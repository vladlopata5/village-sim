extends SceneTree
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Command = preload("res://scripts/player_command.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node, obstacle: Rect2 = Rect2()) -> bool:
	var clear := true
	for frame in range(180):
		await physics_frame
		actor.view._physics_process(0.1)
		if obstacle.has_area():
			var point: Vector2 = actor.view.get_sim_position()
			if point.distance_to(point.clamp(obstacle.position, obstacle.end)) < 10.0: clear = false
		if not actor.view.movement.is_moving(): break
	check(not actor.view.movement.is_moving(), "Navigation action terminates in bounded steps")
	return clear
func _run() -> void:
	var old = load("res://scenes/main.tscn").instantiate()
	root.add_child(old)
	old.game_time.set_process(false)
	var residents: Array = []
	var buildings: Array = []
	for data in old.residents: residents.append([data.id, data.resident_name, data.profession, data.home_location_id])
	for data in old.buildings: buildings.append([data.id, data.type, data.position, data.state, data.resources.get_amount(Resources.FOOD), data.resources.get_amount(Resources.PLANK)])
	old.free()
	var scene = preload("res://tests/legacy_starter_3d.gd").instantiate()
	root.add_child(scene)
	for frame in range(120):
		await physics_frame
		if scene.ready_for_play: break
	check(scene.ready_for_play, "Real 3D Main completes shared simulation setup")
	scene.game_time.set_process(false)
	for runtime in scene.resident_runtimes: runtime.view.set_physics_process(false)
	check(scene.residents.size() == 4 and scene.buildings.size() == 7, "Exact shared starter counts; no duplicate entities")
	check(scene.get_node("World/ResidentViews").get_child_count() == 4 and scene.get_node("World/BuildingViews").get_child_count() == 7, "All domain entities have 3D presentations")
	for i in range(4):
		var data = scene.residents[i]
		check([data.id, data.resident_name, data.profession, data.home_location_id] == residents[i], "Resident identity, profession and home match 2D starter")
		var runtime = scene.resident_runtimes[i]
		check(runtime.view.resident_data == data and runtime.view.view.resident_data == data, "Executor and child view reference the same domain resident")
		check(runtime.view.view.position == Vector3.ZERO and runtime.view.get_sim_position() == Coordinates.to_sim(runtime.view.global_position), "Executor owns physical position; view has zero local offset")
	for i in range(7):
		var data = scene.buildings[i]
		check([data.id, data.type, data.position, data.state, data.resources.get_amount(Resources.FOOD), data.resources.get_amount(Resources.PLANK)] == buildings[i], "Building state/resources/location match 2D starter")
		var view = scene.world_locations.get_view(data.id)
		check(view.building_data == data and view.global_position == Coordinates.to_world(data.position), "Building view uses domain ID and logical center")
		var point: Variant = scene.world_locations.get_position(data.id)
		check(point is Vector2 and not data.footprint().has_point(point), "Action access point is outside building footprint")
		check(point == scene.world_locations.resolve_action_position(data), "Every action resolves the same deterministic access point")
	var impossible = Building.new(&"outside_navigation", Definition.for_type(Types.HOME), Vector2(9000,9000))
	check(scene.world_locations.resolve_action_position(impossible) == null, "Unwalkable building has no action point, no center fallback")
	var actor = scene.resident_runtimes[0]
	var camera: Camera3D = scene.get_node("World/Camera3D")
	await physics_frame
	var resident_hit: Dictionary = scene.pick(camera.unproject_position(actor.view.global_position + Vector3(0,0.72,0)))
	check(resident_hit.get("collider") == actor.view.view, "Real raycast picks explicit ResidentView3D")
	scene.handle_world_click(MOUSE_BUTTON_LEFT, resident_hit)
	check(scene.resident_selection.selected_resident == actor.data and scene.resident_selection.selected_building == null, "Resident selection stores domain data exclusively")
	check(scene.get_node("HUD/ResidentCard").visible and scene.get_node("HUD/ResidentCard").name_label.text.contains(actor.data.resident_name), "Existing ResidentCard reads selected resident")
	check(actor.view.view.indicator.visible, "Resident selection indicator is visible")
	var card: Control = scene.get_node("HUD/ResidentCard")
	await process_frame
	var ui_click := InputEventMouseButton.new()
	ui_click.button_index = MOUSE_BUTTON_RIGHT
	ui_click.pressed = true
	ui_click.position = card.get_global_rect().position + Vector2(12,80)
	root.push_input(ui_click, true)
	await physics_frame
	check(actor.commands.active_command == null and scene.resident_selection.selected_resident == actor.data, "Actual GUI click is consumed before 3D world input")
	var house = scene.player_control.get_building(actor.data.home_location_id)
	var house_view = scene.world_locations.get_view(house.id)
	var building_hit: Dictionary = scene.pick(camera.unproject_position(house_view.global_position + Vector3(0,1,0)))
	check(building_hit.get("collider") == house_view, "Real raycast picks BuildingView3D")
	scene.handle_world_click(MOUSE_BUTTON_LEFT, building_hit)
	check(scene.resident_selection.selected_building == house and scene.resident_selection.selected_resident == null, "Building selection replaces resident")
	check(house_view.indicator.visible and not actor.view.view.indicator.visible, "Unified selection switches highlights")
	check(scene.get_node("HUD/BuildingCard").visible and not scene.get_node("HUD/ResidentCard").visible, "Existing BuildingCard replaces ResidentCard")
	check(scene.get_node("HUD/BuildingCard").housing_count.text.contains("1 / 4"), "Existing housing query works in 3D card")
	scene.get_node("HUD/BuildingCard").close_button.pressed.emit()
	check(scene.resident_selection.selected_entity == null and not house_view.indicator.visible, "Existing close button clears 3D highlight")
	scene.resident_selection.select(actor.data)
	# Physical speed scales once; domain distance/time and modifiers stay unchanged.
	var sim_speed: float = preload("res://scripts/resident_modifiers.gd").movement_speed(actor.data,120.0)
	actor.view.global_position = Coordinates.to_world(Vector2.ZERO)
	scene.player_control.move_to(actor.data.id,Vector2(250,0))
	actor.view._physics_process(0.1)
	var x1_position: Vector2 = actor.view.get_sim_position()
	check(is_equal_approx(x1_position.length(),sim_speed*0.1), "Real executor preserves balanced simulation speed at x1")
	actor.view.global_position = Coordinates.to_world(Vector2.ZERO)
	scene.game_time.set_speed(20)
	scene.player_control.move_to(actor.data.id,Vector2(250,0))
	actor.view._physics_process(0.005)
	check(actor.view.get_sim_position().is_equal_approx(x1_position), "Real executor x20 covers same simulation distance for equal game time")
	check(scene.social_world.position_of(actor.data.id).is_equal_approx(x1_position), "Social gameplay provider still returns simulation units")
	scene.game_time.set_speed(1)
	actor.view.global_position = Coordinates.to_world(Vector2(120,240))
	var target := Vector2(450,240)
	scene.handle_world_click(MOUSE_BUTTON_RIGHT, {"collider":scene.get_node("World/Ground"), "position":Coordinates.to_world(target)})
	var command = actor.commands.active_command
	check(command != null and command.target.is_equal_approx(target), "3D ground input creates existing PlayerCommand MOVE_TO")
	check(actor.view.movement.target_position() == Coordinates.to_world(target), "Intent bridge passes X/Z target to executor")
	check(await walk(actor, scene.warehouse_data.footprint()), "Navigation keeps resident capsule outside static warehouse")
	check(command.state == Command.State.COMPLETED and actor.view.get_sim_position().distance_to(target) < 1, "Real navigation arrival completes original PlayerCommand")
	scene.player_control.move_to(actor.data.id, scene.warehouse_data.position)
	command = actor.commands.active_command
	await walk(actor)
	check(command.state == Command.State.CANCELLED and actor.commands.active_command == null, "Building center/blocked command cancels without stuck ownership")
	check(actor.data.inventory.amount == 0, "Failed move does not invent cargo")
	# Existing EAT and porter workflows use the bridge without 3D-specific gameplay.
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.hunger = 45
	scene.kitchen_data.resources.add(Resources.FOOD, 2)
	actor.intents.abort_current(actor.intents.current_intent)
	check(actor.needs.try_eat_at(scene.kitchen_data.id, 6000), "Existing targeted EAT starts in 3D")
	check(actor.intents.current_intent.target_position == scene.world_locations.get_position(scene.kitchen_data.id), "EAT uses central building access point")
	await walk(actor)
	check(actor.data.activity == Activity.EATING, "Real navigation arrival starts existing eating flow")
	scene.player_control.move_to(actor.data.id, actor.view.get_sim_position())
	await walk(actor)
	check(actor.data.activity != Activity.EATING, "PlayerCommand interrupts EAT through shared cleanup")
	scene.game_time.total_minutes = 420
	actor.schedule._phase = "День"
	actor.intents.abort_current(actor.intents.current_intent)
	var candidates: Array = scene.logistics.collect_candidates(actor.data.id)
	check(not candidates.is_empty(), "Porter candidates remain available after world scaling")
	for candidate in candidates:
		var source_point: Vector2 = scene.world_locations.get_position(candidate.source.id)
		var destination_point: Vector2 = scene.world_locations.get_position(candidate.destination.id)
		var expected_distance: float = actor.view.get_sim_position().distance_to(source_point)+source_point.distance_to(destination_point)
		var world_distance: float = actor.view.global_position.distance_to(Coordinates.to_world(source_point))+Coordinates.to_world(source_point).distance_to(Coordinates.to_world(destination_point))
		check(is_equal_approx(candidate.route_distance,expected_distance), "Logistics scoring measures original simulation distances")
		check(is_equal_approx(Coordinates.length_to_world(candidate.route_distance),world_distance), "Route distance is not accidentally scored in smaller world units")
	check(scene._request_haul_work(actor), "Existing porter claims physical delivery in 3D")
	var job = scene.logistics.current_job
	var delivered_before: int = scene.kitchen_data.resources.get_amount(Resources.FOOD)
	for frame in range(180):
		await physics_frame
		actor.view._physics_process(0.1)
		if job.state == preload("res://scripts/haul_job.gd").State.COMPLETED: break
	check(job.state == preload("res://scripts/haul_job.gd").State.COMPLETED, "Porter reaches both access points and completes committed HaulJob")
	check(scene.kitchen_data.resources.get_amount(Resources.FOOD) == delivered_before+1 and actor.data.inventory.amount == 0, "Physical delivery updates unchanged containers/inventory")
	var gatherer = scene.resident_runtimes[2]
	gatherer.schedule._phase = "День"
	gatherer.intents.abort_current(gatherer.intents.current_intent)
	check(gatherer.schedule.request_work(), "Existing gatherer WORK requests navigation destination")
	await walk(gatherer)
	check(gatherer.data.activity == Activity.WORKING, "Gatherer arrives at hut access and starts WORKING")
	var progress: int = scene.gatherer_hut_data.production_progress
	scene.production._on_minute(scene.game_time.total_minutes)
	check(scene.gatherer_hut_data.production_progress == progress+1, "Production proximity reads the same resolved action point")
	# Dynamic blockers and location cache updates use the same real main-world service.
	var nav_start := Coordinates.to_world(Vector2(-600,600))
	var nav_target := Coordinates.to_world(Vector2(-300,600))
	var direct: PackedVector3Array = scene.navigation.find_path(nav_start,nav_target)
	check(direct.size()==2, "Main grid initially has direct route in clear playable area")
	scene.navigation.add_blocker(&"temporary_integration",Rect2(-19,22,2,4))
	var detour: PackedVector3Array = scene.navigation.find_path(nav_start,nav_target)
	check(detour.size()>2, "Runtime blocker immediately changes main-world path")
	scene.navigation.remove_blocker(&"temporary_integration")
	check(scene.navigation.find_path(nav_start,nav_target)==direct, "Removal immediately restores deterministic main-world path")
	var previous_access: Vector2 = scene.world_locations.get_position(house.id)
	var access_world := Coordinates.to_world(previous_access)
	scene.navigation.add_blocker(&"door_test",Rect2(Coordinates.world_plane(access_world)-Vector2.ONE*2.0,Vector2.ONE*4.0))
	var next_access: Variant = scene.world_locations.get_position(house.id)
	check(next_access==null or not next_access.is_equal_approx(previous_access), "Grid revision invalidates cached building access point")
	scene.navigation.remove_blocker(&"door_test")
	check(scene.world_locations.get_position(house.id)==previous_access, "Access point returns deterministically after blocker removal")
	check(scene.navigation_debug.visible==false, "Navigation debug is hidden by default")
	scene.navigation_debug.set_enabled(true)
	scene.navigation_debug.bind_movement(actor.view.movement)
	check(scene.navigation_debug.visible, "Navigation debug can be enabled without gameplay changes")
	scene.navigation_debug.set_enabled(false)
	# Sleep target and proximity use the exact same building access resolver.
	scene.game_time.total_minutes = 1379
	scene.game_time.advance(1)
	check(actor.intents.current_intent.reason_id == &"night_home" and actor.intents.current_intent.target_position == scene.world_locations.get_position(house.id), "Real night schedule resolves home access, not center")
	check(actor.data.activity == Activity.MOVING, "Ordinary sleep requires physical travel")
	await walk(actor)
	check(actor.data.activity == Activity.SLEEPING and actor.data.current_sleep_quality == 1.0, "Arrival at access point starts existing home-quality sleep")
	var home_target: Vector2 = actor.view.get_sim_position()
	scene.player_control.clear_home(actor.data.id)
	check(actor.data.activity == Activity.SLEEPING and actor.view.get_sim_position() == home_target, "Housing changes preserve committed sleep")
	var minute: int = scene.game_time.total_minutes
	scene.game_time.advance(1)
	check(scene.game_time.total_minutes == minute+1, "Shared simulation clock continues ticking")
	var before_pause: Vector2 = actor.view.get_sim_position()
	paused = true
	scene.game_time.advance(10)
	await physics_frame
	check(scene.game_time.total_minutes == minute+1 and actor.view.get_sim_position() == before_pause, "Pause preserves clock and physical position")
	paused = false
	scene.handle_world_click(MOUSE_BUTTON_LEFT, {"collider":scene.get_node("World/Ground")})
	check(scene.resident_selection.selected_entity == null, "Empty ground clears unified selection")
	scene.free()
	print("Main 3D migration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
