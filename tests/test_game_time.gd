extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
var failures: int = 0
var transitions: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	check(clock.get_clock_text() == "06:00", "Initial clock")
	for speed in [1, 2, 4]:
		clock.total_minutes = 360
		clock.set_speed(speed)
		clock.advance(10.0)
		check(clock.total_minutes == 360 + 10 * speed, "Speed x%d" % speed)
	clock.set_speed(1)
	clock.total_minutes = 360
	for _frame in range(100):
		clock.advance(0.125)
	check(clock.total_minutes == 372, "Fractional frame accumulation")
	clock.advance(0.5)
	check(clock.total_minutes == 373, "Fractional remainder preserved")
	paused = true
	clock.set_speed(4)
	clock.advance(100.0)
	check(clock.total_minutes == 373, "Pause stops time even after changing speed")
	paused = false
	clock.advance(1.0)
	check(clock.total_minutes == 377, "Resume at selected speed")
	clock.set_speed(3)
	check(clock.speed_multiplier == 4, "Reject unsupported speed")
	var boundaries := {359: "Ночь", 360: "Утро", 419: "Утро", 420: "День", 1019: "День", 1020: "Вечер", 1379: "Вечер", 1380: "Ночь", 1440: "Ночь"}
	for minute in boundaries:
		clock.total_minutes = minute
		check(clock.get_phase() == boundaries[minute], "Phase boundary %d" % minute)
	clock.total_minutes = 1439
	clock.set_speed(1)
	clock.advance(1.0)
	check(clock.get_clock_text() == "00:00", "Midnight rollover")
	clock.total_minutes = 360
	clock.phase_changed.connect(func(phase: String): transitions.append(phase))
	clock.advance(1440.0)
	check(transitions == ["День", "Вечер", "Ночь", "Утро"], "Long frame emits every crossed phase")
	# Equal elapsed time with different frame sizes gives equal simulation time.
	var slow = Clock.new()
	var fast = Clock.new()
	root.add_child(slow)
	root.add_child(fast)
	slow.set_process(false)
	fast.set_process(false)
	for _frame in range(30):
		slow.advance(0.5)
	for _frame in range(120):
		fast.advance(0.125)
	check(slow.total_minutes == fast.total_minutes, "Frame rate independence")
	clock.queue_free()
	slow.queue_free()
	fast.queue_free()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	var scene_clock = scene.get_node("GameTime")
	scene_clock.set_process(false)
	check(scene.clock_label.text == "06:00", "Scene initial HUD")
	scene.speed_buttons[2].pressed.emit()
	check(scene_clock.speed_multiplier == 4, "HUD speed button")
	scene.pause_button.pressed.emit()
	check(paused and scene.pause_button.text == "Продолжить", "HUD pause button")
	var paused_minutes: int = scene_clock.total_minutes
	scene_clock.advance(100.0)
	check(scene_clock.total_minutes == paused_minutes, "Scene pause freezes clock")
	check(scene.get_node("World").can_process() == false, "World paused")
	check(scene.get_node("World/Camera2D").can_process(), "Camera available while paused")
	check(scene.get_node("HUD").can_process(), "HUD available while paused")
	scene.pause_button.pressed.emit()
	check(not paused, "HUD resume button")
	scene_clock.total_minutes = 419
	scene_clock.advance(0.25)
	check(scene.phase_label.text == "День", "Phase signal updates HUD")
	check(scene.get_node("World/Field").modulate == Color.WHITE, "Phase signal updates field")
	scene.queue_free()
	print("Time checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
