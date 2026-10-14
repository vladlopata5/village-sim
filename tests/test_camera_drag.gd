extends SceneTree
const Definitions = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func drag(point: Vector2, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.position = point
	press.pressed = true
	root.push_input(press,true)
	var motion := InputEventMouseMotion.new()
	motion.position = point+relative
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(motion,true)
	press.pressed = false
	press.position = motion.position
	root.push_input(press,true)
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	var camera: Camera3D = world.get_node("World/Camera3D")
	camera.set_process(false)
	await physics_frame
	await process_frame
	var position_before := camera.global_position
	var rotation_before := camera.rotation_degrees
	var zoom_before: float = camera.get_zoom_distance()
	for yaw in [45.0,-25.0]:
		for distance in [camera.min_distance,camera.max_distance]:
			camera.global_transform=Transform3D(Basis.from_euler(rotation_before*PI/180.0),position_before)
			camera.orbit_to_yaw(yaw)
			camera.set_zoom_distance(distance)
			for relative in [Vector2(40,0),Vector2(-40,0),Vector2(0,40),Vector2(0,-40),Vector2(30,-20)]:
				var cursor:=Vector2(640,360)
				var grabbed: Vector3=Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(cursor),camera.project_ray_normal(cursor))
				var height_before:=camera.global_position.y
				camera.drag_pan(relative,cursor+relative)
				check(camera.unproject_position(grabbed).distance_to(cursor+relative)<0.002,"Perspective grabbed point follows mouse at either yaw/zoom")
				check(is_equal_approx(camera.global_position.y,height_before) and is_equal_approx(camera.rotation_degrees.x,rotation_before.x),"Drag preserves height and pitch")
	camera.global_position=position_before
	camera.rotation_degrees=rotation_before
	camera.set_zoom_distance(zoom_before)
	camera.pan(Vector2.UP,0.25)
	check(is_equal_approx(camera.global_position.distance_to(position_before),camera.movement_speed*0.25),"Keyboard pan speed unchanged")
	camera.global_position = position_before
	var actor = world.resident_runtimes[0]
	world.resident_selection.select(actor.data)
	for mode in ["selection","roads","building","UI"]:
		world._cancel_road_tool()
		world.placement.cancel()
		if mode=="roads": world._select_road_tool()
		if mode=="building": world._select_building_definition(Definitions.for_type(Types.HOME))
		var selection_before = world.resident_selection.selected_entity
		var road_count: int = world.roads.cells().size()
		var building_count: int = world.buildings.size()
		camera.global_position = position_before
		var point := Vector2(1000,600)
		if mode=="UI": point=world.construction_panel.collapse_button.get_global_rect().get_center()
		drag(point,Vector2(25,15))
		await physics_frame
		check(not camera.global_position.is_equal_approx(position_before),"Real MMB input pans in "+mode+" mode")
		check(world.roads.cells().size()==road_count and world.buildings.size()==building_count and actor.commands.active_command==null and world.resident_selection.selected_entity==selection_before,"MMB changes no roads/buildings/commands/selection in "+mode+" mode")
		var stopped := camera.global_position
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(25,15)
		motion.position = point+Vector2(50,30)
		root.push_input(motion,true)
		check(camera.global_position.is_equal_approx(stopped),"MMB release stops drag even over UI")
	world.placement.cancel()
	world._cancel_road_tool()
	camera.global_position = position_before
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = Vector2(700,450) # Uncovered world, not the selected card.
	wheel.pressed = true
	root.push_input(wheel,true)
	check(is_equal_approx(camera.get_zoom_distance(),zoom_before-camera.distance_step),"Real wheel dollies toward original focus")
	camera._mouse_panning = true
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not camera._mouse_panning,"Focus loss stops mouse drag")
	world.free()
	print("Camera MMB drag: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
