extends SceneTree
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Building = preload("res://scripts/building_instance.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Builder = preload("res://scripts/resident_builder_controller.gd")
const Resources = preload("res://scripts/resource_type.gd").Type
const View = preload("res://scripts/world_3d/building_view_3d.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func place(scene: Node, point: Vector3, turns: int = 0):
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_world_position(point)
	for turn in range(turns): scene.placement.rotate()
	return scene.placement.confirm()
func key(scene: Node, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code as Key
	event.pressed = true
	scene._unhandled_input(event)
func walk_phase(actor: Node, phase: int) -> void:
	for step in range(500):
		if actor.builder.phase != phase: break
		actor.view._physics_process(0.05)
	check(actor.builder.phase != phase, "Real grid executor reaches next builder phase")
func _run() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.set_process(false)
	for actor in scene.resident_runtimes:
		actor.view.set_physics_process(false)
		actor.intents.clear_reason(&"day_work")
	await physics_frame
	check(scene.construction_panel != null and not scene.construction_panel.collapsed, "Existing expanded ConstructionPanel reused in 3D")
	scene.construction_panel.set_collapsed(true)
	check(not scene.construction_panel.building_buttons.visible, "Existing collapse semantics preserved")
	scene.construction_panel.set_collapsed(false)
	for building in scene.buildings:
		check(not scene.build_grid.occupied_cells(building.id).is_empty(), "Every starter building registered in BuildGrid")
		check(not scene.navigation.is_world_walkable(Coordinates.to_world(building.position)), "Every starter uses same navigation registration path")
	var actor = scene.resident_runtimes[1]
	scene.resident_selection.select(actor.data)
	var count: int = scene.buildings.size()
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_world_position(Vector3(0.12,0,20.13))
	scene.building_ghost.refresh()
	check(scene.building_ghost.visible and not scene.building_ghost is Building, "Ghost is visual only, not domain building")
	check(scene.building_ghost.get_children().all(func(child): return not child is CollisionObject3D), "Ghost has no physics/picking blockers")
	check(scene.placement.world_position == Vector3(0,0,20), "Ghost snaps to half-unit BuildGrid")
	key(scene,KEY_R)
	check(scene.placement.quarter_turns == 1, "R rotates placement once")
	key(scene,KEY_ESCAPE)
	check(not scene.placement.is_active() and not scene.building_ghost.visible and scene.buildings.size() == count, "Esc cancels preview without creating entity")
	check(scene.resident_selection.selected_resident == actor.data, "Placement cancel does not clear selection")
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.handle_world_click(MOUSE_BUTTON_LEFT,{"collider":scene.world_locations.get_view(scene.warehouse_data.id),"position":Coordinates.to_world(scene.warehouse_data.position)})
	check(scene.buildings.size() == count and scene.placement.is_active(), "Overlap click invalid; mode remains active")
	check(scene.resident_selection.selected_resident == actor.data, "Placement click cannot select hit entity")
	scene.handle_world_click(MOUSE_BUTTON_RIGHT,{})
	check(not scene.placement.is_active() and actor.commands.active_command == null, "RMB cancels placement instead of issuing MOVE_TO/menu")
	# Actual viewport UI clicks must not become world placement/selection/commands.
	await process_frame
	var button: Button = scene.construction_panel.building_buttons.get_child(0)
	var button_click := InputEventMouseButton.new()
	button_click.button_index = MOUSE_BUTTON_LEFT
	button_click.pressed = true
	button_click.position = button.get_global_rect().get_center()
	root.push_input(button_click,true)
	var button_release := button_click.duplicate()
	button_release.pressed = false
	root.push_input(button_release,true)
	await physics_frame
	check(scene.placement.is_active() and scene.buildings.size() == count and scene.resident_selection.selected_resident == actor.data, "ConstructionPanel consumes click before world placement/selection")
	scene.placement.cancel()
	var start := Vector3(-8,0,20)
	var target := Vector3(8,0,20)
	var original: PackedVector3Array = scene.navigation.find_path(start,target)
	check(original.size() == 2, "Free area has direct path")
	var site = place(scene,Vector3(0.12,0,20.13),1)
	check(site is Building and site in scene.buildings and site.state == Building.State.UNDER_CONSTRUCTION, "Confirm creates real registered UNDER_CONSTRUCTION BuildingInstance")
	check(site.position == Vector2(0,500) and site.quarter_turns == 1, "Snapped world center bridges to simulation; rotation retained")
	check(site.get_delivered_amount(Resources.WOOD) == 0 and site.construction_progress == 0 and site.active_builder_ids.is_empty(), "Existing construction initialization preserved")
	var view = scene.world_locations.get_view(site.id)
	check(view is View and view.building_data == site and view.position == Vector3(0,0,20), "Runtime BuildingView3D references existing domain entity")
	check(Geometry.building_size(site) == Vector2(2,3), "Rotation swaps physical mesh/blocker dimensions")
	check(scene.build_grid.occupied_cells(site.id).size() == 24, "Build occupancy contains physical footprint only")
	check(not scene.navigation.is_world_walkable(Vector3(1.25,0,20)), "Navigation separately blocks resident clearance outside footprint")
	check(scene.navigation.find_path(start,target).size() > 2, "Next path immediately avoids placed construction")
	var access: Variant = scene.world_locations.get_position(site.id)
	check(access is Vector2 and scene.navigation.is_world_walkable(Coordinates.to_world(access)), "Rotated building has available deterministic action point")
	check(Coordinates.to_world(access).x > 1, "90 degree orientation prefers +X access side")
	check(not scene.placement.is_active() and not scene.building_ghost.visible, "Successful one-building placement exits mode")
	scene.handle_world_click(MOUSE_BUTTON_LEFT,{"collider":view})
	check(scene.resident_selection.selected_building == site and scene.get_node("HUD/BuildingCard").visible, "Selection/BuildingCard work after placement")
	scene.navigation.add_blocker(&"other",Geometry.footprint(site))
	check(scene.cancel_construction(site.id), "Cancellation API removes unfinished building")
	check(scene.build_grid.occupied_cells(site.id).is_empty() and site not in scene.buildings and scene.world_locations.get_position(site.id) == null, "Removal releases occupancy, registry and action-location cache")
	check(scene.resident_selection.selected_entity == null, "Removing selected construction clears highlight/card")
	check(not scene.navigation.is_world_walkable(Vector3(0,0,20)), "Removing building keeps overlapping independent navigation blocker")
	scene.navigation.remove_blocker(&"other")
	check(scene.navigation.find_path(start,target) == original, "Removing last blocker restores direct route without rebake")
	# Full physical WOOD workflow; controllers and reservations are the existing implementation.
	site = place(scene,Vector3(4,0,14))
	view = scene.world_locations.get_view(site.id)
	scene.game_time.total_minutes = 420
	actor.schedule._phase = "День"
	scene.player_control.assign_profession(actor.data.id,Profession.Type.BUILDER)
	actor.intents.clear_reason(&"day_work")
	actor.decision._deciding = true # Drive bounded work decision points explicitly; keep real work_request/controllers.
	actor.intents.cancel_current(actor.intents.current_intent)
	check(scene._request_work(actor), "Existing builder chooses runtime 3D construction")
	check(scene.warehouse_data.resources.get_reserved_out(Resources.WOOD) == 1 and site.get_construction_reserved_in(Resources.WOOD) == 1, "Existing physical reservation semantics apply")
	walk_phase(actor,Builder.Phase.GOING_TO_SOURCE)
	check(actor.data.inventory.amount == 1 and scene.warehouse_data.resources.get_amount(Resources.WOOD) == 49, "Real navigation arrival picks up one WOOD")
	walk_phase(actor,Builder.Phase.CARRYING_TO_SITE)
	check(site.get_delivered_amount(Resources.WOOD) == 1, "Real navigation arrival delivers to construction, not center")
	for trip in range(9):
		walk_phase(actor,Builder.Phase.GOING_TO_SOURCE)
		walk_phase(actor,Builder.Phase.CARRYING_TO_SITE)
	check(site.get_delivered_amount(Resources.WOOD) == 10 and scene.warehouse_data.resources.get_amount(Resources.WOOD) == 40, "All ten units physically travel warehouse/inventory/site")
	walk_phase(actor,Builder.Phase.GOING_TO_SITE)
	check(actor.builder.phase == Builder.Phase.BUILDING and actor.view.get_sim_position().is_equal_approx(scene.world_locations.get_position(site.id)), "Construction work starts at shared DEFAULT ACCESS POINT")
	for cycle in range(3):
		if cycle > 0:
			actor.intents.cancel_current(actor.intents.current_intent)
			check(scene._request_work(actor), "Next completed work cycle passes through a decision point")
			walk_phase(actor,Builder.Phase.GOING_TO_SITE)
		scene.game_time.total_minutes += 60
		actor.builder._on_minute(scene.game_time.total_minutes)
		check(site.construction_progress == (cycle+1)*60, "Real builder adds existing 60 minute contribution")
	check(site.is_built() and site.active_builder_ids.is_empty(), "Existing material/work completion transitions same instance to BUILT")
	check(view == scene.world_locations.get_view(site.id) and view.caption.text == "Дом", "Completion reuses 3D view, updates lifecycle visual")
	check(not scene.build_grid.occupied_cells(site.id).is_empty() and not scene.navigation.is_world_walkable(Coordinates.to_world(site.position)), "Completion preserves footprint and obstacle")
	check(not scene.cancel_construction(site.id), "Cancellation cannot demolish BUILT building")
	check(scene.player_control.assign_home(actor.data.id,site.id), "Completed runtime house joins existing housing API")
	# Remove before pickup releases both reservations without creating cargo.
	var before_pickup = place(scene,Vector3(-4,0,20))
	actor.intents.cancel_current(actor.intents.current_intent)
	check(scene._request_work(actor), "Claim new construction before cancellation")
	var before_drops: int = scene.ground_resources.drops.size()
	check(scene.cancel_construction(before_pickup.id), "Cancel before pickup supported")
	check(scene.warehouse_data.resources.get_reserved_out(Resources.WOOD) == 0 and before_pickup.get_construction_reserved_in(Resources.WOOD) == 0 and before_pickup.active_builder_ids.is_empty(), "Before-pickup removal releases both reservations and slot")
	check(scene.ground_resources.drops.size() == before_drops, "Before-pickup cancellation creates no phantom drop")
	# Cancellation while transporting uses existing cleanup/drop semantics.
	var cancelled = place(scene,Vector3(0,0,20))
	actor.intents.cancel_current(actor.intents.current_intent)
	check(scene._request_work(actor), "Builder can claim next site")
	walk_phase(actor,Builder.Phase.GOING_TO_SOURCE)
	var drops: int = scene.ground_resources.drops.size()
	check(scene.cancel_construction(cancelled.id), "Remove during transport supported")
	check(actor.builder.site == null and actor.data.inventory.amount == 0 and cancelled.active_builder_ids.is_empty() and cancelled.get_construction_reserved_in(Resources.WOOD) == 0, "Remove releases task/slot/inbound reservation")
	check(scene.ground_resources.drops.size() == drops+1, "Picked-up WOOD drops physically on site cancellation")
	await process_frame
	scene.free()
	print("Construction 3D: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
