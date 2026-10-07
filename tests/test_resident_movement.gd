extends SceneTree
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func click_at(point: Vector2, button: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	await process_frame
	await process_frame
	var view = scene.resident_runtimes[0].view
	var selection = scene.get_node("ResidentSelection")
	var clock = scene.get_node("GameTime")
	var card = scene.get_node("HUD/ResidentCard")
	var field: Node2D = scene.get_node("World/Field")
	var camera: Camera2D = scene.get_node("World/Camera2D")
	view.set_process(false)
	clock.set_process(false)
	var origin: Vector2 = view.global_position
	var field_target := Vector2(-200, 100)
	click_at(field.get_global_transform_with_canvas() * field_target)
	check(not view.has_movement_target, "Right click without selection does nothing")
	click_at(view.get_global_transform_with_canvas() * Vector2.ZERO, MOUSE_BUTTON_LEFT)
	click_at(field.get_global_transform_with_canvas() * field_target)
	check(view.has_movement_target and view.target_position.is_equal_approx(field.to_global(field_target)), "Right click assigns the selected resident's target")
	check(selection.selected_resident == scene.residents[0] and card.visible, "Movement command preserves selection and card")
	# Controlled frame intervals test speed scaling using the real frame callback.
	for multiplier in [1, 2, 4]:
		view.global_position = origin
		view.move_to(origin + Vector2(1000, 0))
		clock.set_speed(multiplier)
		view._process(0.5)
		check(view.global_position.is_equal_approx(origin + Vector2(60 * multiplier, 0)), "Distance at x%d" % multiplier)
	# Equal elapsed time with different frame sizes yields equal movement.
	clock.set_speed(1)
	view.global_position = origin
	view.move_to(origin + Vector2(1000, 0))
	for _frame in range(4):
		view._process(0.25)
	var slow_frames: Vector2 = view.global_position
	view.global_position = origin
	view.move_to(origin + Vector2(1000, 0))
	for _frame in range(8):
		view._process(0.125)
	check(view.global_position.is_equal_approx(slow_frames), "Movement independent of frame count")
	view.global_position = origin
	view.move_to(origin + Vector2(300, 400))
	view._process(0.5)
	check(is_equal_approx(view.global_position.distance_to(origin), 60.0), "Diagonal has the same constant speed")
	view.move_to(origin + Vector2(-10, -10))
	view._process(10.0)
	check(view.global_position.is_equal_approx(origin + Vector2(-10, -10)) and not view.has_movement_target, "Stops at target without overshoot")
	var stopped_position: Vector2 = view.global_position
	view._process(10.0)
	check(view.global_position == stopped_position, "Remains stopped after arrival")
	view.global_position = origin
	view.move_to(origin + Vector2(1000, 0))
	for multiplier in [1, 2, 4]:
		clock.set_speed(multiplier)
		view._process(0.25)
	check(view.global_position.is_equal_approx(origin + Vector2(210, 0)), "Speed changes apply during motion")
	# Let real engine frames run during pause: input stays active, movement does not.
	clock.toggle_pause()
	view.set_process(true)
	var paused_position: Vector2 = view.global_position
	await create_timer(0.1, true).timeout
	check(view.global_position == paused_position, "Actual paused frames never move resident")
	view.set_process(false)
	view._process(30.0)
	check(view.global_position == paused_position, "Paused frame never accumulates movement")
	clock.set_speed(2)
	var paused_target := Vector2(-100, 150)
	click_at(field.get_global_transform_with_canvas() * paused_target)
	check(view.target_position.is_equal_approx(field.to_global(paused_target)), "New target can be assigned on pause")
	check(view.global_position == paused_position, "Command on pause does not move resident")
	clock.toggle_pause()
	view._process(0.125)
	var expected_resume: Vector2 = paused_position.move_toward(view.target_position, 30.0)
	check(view.global_position.is_equal_approx(expected_resume), "Resume advances one current frame without catch-up")
	# UI must not leak right clicks into movement commands.
	var target_before_ui: Vector2 = view.target_position
	click_at(card.name_label.get_global_rect().get_center())
	click_at(scene.pause_button.get_global_rect().get_center())
	check(view.target_position == target_before_ui and selection.selected_resident == scene.residents[0], "Right clicks on UI do not issue movement commands")
	camera.position = Vector2(200, 100)
	camera.force_update_scroll()
	await process_frame
	var camera_target := Vector2(-150, 180)
	click_at(field.get_global_transform_with_canvas() * camera_target)
	check(view.target_position.is_equal_approx(field.to_global(camera_target)), "Target coordinates account for camera movement")
	camera.position = Vector2(1500, 0)
	camera.force_update_scroll()
	await process_frame
	var previous_target: Vector2 = view.target_position
	click_at(field.get_global_transform_with_canvas() * Vector2(1900, 200))
	check(view.target_position == previous_target, "Clicks outside the field are ignored")
	# Run real unpaused frames to confirm automatic movement is wired.
	camera.position = Vector2.ZERO
	camera.force_update_scroll()
	view.global_position = origin
	view.move_to(origin + Vector2(1000, 0))
	view.set_process(true)
	await create_timer(0.1, true).timeout
	view.set_process(false)
	check(view.global_position.x > origin.x, "Actual unpaused frames move resident")
	# Clearing selection does not turn off an already issued command.
	selection.clear()
	view._process(0.125)
	check(view.has_movement_target and not card.visible, "Issued command continues independently of selection")
	var data = scene.residents[0]
	check(data.hunger == 20 and data.fatigue == 35 and data.mood == 65 and data.traits.is_empty(), "Movement never changes states or traits")
	scene.queue_free()
	print("Movement checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
