extends SceneTree
const Controller = preload("res://scripts/resident_schedule_controller.gd")
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

func schedule_move(point: Vector2) -> void:
	# This suite isolates the old low-priority schedule source. RMB is tested separately.
	var scene = root.get_node("Main")
	var selected = scene.resident_selection.selected_resident
	if selected != null:
		var field = scene.get_node("World/Field")
		var world_point: Vector2 = field.to_global(field.get_global_transform_with_canvas().affine_inverse() * point)
		scene.get_resident_runtime(selected).schedule.request_manual_move(world_point)
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
	var data_without_ui = load("res://scripts/resident_data.gd").new("test", "Test", 30)
	data_without_ui.home_location_id = &"home_stepan"
	intents_without_ui.setup(data_without_ui)
	var locations = load("res://scripts/world_locations_2d.gd").new()
	var marker := Node2D.new()
	root.add_child(marker)
	marker.position = Vector2(100, 200)
	locations.register(load("res://scripts/world_location.gd").new(&"home_stepan", "Дом"), marker)
	var house = load("res://scripts/building_instance.gd").new(&"home_stepan", load("res://scripts/building_definition.gd").for_type(load("res://scripts/building_type.gd").Type.HOME))
	controller_without_ui.setup(clock_without_ui, locations, intents_without_ui, [house])
	check(commands == [Vector2(100, 200)], "Night setup issues home command without UI")
	check(not controller_without_ui.request_manual_move(Vector2.ZERO), "Night controller rejects manual movement")
	clock_without_ui.advance(420.0)
	check(not controller_without_ui.is_night, "06:00 releases night priority")
	check(controller_without_ui.request_manual_move(Vector2.ZERO), "Morning controller allows manual movement")
	clock_without_ui.queue_free()
	controller_without_ui.queue_free()
	intents_without_ui.queue_free()
	marker.queue_free()

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	await process_frame
	await process_frame
	var clock = scene.get_node("GameTime")
	var controller = scene.resident_runtimes[0].schedule
	var intents = scene.resident_runtimes[0].intents
	var view = scene.resident_runtimes[0].view
	var home: Node2D = scene.get_node("World/home_stepan")
	var field: Node2D = scene.get_node("World/Field")
	var selection = scene.get_node("ResidentSelection")
	clock.set_process(false)
	view.set_process(false)
	var start: Vector2 = view.global_position
	check(scene.world_locations.get_position(scene.residents[0].home_location_id) == home.global_position, "Controller uses ordinary house view coordinates")
	for multiplier in [1, 2, 4]:
		# Re-enter a non-night phase through real clock transitions.
		if controller.is_night:
			clock.set_speed(1)
			clock.total_minutes = 1799
			clock.advance(1.0)
		selection.select(scene.residents[0])
		var manual_target := Vector2(-100, 180)
		schedule_move(field.get_global_transform_with_canvas() * manual_target)
		check(view.target_position.is_equal_approx(field.to_global(manual_target)), "Low-priority move routes through controller")
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
		selection.select(scene.residents[0])
		schedule_move(field.get_global_transform_with_canvas() * manual_target)
		check(view.target_position == home.global_position, "Night low-priority move cannot override home")
		view._process(30.0)
		check(view.global_position == home.global_position and not view.has_movement_target, "Stops at home")
		check(intents.current_intent.type == ResidentIntent.Type.NONE, "Home arrival clears intent")
		schedule_move(field.get_global_transform_with_canvas() * manual_target)
		check(view.global_position == home.global_position and not view.has_movement_target, "Night low-priority move cannot send resident away after arrival")
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
	schedule_move(field.get_global_transform_with_canvas() * Vector2(-100, 180))
	check(view.target_position == home.global_position, "Night priority holds on pause")
	clock.toggle_pause()
	view._process(0.125)
	check(view.global_position.is_equal_approx(paused_position.move_toward(home.global_position, 60.0)), "Home movement resumes without a jump at selected speed")
	clock.set_speed(1)
	clock.total_minutes = 1799
	clock.advance(1.0)
	schedule_move(field.get_global_transform_with_canvas() * Vector2(-100, 180))
	check(not controller.is_night and view.target_position.is_equal_approx(Vector2(-100, 180)), "Morning restores manual commands")
	var data = scene.residents[0]
	check(data.fatigue >= 0 and data.fatigue <= 100 and data.mood == 65 and data.traits.is_empty(), "Night reaction keeps fatigue bounded and preserves mood/traits")
	scene.queue_free()
	print("Night home checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
