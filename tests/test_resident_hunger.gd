extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const Data = preload("res://scripts/resident_data.gd")
const Hunger = preload("res://scripts/resident_hunger.gd")
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
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
func _run() -> void:
	# No scene, renderer or UI needed; equal game time at different speeds/FPS.
	for speed in [1, 2, 4]:
		for frames in [1, 30, 120]:
			var clock = Clock.new()
			root.add_child(clock)
			clock.set_process(false)
			clock.set_speed(speed)
			var data = Data.new("test", "Тест", 30, "")
			data.hunger = 20
			var hunger = Hunger.new()
			root.add_child(hunger)
			hunger.setup(clock, data)
			for _frame in range(frames):
				clock.advance(60.0 / speed / frames)
			# Exact binary fractions above: total minute count is 60.
			check(data.hunger == 24, "Awake hour has same growth on every speed and frame count")
			data.activity = Activity.Type.SLEEPING
			clock.advance(60.0 / speed)
			check(data.hunger == 25, "Sleeping hour grows four times slower")
			data.activity = Activity.Type.WORKING
			clock.advance(15.0 / speed)
			check(data.hunger == 26, "Working uses awake rate")
			paused = true
			clock.advance(1000.0)
			check(data.hunger == 26, "Pause blocks ordinary hunger growth")
			clock.debug_skip_minutes(60)
			check(data.hunger == 30 and paused, "Explicit debug time advances hunger on pause independent of speed")
			paused = false
			clock.queue_free()
			hunger.queue_free()
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	var data = Data.new("fraction", "Тест", 30, "")
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
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.get_node("ResidentNeedsController").free()
	await process_frame
	await process_frame
	clock = scene.game_time
	clock.set_process(false)
	var view = scene.resident_view
	view.set_process(false)
	data = scene.resident_data
	var card = scene.get_node("HUD/ResidentCard")
	key(KEY_F9)
	check(data.hunger == 20, "F9 without selection does nothing")
	scene.resident_selection.select(data)
	paused = true
	var minute: int = clock.total_minutes
	key(KEY_F9)
	await process_frame
	check(data.hunger == 45 and card.hunger_label.text == "Голод: 45/100 — Немного голоден", "F9 on pause adds 25 and live card reads data")
	key(KEY_F9, true)
	check(data.hunger == 45, "Held-key echo is ignored")
	check(clock.total_minutes == minute and paused, "F9 never advances time or changes pause")
	var other = Data.new("other", "Другой", 20, "")
	scene.resident_selection.select(other)
	key(KEY_F9)
	check(other.hunger == 25 and data.hunger == 45, "F9 changes only selected resident")
	scene.resident_selection.select(data)
	key(KEY_F9)
	key(KEY_F9)
	key(KEY_F9)
	check(data.hunger == 100, "F9 respects upper bound")
	key(KEY_F8)
	check(scene.resident_intents.current_intent.reason_id == &"day_work", "Hunger 100 does not override work schedule")
	paused = false
	view._process(20.0)
	check(data.activity == Activity.Type.WORKING, "Hunger 100 does not prevent work arrival")
	key(KEY_F8)
	key(KEY_F8)
	view._process(20.0)
	check(data.activity == Activity.Type.SLEEPING, "Hunger 100 does not prevent sleep")
	key(KEY_F8)
	check(data.activity == Activity.Type.IDLE and data.fatigue == 35 and data.mood == 65, "Morning still wakes; fatigue and mood unchanged")
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
