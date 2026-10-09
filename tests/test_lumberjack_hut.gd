extends SceneTree
const Fixture = preload("res://tests/forestry_fixture.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const TreeData = preload("res://scripts/tree_data.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(1800):
		actor.view._physics_process(0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id != reason: break
		if not actor.view.movement.is_moving(): break
func idle(actor: Node) -> void:
	if actor.commands.active_command != null: actor.commands.cancel_current()
	actor.intents.cancel_current(actor.intents.current_intent)
func run() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for actor in scene.resident_runtimes:
		actor.decision._deciding = true
		idle(actor)
		actor.view.set_physics_process(false)
		for need in range(4): actor.data.get_need(need).value = 0
	await physics_frame
	var actor = scene.resident_runtimes[3]
	var worker = actor.get_node("Lumberjack")
	check(not scene.player_control.assign_profession(actor.data.id,Profession.LUMBERJACK),"No hut means management assignment unavailable")
	actor.data.profession = Profession.LUMBERJACK
	actor.data.work_location_id = &""
	check(not actor.decision._has_work() and not worker.has_work(),"Lumberjack without workplace has no WORK")
	var def = Definition.for_type(Types.LUMBERJACK_HUT)
	check(def.footprint_cells==Vector2i(8,6) and def.worker_capacity==1,"Ordinary definition footprint and capacity")
	check(def.work_radius==15 and def.target_tree_count==12 and def.local_resource_capacity==12,"Data-driven area/count/buffer")
	scene.placement.select(def)
	scene.placement.update_world_position(Vector3(-20,0,-8))
	scene.placement.rotate()
	var hut = scene.placement.confirm()
	check(hut != null and not hut.is_built() and hut.quarter_turns==1,"Real rotated placement creates construction")
	check(not scene.player_control.assign_workplace(actor.data.id,hut.id),"Under construction hut cannot employ")
	check(not scene.navigation.is_world_walkable(Coordinates.to_world(hut.position)),"Construction footprint already blocks navigation")
	hut.add_delivered_material(Resources.WOOD,10)
	hut.construction_progress = 180
	check(hut.complete_construction(),"Ordinary WOOD/work lifecycle activates same instance")
	check(hut.resources.get_capacity(Resources.LOG)==12 and not hut.resources.allows_resource(Resources.FOOD) and not hut.resources.allows_resource(Resources.WOOD),"Built hut stores only LOG")
	check(scene.player_control.assign_workplace(actor.data.id,hut.id),"Built hut employs lumberjack")
	var other = scene.resident_runtimes[1]
	check(not scene.player_control.assign_workplace(other.data.id,hut.id),"Second worker rejected atomically")
	check(scene.player_control.get_workplace_workers(hut.id)==[actor.data],"Workers derived from resident relationship")
	scene.resident_selection.select_building(hut)
	scene.get_node("HUD/BuildingCard")._refresh()
	check("Бревно" in scene.get_node("HUD/BuildingCard").resources_label.text and "Марина" in scene.get_node("HUD/BuildingCard").resources_label.text,"Card exposes LOG and assigned worker")
	scene.game_time.debug_skip_minutes(60)
	check(worker.best_task().kind==&"CHOP","No loose LOG gives chopping")
	var remote_drop = scene.ground_resources.create_drop(Resources.LOG,1,Coordinates.to_sim(Vector3(40,0,20)))
	check(worker.best_task().kind==&"CHOP","Ground LOG outside own work radius is ignored")
	check(not remote_drop.reserve(&"") and remote_drop.reserve(&"first") and not remote_drop.reserve(&"second"),"Generic GroundResource reservation excludes duplicate owners")
	remote_drop.release(&"second")
	check(remote_drop.reservation_owner_id==&"first","Only reservation owner can release")
	remote_drop.release(&"first")
	Fixture.clear_drops(scene)
	var outside = TreeData.new(&"outside",Coordinates.to_sim(Vector3(30,0,20)))
	scene.trees.append(outside)
	check(not scene.forestry_area.inside(hut,outside.position),"Outside tree excluded")
	scene.trees.erase(outside)
	check(worker.request_work(),"Chop through ordinary provider")
	var chopped = worker.tree
	walk(actor)
	check(worker.chopping,"Physical arrival begins chopping")
	scene.game_time.debug_skip_minutes(60)
	check(chopped.state==TreeData.State.DEPLETED and scene.ground_resources.drops.size()==3,"Chop yields three physical LOG")
	for trip in range(3):
		check(worker.best_task().kind==&"COLLECT" and worker.request_work(),"Loose logs take priority over standing trees")
		var drop = worker.drop
		check(not drop.id.is_empty() and drop.reservation_owner_id==StringName(actor.data.id) and hut.resources.get_reserved_in(Resources.LOG)==1,"Ground and hut capacity reserved together")
		walk(actor,&"collect_log")
		check(actor.data.inventory.amount==1 and actor.data.inventory.resource_type==Resources.LOG and drop not in scene.ground_resources.drops,"Pickup physically transfers one LOG")
		walk(actor)
		check(actor.data.inventory.amount==0 and hut.resources.get_amount(Resources.LOG)==trip+1 and hut.resources.get_reserved_in(Resources.LOG)==0,"Delivery deposits into own hut and clears reservation")
	check(scene.ground_resources.drops.is_empty(),"Three trips collect all three logs")
	# Overlapping huts share spatial resources; there is no permanent owner.
	var second_hut = Fixture.hut(scene,&"second_hut",Vector3(-20,0,-2))
	check(scene.player_control.assign_workplace(other.data.id,second_hut.id),"Separate hut has its own worker capacity")
	var loose = scene.ground_resources.create_drop(Resources.LOG,1,Coordinates.to_sim(Vector3(-24,0,-4)))
	check(scene.forestry_area.inside(hut,loose.world_position) and scene.forestry_area.inside(second_hut,loose.world_position),"Both work areas can contain same ground LOG")
	check(worker.request_work() and loose.reservation_owner_id==StringName(actor.data.id),"First worker reserves common LOG")
	check(other.get_node("Lumberjack").best_task().kind!=&"COLLECT","Second worker cannot duplicate reserved pickup")
	scene.player_control.move_to(actor.data.id,Vector2(0,500))
	check(loose in scene.ground_resources.drops and loose.reservation_owner_id.is_empty() and hut.resources.get_reserved_in(Resources.LOG)==0,"Before pickup interrupt leaves resource and releases both claims")
	idle(actor)
	check(worker.request_work(),"Collection can resume after command")
	walk(actor,&"collect_log")
	scene.player_control.move_to(actor.data.id,Vector2(0,500))
	check(actor.data.inventory.amount==0 and scene.ground_resources.drops.size()==1 and hut.resources.get_reserved_in(Resources.LOG)==0,"After pickup interrupt drops carried LOG without duplication")
	idle(actor)
	Fixture.clear_drops(scene)
	# Full-buffer regression: export naturally frees enough capacity for a complete yield.
	check(second_hut.resources.get_amount(Resources.LOG)==0,"Empty second hut must not attract external export")
	hut.resources.add(Resources.LOG,7)
	hut.definition.target_tree_count = 0
	check(hut.resources.get_amount(Resources.LOG)==10 and worker.best_target().is_empty(),"10/12 cannot fit full yield 3")
	check(worker.best_task().kind==&"EXPORT" and worker.request_work(),"No local tasks gives shared export")
	var job = scene.logistics.get_job(actor.data.id)
	check(job != null and job.source_location_id==hut.id and job.resource_type==Resources.LOG and job.work_phase_only,"Export uses existing owned HaulJob from own hut")
	check(hut.resources.get_reserved_out(Resources.LOG)==1 and scene.warehouse_data.resources.get_reserved_in(Resources.LOG)==1,"Shared haul reserves source and destination")
	walk(actor,&"haul_source")
	check(actor.data.inventory.amount==1 and hut.resources.get_amount(Resources.LOG)==9,"Shared pickup uses inventory and reduces source")
	walk(actor)
	check(scene.warehouse_data.resources.get_amount(Resources.LOG)==1 and scene.logistics.get_job(actor.data.id)==null,"Shared delivery completes into storage")
	check(worker.best_task().kind==&"CHOP","9/12 makes full yield available again")
	check(scene.logistics.collect_candidates(scene.resident_runtimes[0].data.id).any(func(candidate): return candidate.resource_type==Resources.LOG),"Ordinary porter can see container LOG export")
	# Planting below target when complete yield does not fit.
	hut.resources.add(Resources.LOG,3)
	hut.definition.target_tree_count = 30
	check(worker.best_task().kind==&"PLANT" and worker.request_work(),"Planting precedes export when below target")
	var spot: Vector2 = scene.forestry_area.claims[actor.data.id]
	check(scene.forestry_area.spot_valid(hut,spot,actor.data.id),"Claimed planting spot passes spacing/building/navigation checks")
	walk(actor)
	var count: int = scene.trees.size()
	scene.game_time.debug_skip_minutes(10)
	check(scene.trees.size()==count and worker.work_minutes==10,"Planting requires actual work time")
	scene.player_control.move_to(actor.data.id,Vector2(0,500))
	check(scene.forestry_area.claims.is_empty() and worker.work_minutes==0 and scene.trees.size()==count,"Interrupted planting discards progress and releases spot")
	idle(actor)
	check(worker.request_work(),"Planting can start anew")
	walk(actor)
	scene.game_time.debug_skip_minutes(Balance.TREE_PLANTING_MINUTES)
	check(scene.trees.size()==count+1 and scene.forestry_area.claims.is_empty(),"Full planting creates exactly one individual sapling")
	var sapling = scene.trees.back()
	check(sapling.state==TreeData.State.SAPLING and sapling.growth_progress==0,"New tree starts as sapling")
	check(scene.runtime_placement_blockers.has_blocker(sapling.id) and not scene.navigation.is_world_walkable(Coordinates.to_world(sapling.position)) and scene.build_grid.occupied_cells(sapling.id).is_empty(),"Sapling blocks navigation/placement, never BuildGrid")
	var count_before: int = scene.forestry_area.tree_count(hut)
	check(not scene.forestry_area.spot_valid(hut,sapling.position) and not scene.forestry_area.spot_valid(hut,hut.position),"Tree and building overlap planting rejected")
	# Grow through the same minute-event implementation without unrelated 4320-minute needs simulation.
	scene._grow_trees(scene.game_time.total_minutes+Balance.TREE_GROWTH_MINUTES)
	check(sapling.state==TreeData.State.STANDING and sapling.physical_radius==Balance.TREE_PHYSICAL_RADIUS,"Configured growth produces normal mature tree")
	hut.resources.try_take(Resources.LOG,3)
	for tree in scene.trees:
		if tree != sapling: tree.claim(&"growth_fixture")
	check(worker.best_target().get("tree")==sapling,"Grown sapling becomes normal reachable chopping target")
	for tree in scene.trees: tree.release(&"growth_fixture")
	hut.resources.add(Resources.LOG,3)
	check(scene.forestry_area.tree_count(hut)==count_before and scene.runtime_placement_blockers.has_blocker(sapling.id),"Growth preserves identity/count and refreshes mature blocker")
	# Export interruption uses the shared haul cleanup, including after-pickup drops.
	hut.definition.target_tree_count = 0
	for picked_up in [false,true]:
		check(worker.request_work(),"Full hut falls back to export for interruption test")
		if picked_up: walk(actor,&"haul_source")
		var amount_before: int = hut.resources.get_amount(Resources.LOG)
		actor.intents.force_set_intent(preload("res://scripts/resident_intent.gd").new(preload("res://scripts/resident_intent.gd").Type.NONE,&"critical_sleep",Vector2.ZERO,0,false),100)
		check(hut.resources.get_reserved_out(Resources.LOG)==0 and scene.warehouse_data.resources.get_reserved_in(Resources.LOG)==0 and scene.logistics.get_job(actor.data.id)==null,"Critical export cleanup releases both container reservations")
		check(hut.resources.get_amount(Resources.LOG)==amount_before and actor.data.inventory.amount==0 and scene.ground_resources.drops.size()==(1 if picked_up else 0),"Only physically picked cargo becomes ground LOG on interrupt")
		actor.intents.abort_current(actor.intents.current_intent)
		Fixture.clear_drops(scene)
		if picked_up: hut.resources.add(Resources.LOG,1)
	# End of WORK phase cancels local collection instead of carrying into leisure.
	var end_drop = scene.ground_resources.create_drop(Resources.LOG,1,Coordinates.to_sim(Vector3(-24,0,-4)))
	hut.resources.try_take(Resources.LOG,1)
	check(worker.request_work() and worker.kind==&"COLLECT","Schedule cleanup starts local pickup")
	scene.game_time.total_minutes = 1019
	scene.game_time.debug_skip_minutes(1)
	check(worker.kind.is_empty() and end_drop.reservation_owner_id.is_empty() and hut.resources.get_reserved_in(Resources.LOG)==0,"End of WORK releases local task/reservations")
	Fixture.clear_drops(scene)
	idle(actor)
	hut.resources.add(Resources.LOG,1)
	scene.game_time.total_minutes = 420
	# All resources unavailable means no candidate, without forestry polling/forced action.
	hut.definition.target_tree_count = 0
	scene.warehouse_data.resources.add(Resources.LOG,19)
	check(worker.best_task().is_empty(),"Full hut and no accepting destination yields no task")
	scene.free()
	print("Lumberjack hut: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
