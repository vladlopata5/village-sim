extends SceneTree
const Command = preload("res://scripts/player_command.gd")
var checks := 0
var failures := 0
var arrivals := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func make_scene() -> Node:
	var scene = load("res://scenes/prototypes/2_5d_prototype.tscn").instantiate()
	root.add_child(scene)
	scene.get_node("Camera3D").set_process(false)
	scene.movement.set_physics_process(false)
	scene.selection.select(scene.resident)
	for frame in range(30):
		await physics_frame
		var map: RID = scene.movement.agent.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3.ZERO) == scene.get_node("NavigationRegion3D").get_rid(): break
	return scene
func walk(scene: Node, target: Vector2, avoid_building: bool = false) -> bool:
	scene.control.move_to(target)
	var stayed_clear := true
	var obstacle: Rect2 = scene.building.footprint()
	for frame in range(600):
		await physics_frame
		scene.movement.advance(0.05)
		var point: Vector3 = scene.resident_view.global_position
		var ground_point := Vector2(point.x, point.z)
		var closest := ground_point.clamp(obstacle.position, obstacle.end)
		if avoid_building and ground_point.distance_to(closest) < 0.39: stayed_clear = false
		if not scene.movement.is_moving(): break
	check(not scene.movement.is_moving(), "Movement terminates within bounded integration steps")
	return stayed_clear
func _run() -> void:
	var scene = await make_scene()
	var region: NavigationRegion3D = scene.get_node("NavigationRegion3D")
	check(region.navigation_mesh.get_polygon_count() > 0, "Prebaked NavigationMesh is loaded into a real region")
	check(scene.movement.agent.get_parent() == scene.resident_view and not scene.movement.agent.avoidance_enabled, "Agent follows resident; crowd avoidance remains disabled")
	scene.movement.arrived.connect(func(): arrivals += 1)
	scene.control.move_to(Vector2(-3, 6))
	await physics_frame
	scene.movement.advance(0.0)
	check(scene.movement.is_moving() and scene.movement.agent.get_current_navigation_path().size() >= 2, "Target assignment starts a real NavigationAgent path")
	check(scene.get_node("DebugPath").mesh.get_surface_count() == 1, "Active path has visual debug lines")
	await walk(scene, Vector2(-3, 6))
	check(scene.resident_view.global_position.distance_to(Vector3(-3, 0, 6)) <= 0.08, "Resident reaches an unobstructed navigation target")
	check(scene.control.current_command.state == Command.State.COMPLETED and arrivals == 1, "Navigation arrival completes PlayerCommand exactly once")
	var stopped: Vector3 = scene.resident_view.global_position
	for frame in range(3):
		await physics_frame
		scene.movement.advance(0.1)
	check(scene.resident_view.global_position == stopped and arrivals == 1, "Arrival has no jitter or repeated completion")
	check(scene.get_node("DebugPath").mesh.get_surface_count() == 0, "Arrival clears path preview")
	scene.free()
	scene = await make_scene()
	scene.resident_view.global_position = Vector3(-3, 0, 1)
	await physics_frame
	scene.control.move_to(Vector2(9, 1))
	await physics_frame
	scene.movement.advance(0.0)
	var path: PackedVector3Array = scene.movement.agent.get_current_navigation_path()
	check(path.size() > 2, "Building between start and target forces a non-straight path")
	var detour := false
	for point in path:
		if point.z < -0.5 or point.z > 2.5: detour = true
	check(detour, "Real path bends around the building footprint")
	check(await walk(scene, Vector2(9, 1), true), "Every movement step keeps capsule radius clear of static building")
	check(scene.control.current_command.state == Command.State.COMPLETED and scene.resident_view.global_position.distance_to(Vector3(9, 0, 1)) <= 0.08, "Obstacle detour reaches target and completes command")
	check(is_zero_approx(scene.resident_view.global_position.y), "Navigation remains on flat ground")
	await physics_frame
	scene.control.move_to(Vector2(100, 100))
	await physics_frame
	scene.movement.advance(0.0)
	check(not scene.movement.is_moving() and scene.control.current_command.state == Command.State.CANCELLED, "Outside-navmesh target cancels without a stuck command")
	await physics_frame
	scene.control.move_to(Vector2(3, 1))
	await physics_frame
	scene.movement.advance(0.0)
	check(not scene.movement.is_moving() and scene.control.current_command.state == Command.State.CANCELLED, "Building interior is excluded, not a walkable roof")
	await physics_frame
	scene.control.move_to(Vector2(-9, -9))
	scene.control.cancel_move()
	check(not scene.movement.is_moving() and scene.get_node("DebugPath").mesh.get_surface_count() == 0, "Stop cancels navigation and clears preview")
	scene.free()
	# Two disconnected regions test unreachable targets on otherwise valid navmesh.
	scene = await make_scene()
	scene.get_node("NavigationRegion3D").enabled = false
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-4,0,-2),Vector3(-4,0,2),Vector3(0,0,2),Vector3(0,0,-2),Vector3(8,0,-2),Vector3(8,0,2),Vector3(12,0,2),Vector3(12,0,-2)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	mesh.add_polygon(PackedInt32Array([4,5,6,7]))
	var islands := NavigationRegion3D.new()
	islands.navigation_mesh = mesh
	scene.add_child(islands)
	for frame in range(3): await physics_frame
	await walk(scene, Vector2(10, 0))
	check(scene.control.current_command.state == Command.State.CANCELLED, "Unreachable island cancels at final reachable waypoint, not COMPLETED")
	scene.free()
	print("Prototype navigation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
