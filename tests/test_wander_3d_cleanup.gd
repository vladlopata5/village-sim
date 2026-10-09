extends SceneTree
const Target = preload("res://scripts/wander_target.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Navigation = preload("res://scripts/navigation_grid.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
var checks := 0
var failures := 0
var attempts := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func reject(_origin: Vector2, _target: Vector2) -> bool:
	attempts += 1
	return false
func _run() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.set_process(false)
	for actor in scene.resident_runtimes: actor.view.set_physics_process(false)
	await physics_frame
	check(scene.residents.size() == 4 and scene.buildings.size() == 7, "Shared starter counts preserved")
	var expected := {
		&"communal_kitchen_01":Vector2(-275,237.5), &"warehouse_01":Vector2(300,237.5),
		&"gatherer_hut_01":Vector2(375,-237.5), &"home_stepan":Vector2(-300,-125),
		&"home_anna":Vector2(-100,-200), &"home_fedor":Vector2(100,-200), &"home_marina":Vector2(300,-125),
	}
	var all_cells: Dictionary = {}
	var expected_navigation = Navigation.new()
	for building in scene.buildings:
		var point := Coordinates.to_world(building.position)
		check(building.position == expected[building.id] and building.quarter_turns == 0 and building.is_built(), "Explicit aligned starter source data, zero rotation and BUILT preserved")
		check(point.is_equal_approx(scene.build_grid.snap(point,building.definition.footprint_cells,building.quarter_turns)), "Starter and runtime share footprint-aware snap")
		var footprint := Geometry.footprint(building)
		for edge in [footprint.position,footprint.end]:
			var relative: Vector2 = (edge-scene.build_grid.bounds.position)/scene.build_grid.CELL_SIZE
			check(relative.is_equal_approx(relative.round()), "All physical edges are build cell boundaries")
		check(scene.build_grid.bounds.encloses(footprint), "Starter footprint inside bounds")
		var cells: Array = scene.build_grid.occupied_cells(building.id)
		check(cells.size() == building.definition.footprint_cells.x*building.definition.footprint_cells.y, "No conservative extra occupancy cells needed for aligned starter")
		var overlapping := false
		for cell in cells:
			if all_cells.has(cell): overlapping = true
			all_cells[cell] = building.id
		check(not overlapping, "No starter occupancy overlap")
		var access: Variant = scene.world_locations.get_position(building.id)
		check(access is Vector2 and scene.navigation.is_world_walkable(Coordinates.to_world(access)), "Starter access point remains walkable")
		expected_navigation.add_blocker(building.id,footprint)
	for tree in scene.trees: expected_navigation.add_blocker(tree.id,scene.tree_footprint(tree))
	check(scene.navigation.blocked_cells() == expected_navigation.blocked_cells(), "Navigation blockers match exact snapped physical footprints plus unchanged clearance")
	for resident in scene.residents:
		check(scene.player_control.get_home(resident.id).id == resident.home_location_id and resident.home_location_id in expected, "Original home relationship remains valid")
	check(scene.warehouse_data.resources.get_amount(0) == 10 and scene.warehouse_data.resources.get_amount(1) == 50 and scene.kitchen_data.resources.get_amount(0) == 0, "Initial resources preserved")
	var actor = scene.resident_runtimes[1]
	actor.view.global_position = Vector3(8.25,0,9.75)
	var origin: Vector2 = actor.view.get_sim_position()
	var rng := RandomNumberGenerator.new()
	# Locate a deterministic seed where legacy first target is blocked but a later target is reachable.
	var corrected_seed := -1
	for seed_value in range(200):
		rng.seed = seed_value
		var legacy = Target.nearby(origin,rng,scene.field.FIELD)
		rng.seed = seed_value
		var validated = scene._wander_target_2d(rng,actor.data.id)
		if not scene.navigation.is_world_walkable(Coordinates.to_world(legacy.position)) and validated != null:
			corrected_seed = seed_value
			check(validated.position != legacy.position and scene._reachable_wander_target(origin,validated.position), "Blocked first candidate rejected; later reachable point selected")
			break
	check(corrected_seed >= 0, "Real starter geometry reproduces legacy target selection failure")
	check(not scene._reachable_wander_target(origin,scene.warehouse_data.position), "Blocked destination rejected")
	check(not scene._reachable_wander_target(origin,Vector2(9000,9000)), "Out-of-grid candidate rejected")
	# A separate authoritative NavigationGrid creates an actually disconnected walkable island.
	var local = Navigation.new(Rect2(-5,-5,10,10),0.0)
	local.add_blocker(&"wall",Rect2(-0.5,-5,1,10))
	var previous = scene.navigation
	scene.navigation = local
	check(local.is_world_walkable(Vector3(2.25,0,0.25)) and not scene._reachable_wander_target(Vector2(-56.25,6.25),Vector2(56.25,6.25)), "Walkable but disconnected candidate rejected through NavigationGrid")
	scene.navigation = previous
	attempts = 0
	rng.seed = 12
	check(Target.nearby(origin,rng,scene.field.FIELD,reject) == null and attempts == Target.MAX_ATTEMPTS and attempts == 8, "No candidate returns null after exactly eight attempts, no infinite retry")
	# Isolated start is valid but every candidate is rejected by real connectivity/bounds.
	actor.view.global_position = Vector3(40.25,0,20.25)
	scene.navigation.add_blocker(&"isolation_left",Rect2(39.5,18,0.1,5))
	scene.navigation.add_blocker(&"isolation_right",Rect2(41,18,0.1,5))
	scene.navigation.add_blocker(&"isolation_up",Rect2(38,19.5,5,0.1))
	scene.navigation.add_blocker(&"isolation_down",Rect2(38,21,5,0.1))
	check(scene.navigation.is_world_walkable(actor.view.global_position), "Trapped test source remains walkable")
	actor.decision._deciding = true
	actor.intents.cancel_current(actor.intents.current_intent)
	check(not actor.wander.try_wander(500) and actor.wander._active == null and not actor.intents.has_current_action(), "No reachable wander point declines cleanly without starting a bad intent")
	for id in [&"isolation_left",&"isolation_right",&"isolation_up",&"isolation_down"]: scene.navigation.remove_blocker(id)
	actor.view.global_position = Vector3(-63.25,0,0.25)
	for seed_value in range(60):
		rng.seed = seed_value
		var target = scene._wander_target_2d(rng,actor.data.id)
		check(target == null or scene._reachable_wander_target(actor.view.get_sim_position(),target.position), "Near-boundary targets obey bounds/clearance/connectivity")
	actor.view.global_position = Vector3(0,0,20)
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_world_position(Vector3(4.13,0,20.12))
	var runtime_building = scene.placement.confirm()
	check(runtime_building != null and Coordinates.to_world(runtime_building.position).is_equal_approx(scene.build_grid.snap(Vector3(4.13,0,20.12),runtime_building.definition.footprint_cells)), "Runtime placement continues same snap semantics alongside starters")
	actor.wander.rng.seed = 6
	check(actor.wander.try_wander(500), "Reachable ordinary wander still starts")
	for step in range(200):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
	check(actor.wander._stay_ends_at > 0 and actor.intents.current_intent.reason_id == &"wander", "Real executor reaches wander destination and enters existing stay")
	scene.free()
	print("Wander/starter cleanup: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
