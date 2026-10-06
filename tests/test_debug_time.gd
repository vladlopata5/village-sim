extends SceneTree
const GameTime = preload("res://scripts/game_time.gd")
const Intent = preload("res://scripts/resident_intent.gd")
var failures := 0
var minutes: Array[int] = []
var phases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.shift_pressed = true
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.shift_pressed = true
	root.push_input(event, true)

func click(world: Vector2, button: MouseButton, view: Node2D) -> void:
	var event := InputEventMouseButton.new()
	event.position = view.get_canvas_transform() * world
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = InputEventMouseButton.new()
	event.position = view.get_canvas_transform() * world
	event.button_index = button
	root.push_input(event, true)

func _run() -> void:
	var clock = GameTime.new()
	root.add_child(clock)
	clock.set_process(false)
	clock.minute_changed.connect(func(value: int): minutes.append(value))
	clock.phase_changed.connect(func(value: String): phases.append(value))
	for speed in [1, 2, 4, 10, 20]:
		clock.set_speed(speed)
		for paused_case in [false, true]:
			self.paused = paused_case
			clock.total_minutes = 360
			minutes.clear()
			phases.clear()
			clock.debug_skip_minutes(60)
			check(clock.total_minutes == 420 and minutes.size() == 60 and phases == ["День"], "Hour jump emits each minute and phase regardless of speed/pause")
			clock.debug_skip_minutes(360)
			check(clock.total_minutes == 780 and minutes.size() == 420, "Six-hour jump independent of speed/pause")
			check(self.paused == paused_case and clock.speed_multiplier == speed, "Debug keeps pause and speed")
	clock.total_minutes = 1010
	phases.clear()
	minutes.clear()
	clock.debug_skip_minutes(360)
	check(phases == ["Вечер"] and minutes.size() == 360, "Skip emits crossed boundary")
	clock.debug_skip_minutes(360)
	check(phases == ["Вечер", "Ночь"], "Skip across midnight keeps night phase")
	clock.total_minutes = 350
	phases.clear()
	clock.debug_skip_minutes(1440)
	check(phases == ["Утро", "День", "Вечер", "Ночь"], "Long jump emits all crossed phases in order")
	for sample in [[380, 420], [900, 1020], [1410, 1800], [360, 420], [420, 1020], [1020, 1380], [1380, 1800], [0, 360]]:
		clock.total_minutes = sample[0]
		minutes.clear()
		phases.clear()
		clock.debug_next_phase()
		check(clock.total_minutes == sample[1] and minutes.size() == sample[1] - sample[0] and phases.size() == 1, "Next phase chooses strictly next boundary and emits signals")
	self.paused = false
	clock.set_speed(1)
	clock.total_minutes = 380
	clock.advance(0.5)
	clock.debug_next_phase()
	clock.advance(0.5)
	check(clock.total_minutes == 420, "Next phase resets fractional time for exact boundary")
	clock.advance(0.5)
	check(clock.total_minutes == 421, "Normal time resumes after jump")
	clock.queue_free()

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	await process_frame
	await process_frame
	clock = scene.get_node("GameTime")
	clock.set_process(false)
	var view = scene.resident_runtimes[0].view
	view.set_process(false)
	var intents = scene.resident_runtimes[0].intents
	var night = scene.resident_runtimes[0].schedule
	self.paused = true
	key(KEY_1)
	check(clock.total_minutes == 420 and scene.clock_label.text == "07:00", "Shift+1 on pause updates clock through GameTime")
	key(KEY_2)
	check(clock.total_minutes == 780 and scene.clock_label.text == "13:00", "Shift+2 on pause advances six hours")
	key(KEY_2, true)
	check(clock.total_minutes == 780, "Repeated key event does not jump")
	key(KEY_3)
	check(clock.total_minutes == 1020 and scene.phase_label.text == "Вечер", "Shift+3 updates phase UI via signal")
	# Start fresh morning through normal debug progression.
	key(KEY_3)
	key(KEY_3)
	check(clock.total_minutes == 1800 and not night.is_night, "Next day starts at 06:00")
	click(view.global_position, MOUSE_BUTTON_LEFT, view)
	var target := Vector2(-200, 100)
	click(target, MOUSE_BUTTON_RIGHT, view)
	check(intents.current_intent.reason_id == &"player_move", "Actual right click creates PlayerCommand")
	key(KEY_3)
	key(KEY_3)
	key(KEY_3)
	check(clock.get_clock_text() == "23:00" and intents.current_intent.reason_id == &"player_move", "Shift+3 updates schedule but active PlayerCommand overrides night")
	click(target, MOUSE_BUTTON_RIGHT, view)
	check(intents.current_intent.reason_id == &"player_move", "Night accepts replacement PlayerCommand")
	var before: Vector2 = view.global_position
	view._process(0.5)
	check(view.global_position == before, "Debug night on pause does not move resident")
	self.paused = false
	view._process(20)
	check(scene.resident_runtimes[0].commands.active_command == null, "PlayerCommand completes on arrival")
	night.resume_current_phase() # Decision is removed in this isolated clock fixture.
	before = view.global_position
	view._process(0.5)
	check(view.global_position.distance_to(scene.world_locations.get_position(scene.residents[0].home_location_id)) < before.distance_to(scene.world_locations.get_position(scene.residents[0].home_location_id)), "Resident moves toward home after resume")
	self.paused = true
	before = view.global_position
	key(KEY_3)
	check(clock.get_clock_text() == "06:00" and not night.is_night and intents.current_intent.type == Intent.Type.NONE and not view.has_movement_target, "Morning clears unfinished night goal and unlocks manual input")
	check(view.global_position == before, "Morning does not teleport or assign movement")
	click(target, MOUSE_BUTTON_RIGHT, view)
	check(intents.current_intent.reason_id == &"player_move", "Actual morning right click works again")
	self.paused = false
	view._process(0.5)
	check(view.global_position != before, "Morning manual movement resumes")
	check(scene.residents[0].fatigue >= 0 and scene.residents[0].fatigue <= 100 and scene.residents[0].mood == 65, "Debug and morning leave mood unchanged and fatigue bounded")
	scene.queue_free()
	print("Debug time checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
