extends SceneTree
const Controller = preload("res://scripts/night_home_controller.gd")
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const Clock = preload("res://scripts/game_time.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func right_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	# The time reaction also works without Main, a renderer, selection or UI.
	var clock_without_ui = Clock.new()
	root.add_child(clock_without_ui)
	clock_without_ui.set_process(false)
	clock_without_ui.total_minutes = 1380
	var controller_without_ui = Controller.new()
	root.add_child(controller_without_ui)
	var commands: Array[Vector2] = []
	var intents_without_ui = IntentController.new()
	root.add_child(intents_without_ui)
	intents_without_ui.intent_changed.connect(func(intent): commands.append(intent.target_position))
	controller_without_ui.setup(clock_without_ui, Vector2(100, 200), intents_without_ui)
	check(commands == [Vector2(100, 200)], "Night setup issues home command without UI")
	check(not controller_without_ui.request_manual_move(Vector2.ZERO), "Night controller rejects manual movement")
	clock_without_ui.advance(420.0)
	check(not controller_without_ui.is_night, "06:00 releases night priority")
	check(controller_without_ui.request_manual_move(Vector2.ZERO), "Morning controller allows manual movement")
	clock_without_ui.queue_free()
	controller_without_ui.queue_free()
	intents_without_ui.queue_free()

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var clock = scene.get_node("GameTime")
	var controller = scene.get_node("NightHomeController")
	var intents = scene.get_node("ResidentIntentController")
	var view = scene.get_node("World/ResidentView2D")
	var home: Marker2D = scene.get_node("World/HomePoint")
	var field: Node2D = scene.get_node("World/Field")
	var selection = scene.get_node("ResidentSelection")
	clock.set_process(false)
	view.set_process(false)
	var start: Vector2 = view.global_position
	check(controller.home_position == home.global_position, "Controller uses marker coordinates")
	for multiplier in [1, 2, 4]:
		# Re-enter a non-night phase through real clock transitions.
		if controller.is_night:
			clock.set_speed(1)
			clock.total_minutes = 1799
			clock.advance(1.0)
		selection.select(scene.resident_data)
		var manual_target := Vector2(-100, 180)
		right_click(field.get_global_transform_with_canvas() * manual_target)
		check(view.target_position.is_equal_approx(field.to_global(manual_target)), "Day click routes through controller")
		selection.clear()
		view.global_position = start
		clock.total_minutes = 1379
		clock.set_speed(multiplier)
		clock.advance(1.0 / multiplier)
		check(clock.get_clock_text() == "23:00" and controller.is_night, "Night starts at 23:00 on x%d" % multiplier)
		check(view.target_position == home.global_position, "Night replaces previous goal without selection on x%d" % multiplier)
		view._process(0.125)
		var expected: Vector2 = start.move_toward(home.global_position, 15.0 * multiplier)
		check(view.global_position.is_equal_approx(expected), "Home movement speed x%d" % multiplier)
		selection.select(scene.resident_data)
		right_click(field.get_global_transform_with_canvas() * manual_target)
		check(view.target_position == home.global_position, "Night right click cannot override home")
		view._process(30.0)
		check(view.global_position == home.global_position and not view.has_movement_target, "Stops at home")
		check(intents.current_intent.type == ResidentIntent.Type.NONE, "Home arrival clears intent")
		right_click(field.get_global_transform_with_canvas() * manual_target)
		check(view.global_position == home.global_position and not view.has_movement_target, "Night click cannot send resident away after arrival")
		clock.total_minutes = 1439
		clock.advance(1.0 / multiplier)
		check(controller.is_night, "Midnight keeps night priority")

	# Fresh night transition; pause keeps the automatic goal but halts movement.
	clock.set_speed(1)
	clock.total_minutes = 1799
	clock.advance(1.0)
	view.global_position = start
	clock.total_minutes = 1379
	clock.advance(1.0)
	clock.toggle_pause()
	var paused_position: Vector2 = view.global_position
	view.set_process(true)
	await create_timer(0.1, true).timeout
	view.set_process(false)
	check(view.global_position == paused_position, "Automatic movement stops during actual paused frames")
	clock.advance(1000.0)
	check(clock.get_clock_text() == "23:00", "Clock does not leave night on pause")
	clock.set_speed(4)
	right_click(field.get_global_transform_with_canvas() * Vector2(-100, 180))
	check(view.target_position == home.global_position, "Night priority holds on pause")
	clock.toggle_pause()
	view._process(0.125)
	check(view.global_position.is_equal_approx(paused_position.move_toward(home.global_position, 60.0)), "Home movement resumes without a jump at selected speed")
	clock.set_speed(1)
	clock.total_minutes = 1799
	clock.advance(1.0)
	right_click(field.get_global_transform_with_canvas() * Vector2(-100, 180))
	check(not controller.is_night and view.target_position.is_equal_approx(Vector2(-100, 180)), "Morning restores manual commands")
	var data = scene.resident_data
	check(data.hunger == 20 and data.fatigue == 35 and data.mood == 65 and data.traits.size() == 3, "Night reaction never changes resident states or traits")
	scene.queue_free()
	print("Night home checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
