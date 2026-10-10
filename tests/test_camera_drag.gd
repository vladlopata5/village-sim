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
	var zoom_before := camera.size
	for yaw in [45.0,-25.0]:
		camera.rotation_degrees.y = yaw
		for zoom_size in [camera.min_zoom,camera.max_zoom]:
			camera.size = zoom_size
			for relative in [Vector2(40,0),Vector2(-40,0),Vector2(0,40),Vector2(0,-40),Vector2(30,-20)]:
				camera.global_position = position_before
				var screen_before := camera.unproject_position(Vector3.ZERO)
				camera.drag_pan(relative)
				var screen_delta := camera.unproject_position(Vector3.ZERO)-screen_before
				check(screen_delta.distance_to(relative)<0.001,"Grab-map screen displacement equals mouse delta at either yaw/zoom")
				check(is_equal_approx(camera.global_position.y,position_before.y) and camera.rotation_degrees.is_equal_approx(Vector3(rotation_before.x,yaw,rotation_before.z)),"Drag changes neither height nor pitch/yaw")
	camera.global_position = position_before
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var width_screen := camera.unproject_position(Vector3.ZERO)
	camera.drag_pan(Vector2(40,20))
	check((camera.unproject_position(Vector3.ZERO)-width_screen).distance_to(Vector2(40,20))<0.001,"Drag respects orthographic KEEP_WIDTH aspect mode too")
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.rotation_degrees = rotation_before
	camera.global_position = position_before
	camera.size = camera.min_zoom
	camera.drag_pan(Vector2(40,20))
	var close_distance := camera.global_position.distance_to(position_before)
	camera.global_position = position_before
	camera.size = camera.max_zoom
	camera.drag_pan(Vector2(40,20))
	check(is_equal_approx(camera.global_position.distance_to(position_before)/close_distance,camera.max_zoom/camera.min_zoom),"Mouse world pan scales linearly with orthographic zoom")
	camera.global_position = position_before
	camera.size = zoom_before
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
		var road_count: int = world.roads.cells().size()
		var building_count: int = world.buildings.size()
		camera.global_position = position_before
		var point := Vector2(1000,600)
		if mode=="UI": point=world.get_node("HUD/DebugPanel").collapse_button.get_global_rect().get_center()
		drag(point,Vector2(25,15))
		await physics_frame
		check(not camera.global_position.is_equal_approx(position_before),"Real MMB input pans in "+mode+" mode")
		check(world.roads.cells().size()==road_count and world.buildings.size()==building_count and actor.commands.active_command==null and world.resident_selection.selected_resident==actor.data,"MMB changes no roads/buildings/commands/selection in "+mode+" mode")
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
	wheel.position = Vector2(1000,600)
	wheel.pressed = true
	root.push_input(wheel,true)
	check(is_equal_approx(camera.size,zoom_before-camera.zoom_step),"Real wheel zoom input unchanged")
	camera._mouse_panning = true
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not camera._mouse_panning,"Focus loss stops mouse drag")
	world.free()
	print("Camera MMB drag: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
