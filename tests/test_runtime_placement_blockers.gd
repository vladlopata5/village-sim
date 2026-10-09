extends SceneTree
const Registry = preload("res://scripts/runtime_placement_blockers.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func position_of(body: Node3D) -> Vector3: return body.global_position
func _run() -> void:
	var registry = Registry.new()
	var body := Node3D.new()
	root.add_child(body)
	var provider := position_of.bind(body)
	check(registry.register_circle(&"generic",provider,0.4) and registry.has_blocker(&"generic"), "Generic entity registers without resident class/data")
	check(not registry.register_circle(&"generic",provider,0.5), "Duplicate ID cannot replace live provider")
	check(not registry.register_circle(&"",provider,0.4) and not registry.register_circle(&"invalid",Callable(),0.4), "Empty ID/invalid provider rejected")
	check(not registry.register_circle(&"radius",provider,-1) and not registry.register_circle(&"radius",provider,INF), "Invalid bounds rejected")
	var footprint := Rect2(-1.5,-1,3,2)
	check(registry.first_overlap(footprint) == &"generic", "Center inside rectangle blocks")
	body.position = Vector3(1.8,0,0)
	check(registry.first_overlap(footprint) == &"generic", "Circle edge overlap blocks even with center outside")
	body.position = Vector3(1.91,0,0)
	check(registry.first_overlap(footprint).is_empty(), "Nearby circle without overlap permits placement")
	body.position = Vector3(1.75,0,1.25)
	check(registry.first_overlap(footprint) == &"generic", "Circle corner intersection uses distance to closest rectangle point")
	body.position = Vector3(1.8,0,1.3)
	check(registry.first_overlap(footprint).is_empty(), "Outside corner circle is not falsely blocked by its bounding box")
	body.position = Vector3(0,100,0)
	check(registry.first_overlap(footprint) == &"generic", "First 2.5D version checks X/Z, ignores height")
	check(registry.register_circle(&"a",provider,0.4) and registry.first_overlap(footprint) == &"a", "Multiple overlap reports stable sorted entity ID")
	registry.unregister(&"a")
	check(registry.first_overlap(footprint) == &"generic", "Removing one blocker leaves another")
	registry.unregister(&"generic")
	registry.unregister(&"unknown")
	check(registry.first_overlap(footprint).is_empty(), "Remove/no-op remove leaves footprint available")
	# Exact tangency is conservatively blocked, without adding navigation clearance.
	body.position = Vector3(2,0,0)
	registry.register_circle(&"contact",provider,0.5)
	check(registry.first_overlap(footprint) == &"contact", "Tangent circle contact blocks deterministically")
	body.position.x = 2.01
	check(registry.first_overlap(footprint).is_empty(), "Separation immediately beyond radius is valid")
	registry.unregister(&"contact")
	var temporary := Node3D.new()
	root.add_child(temporary)
	registry.register_circle(&"stale",temporary.get_global_transform,0.4)
	temporary.free()
	check(registry.first_overlap(footprint).is_empty() and not registry.has_blocker(&"stale"), "Freed provider safely removed")
	body.free()
	# Real Main3D integration, with live executor positions rather than copied data.
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.set_process(false)
	for actor in scene.resident_runtimes: actor.view.set_physics_process(false)
	await physics_frame
	check(scene.placement.runtime_blockers == scene.runtime_placement_blockers, "World registry injected into centralized validator")
	for actor in scene.resident_runtimes:
		check(scene.runtime_placement_blockers.has_blocker(StringName(actor.data.id)), "Every real resident is registered")
		check(scene.build_grid.occupied_cells(StringName(actor.data.id)).is_empty(), "Resident never owns BuildGrid cells")
	var actor = scene.resident_runtimes[1]
	var center := Vector3(0,0,20)
	var outside := Vector3(5,0,20)
	actor.view.global_position = outside
	var revision: int = scene.navigation.revision
	var blocked: Array[Vector2i] = scene.navigation.blocked_cells()
	var owners: Dictionary = {}
	for building in scene.buildings: owners[building.id] = scene.build_grid.occupied_cells(building.id)
	var count: int = scene.buildings.size()
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_world_position(center)
	scene.building_ghost.refresh()
	check(scene.placement.can_place() and scene.building_ghost.material.albedo_color.g > 0.8, "Clear ghost initially valid/green")
	actor.view.global_position = center
	check(actor.view.get_world_position() == center and actor.view.get_sim_position() == Coordinates.to_sim(center), "Provider reads authoritative executor position through existing bridge")
	# No new ghost update: confirm must observe the newly entered circle itself.
	check(scene.placement.confirm() == null and scene.buildings.size() == count, "Confirm-time live recheck prevents stale green ghost placement")
	check(scene.placement.is_active(), "Invalid runtime overlap leaves placement mode active")
	scene.building_ghost.refresh()
	check(scene.building_ghost.material.albedo_color.r > 0.9 and scene.placement.validation_reason().contains("подвижным"), "Ghost updates red with generic blocker reason")
	actor.view.global_position = center + Vector3(1.8,0,0)
	check(not scene.placement.can_place(), "Resident partial overlap blocks physical footprint")
	actor.view.global_position = center + Vector3(1.91,0,0)
	check(scene.placement.can_place(), "Resident close but separated does not add phantom clearance")
	actor.view.global_position = center + Vector3(0,0,1.7)
	check(scene.placement.can_place(), "Resident beyond short depth clear at zero rotation")
	scene.placement.rotate()
	check(not scene.placement.can_place(), "90 degree depth expansion intersects same stationary circle")
	scene.placement.rotate()
	check(scene.placement.can_place(), "180 degree restores physical rectangle dimensions")
	scene.placement.rotate()
	check(not scene.placement.can_place(), "270 degree also uses swapped footprint")
	actor.view.global_position = outside
	var second = scene.resident_runtimes[3]
	var second_original: Vector3 = second.view.global_position
	second.view.global_position = center
	check(not scene.placement.can_place(), "Any resident overlapping is sufficient")
	second.view.global_position = second_original
	check(scene.placement.can_place(), "Moving all overlapping entities away restores validity")
	check(scene.navigation.revision == revision and scene.navigation.blocked_cells() == blocked and scene.navigation.is_world_walkable(center), "Runtime registration/movement never creates NavigationGrid blockers")
	for building in scene.buildings:
		check(scene.build_grid.occupied_cells(building.id) == owners[building.id], "Resident movement never changes static occupancy")
	# A plain movable Node3D can join this same validator without a gameplay class branch.
	var generic := Node3D.new()
	root.add_child(generic)
	generic.position = center
	check(scene.runtime_placement_blockers.register_circle(&"future_entity",position_of.bind(generic),0.5), "Generic opt-in uses unchanged placement validator")
	check(not scene.placement.can_place(), "Generic entity blocks exactly like resident")
	scene.runtime_placement_blockers.unregister(&"future_entity")
	generic.free()
	check(scene.placement.can_place(), "Generic removal restores valid placement")
	scene.building_ghost.refresh()
	check(scene.building_ghost.material.albedo_color.g > 0.8, "Ghost automatically turns green on next validation update")
	var placed = scene.placement.confirm()
	check(placed != null and placed in scene.buildings and scene.buildings.size() == count+1, "Same ghost confirms after resident leaves")
	check(placed.quarter_turns == 3 and Geometry.building_size(placed) == Vector2(2,3), "Building creation still uses existing lifecycle")
	check(scene.navigation.revision == revision+1, "Only actual building registration adds navigation blocker")
	check(scene.cancel_construction(placed.id), "Existing construction removal works")
	var executor = scene.resident_runtimes[2].view
	var removed_id := StringName(executor.resident_data.id)
	executor.free()
	check(not scene.runtime_placement_blockers.has_blocker(removed_id), "Executor exit unregisters its live blocker immediately")
	scene.free()
	print("Runtime placement blockers: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
