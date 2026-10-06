extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const Data = preload("res://scripts/resident_data.gd")
const Hunger = preload("res://scripts/need_dynamics.gd")
const Activity = preload("res://scripts/resident_activity.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func key(code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.shift_pressed = true
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
func _run() -> void:
	# No scene, renderer or UI needed; equal game time at different speeds/FPS.
	for speed in [1, 2, 4]:
		for frames in [1, 30, 120]:
			var speed_clock = Clock.new()
			root.add_child(speed_clock)
			speed_clock.set_process(false)
			speed_clock.set_speed(speed)
			var speed_data = Data.new("test", "Тест", 30)
			speed_data.hunger = 20
			var speed_hunger = Hunger.new()
			root.add_child(speed_hunger)
			speed_hunger.setup(speed_clock, speed_data)
			for _frame in range(frames):
				speed_clock.advance(60.0 / speed / frames)
			# Exact binary fractions above: total minute count is 60.
			check(speed_data.hunger == 24, "Awake hour has same growth on every speed and frame count")
			speed_data.activity = Activity.Type.SLEEPING
			speed_clock.advance(60.0 / speed)
			check(speed_data.hunger == 25, "Sleeping hour grows four times slower")
			speed_data.activity = Activity.Type.WORKING
			speed_clock.advance(15.0 / speed)
			check(speed_data.hunger == 26, "Working uses awake rate")
			paused = true
			speed_clock.advance(1000.0)
			check(speed_data.hunger == 26, "Pause blocks ordinary hunger growth")
			speed_clock.debug_skip_minutes(60)
			check(speed_data.hunger == 30 and paused, "Explicit debug time advances hunger on pause independent of speed")
			paused = false
			speed_clock.queue_free()
			speed_hunger.queue_free()
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	var data = Data.new("fraction", "Тест", 30)
	var hunger = Hunger.new()
	root.add_child(hunger)
	hunger.setup(clock, data)
	clock.advance(14.0)
	check(data.hunger == 0, "Fraction remains below one point")
	data.activity = Activity.Type.SLEEPING
	clock.advance(4.0)
	check(data.hunger == 1, "Fraction carries across activity change")
	data.hunger = 99
	clock.debug_skip_minutes(600)
	check(data.hunger == 100, "Hunger saturates at 100")
	clock.queue_free()
	hunger.queue_free()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	scene.resident_runtimes[0].schedule.before_work = Callable()
	await process_frame
	await process_frame
	clock = scene.game_time
	clock.set_process(false)
	var view = scene.resident_runtimes[0].view
	view.set_process(false)
	data = scene.residents[0]
	var card = scene.get_node("HUD/ResidentCard")
	key(KEY_4)
	check(data.hunger == 20, "Shift+4 without selection does nothing")
	scene.resident_selection.select(data)
	paused = true
	var minute: int = clock.total_minutes
	key(KEY_4)
	await process_frame
	check(data.hunger == 45 and card.hunger_label.text == "Голод: 45/100 — Немного голоден", "Shift+4 on pause adds 25 and live card reads data")
	key(KEY_4, true)
	check(data.hunger == 45, "Held-key echo is ignored")
	check(clock.total_minutes == minute and paused, "Shift+4 never advances time or changes pause")
	var other = Data.new("other", "Другой", 20)
	scene.resident_selection.select(other)
	key(KEY_4)
	check(other.hunger == 25 and data.hunger == 45, "Shift+4 changes only selected resident")
	scene.resident_selection.select(data)
	key(KEY_4)
	key(KEY_4)
	key(KEY_4)
	check(data.hunger == 100, "Shift+4 respects upper bound")
	key(KEY_3)
	check(scene.resident_runtimes[0].intents.current_intent.reason_id == &"day_work", "Hunger 100 does not override work schedule")
	paused = false
	view._process(20.0)
	check(data.activity == Activity.Type.WORKING, "Hunger 100 does not prevent work arrival")
	key(KEY_3)
	key(KEY_3)
	view._process(20.0)
	check(data.activity == Activity.Type.SLEEPING, "Hunger 100 does not prevent sleep")
	key(KEY_3)
	check(data.activity == Activity.Type.IDLE and data.fatigue >= 0 and data.fatigue <= 100 and data.mood == 65, "Morning still wakes; mood unchanged and fatigue bounded")
	# Data continues to evolve without its visual representation or card selection.
	data.hunger = 20
	scene.resident_selection.clear()
	view.queue_free()
	await process_frame
	clock.debug_skip_minutes(15)
	check(data.hunger == 21 and not card.visible, "Hunger exists independently of view and UI selection")
	scene.queue_free()
	print("Hunger checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
