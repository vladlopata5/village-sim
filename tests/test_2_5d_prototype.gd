extends SceneTree
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
const Command = preload("res://scripts/player_command.gd")
const Activity = preload("res://scripts/resident_activity.gd")
var checks := 0
var failures := 0
var arrivals := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(button: MouseButton, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
func _run() -> void:
	check(Coordinates.to_world(Vector2(2, 7)) == Vector3(2, 0, 7), "Simulation coordinates map explicitly to X/Z")
	check(Coordinates.to_world(Vector2(2, 7), 4) == Vector3(2, 4, 7), "Optional height is presentation Y")
	check(Coordinates.to_sim(Vector3(2, 100, 7)) == Vector2(2, 7), "Height is excluded from simulation coordinates")
	check(Coordinates.on_ground(Vector3(2, 100, 7)) == Vector3(2, 0, 7), "Ground projection removes height")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main_3d.tscn", "Canonical project startup uses the migrated 3D main scene")
	var scene = load("res://scenes/prototypes/2_5d_prototype.tscn").instantiate()
	root.add_child(scene)
	scene.movement.set_physics_process(false)
	var camera: Camera3D = scene.get_node("Camera3D")
	camera.set_process(false)
	await physics_frame
	await process_frame
	check(scene.resident_view.entity == scene.resident and scene.building_view.entity == scene.building, "Views reference existing domain data")
	check(scene.selection.selected_entity == null, "Prototype starts without selection")
	check(not scene.resident_view.get_node("SelectionIndicator").visible and not scene.building_view.get_node("SelectionIndicator").visible, "Indicators start hidden")
	var grid = scene.get_node("VisualGrid")
	check(grid is MeshInstance3D and grid.get_child_count() == 0, "Grid is a mesh without physics bodies or colliders")
	check(grid.CELL_SIZE == 1.0 and grid.CELL_COUNT == 30, "Visual scale reference covers 30 by 30 unit cells")
	check(grid.basis == Basis.IDENTITY and is_equal_approx(grid.mesh.get_aabb().size.x, 30.0) and is_equal_approx(grid.mesh.get_aabb().size.z, 30.0), "Grid stays axis-aligned on X/Z with expected extent")
	# Real 3D collision queries; node names are not used to identify entities.
	var input_controller = scene.input_controller
	var resident_point := camera.unproject_position(scene.resident_view.global_position + Vector3(0, 0.9, 0))
	var building_point := camera.unproject_position(scene.building_view.global_position + Vector3(0, 1.5, 0))
	var ground_point := camera.unproject_position(Vector3(-6, 0, 5))
	var resident_hit: Dictionary = input_controller.pick(resident_point)
	var building_hit: Dictionary = input_controller.pick(building_point)
	var ground_hit: Dictionary = input_controller.pick(ground_point)
	check(resident_hit.get("collider") == scene.resident_view, "Raycast hits resident capsule")
	check(building_hit.get("collider") == scene.building_view, "Raycast hits building box")
	check(ground_hit.get("collider") == scene.get_node("Ground"), "Raycast through visual grid lines still hits ground")
	scene.resident_view.name = "ArbitraryPickableName"
	input_controller.handle_hit(MOUSE_BUTTON_LEFT, resident_hit)
	check(scene.selection.selected_resident == scene.resident and scene.selection.selected_building == null, "Resident picking stores data, exclusively")
	check(scene.resident_view.get_node("SelectionIndicator").visible, "Resident selection has a visible indicator")
	check(scene.get_node("HUD/Panel/Column/Selected").text.contains("Resident:"), "Resident debug information is shown")
	input_controller.handle_hit(MOUSE_BUTTON_LEFT, building_hit)
	check(scene.selection.selected_building == scene.building and scene.selection.selected_resident == null, "Building selection clears resident selection")
	check(scene.building_view.get_node("SelectionIndicator").visible and not scene.resident_view.get_node("SelectionIndicator").visible, "Only selected building has indicator")
	check(scene.get_node("HUD/Panel/Column/Selected").text.contains("Building:"), "Building debug information is shown")
	input_controller.handle_hit(MOUSE_BUTTON_RIGHT, ground_hit)
	check(scene.control.current_command == null, "Building selection cannot issue a resident MOVE_TO")
	input_controller.handle_hit(MOUSE_BUTTON_LEFT, ground_hit)
	check(scene.selection.selected_entity == null, "Left click on empty ground clears selection")
	check(not scene.building_view.get_node("SelectionIndicator").visible, "Clear removes building indicator")
	# Input is routed through the real viewport, including GUI blocking.
	click(MOUSE_BUTTON_LEFT, resident_point)
	await physics_frame
	await physics_frame
	check(scene.selection.selected_resident == scene.resident, "Unhandled world left click selects resident")
	click(MOUSE_BUTTON_LEFT, Vector2(24, 24))
	click(MOUSE_BUTTON_RIGHT, Vector2(24, 24))
	await physics_frame
	await physics_frame
	check(scene.selection.selected_resident == scene.resident and scene.control.current_command == null, "HUD consumes left/right clicks before world input")
	click(MOUSE_BUTTON_RIGHT, ground_point)
	await physics_frame
	await physics_frame
	check(scene.control.current_command != null and scene.movement.is_moving(), "Ground right click creates an active MOVE_TO request")
	check(scene.control.current_command.type == Command.Type.MOVE_TO and scene.control.current_command.state == Command.State.ACTIVE, "Committed command uses existing PlayerCommand data")
	check(scene.control.current_command.target is Vector2 and scene.control.current_command.target.is_equal_approx(Coordinates.to_sim(ground_hit.position)), "Command owns a simulation-plane destination")
	check(scene.movement.target_position().y == 0, "Movement target stays on the ground")
	var command = scene.control.current_command
	input_controller.handle_hit(MOUSE_BUTTON_RIGHT, building_hit)
	check(scene.control.current_command == command, "Right click on building cannot issue ground movement")
	input_controller.handle_hit(MOUSE_BUTTON_LEFT, building_hit)
	check(scene.movement.is_moving(), "Changing selection does not cancel a committed MOVE_TO")
	scene.selection.select(scene.resident)
	await physics_frame
	scene.control.move_to(Vector2(-3, 6))
	check(command.state == Command.State.CANCELLED and scene.control.current_command != command, "New command replaces previous movement request")
	check(scene.movement.target_position().is_equal_approx(Vector3(-3, 0, 6)), "Request crosses the coordinate adapter into movement target")
	scene.movement.arrived.connect(func(): arrivals += 1)
	var before_step: Vector3 = scene.resident_view.global_position
	await physics_frame
	scene.movement.advance(0.1)
	check(scene.resident_view.global_position.distance_to(before_step) <= scene.movement.speed * 0.1 + 0.001, "Navigation step never exceeds movement speed")
	check(scene.movement.is_moving() and arrivals == 0, "Unfinished movement remains active")
	for frame in range(300):
		await physics_frame
		scene.movement.advance(0.05)
		if not scene.movement.is_moving(): break
	check(scene.resident_view.global_position.distance_to(Vector3(-3, 0, 6)) <= scene.movement.agent.target_desired_distance and not scene.movement.is_moving(), "Navigation arrives within tolerance without overshoot")
	check(arrivals == 1 and scene.control.current_command.state == Command.State.COMPLETED and scene.resident.activity == Activity.Type.IDLE, "Arrival completes command and restores idle exactly once")
	scene.movement.advance(100.0)
	check(arrivals == 1, "Idle movement emits no repeated arrival")
	await physics_frame
	scene.control.move_to(Vector2(-3, 6))
	await physics_frame
	scene.movement.advance(0.0)
	check(not scene.movement.is_moving() and scene.control.current_command.state == Command.State.COMPLETED, "Already at target completes without a new trip")
	scene.control.move_to(Vector2(-8, 4))
	scene.control.cancel_move()
	var stopped: Vector3 = scene.resident_view.global_position
	scene.movement.advance(10.0)
	check(not scene.movement.is_moving() and scene.resident_view.global_position == stopped and scene.control.current_command.state == Command.State.CANCELLED, "Stop cancels request without moving or completing it")
	check(not scene.control.move_to(Vector2(NAN, 0)), "Non-finite targets are rejected before movement")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(scene.selection.selected_entity == null, "Esc clears selection")
	check(not scene.control.move_to(Vector2(1, 1)), "No selection cannot issue MOVE_TO")
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(camera.rotation_degrees.x, -50.0), "Prototype uses orthographic projection at 50 degrees")
	check(is_equal_approx(camera.rotation_degrees.y, 45.0), "Camera yaw is diagonal relative to unchanged world axes")
	camera.zoom(100)
	check(camera.size == camera.min_zoom, "Zoom-in is bounded")
	camera.zoom(-100)
	check(camera.size == camera.max_zoom, "Zoom-out is bounded")
	check_camera_pan(camera)
	scene.free()
	print("2.5D prototype: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check_camera_pan(camera: Camera3D) -> void:
	var original_position := camera.global_position
	var original_rotation := camera.rotation_degrees
	var original_size := camera.size
	# Screen projection checks are independent of hardcoded world directions.
	for yaw in [45.0, -20.0, 110.0]:
		camera.rotation_degrees.y = yaw
		for zoom_size in [camera.min_zoom, camera.max_zoom]:
			camera.size = zoom_size
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1,-1), Vector2(-1,-1), Vector2(1,1), Vector2(-1,1)]:
				camera.global_position = original_position
				var screen_before := camera.unproject_position(Vector3.ZERO)
				camera.pan(direction, 0.25)
				var displacement := camera.global_position-original_position
				var screen_delta := camera.unproject_position(Vector3.ZERO)-screen_before
				check(is_zero_approx(displacement.y) and is_equal_approx(displacement.length(),camera.movement_speed*0.25),"Camera pan preserves height and speed, including diagonals")
				check((is_zero_approx(direction.x) and absf(screen_delta.x)<0.001) or screen_delta.x*direction.x<0,"Camera horizontal pan follows screen orientation at any yaw/zoom")
				check((is_zero_approx(direction.y) and absf(screen_delta.y)<0.001) or screen_delta.y*direction.y<0,"Camera vertical pan follows projected forward at any yaw/zoom")
	camera.global_position = original_position
	camera.pan(Vector2.RIGHT, -1.0)
	check(camera.global_position.is_equal_approx(original_position),"Negative delta cannot pan camera")
	camera.pan(Vector2.ZERO, 1.0)
	check(camera.global_position.is_equal_approx(original_position),"No input leaves camera unchanged")
	camera.rotation_degrees = original_rotation
	camera.size = original_size
