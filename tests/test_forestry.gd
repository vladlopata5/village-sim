extends SceneTree
const TreeData = preload("res://scripts/tree_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Resources = preload("res://scripts/resource_type.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Skill = preload("res://scripts/skill_type.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func arrive(actor: Node) -> void:
	for step in range(500):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func run() -> void:
	var data = TreeData.new(&"unit_tree",Vector2(25,50))
	check(data.id == &"unit_tree" and data.KIND == &"TREE" and data.state == TreeData.State.STANDING,"Stable tree identity and STANDING")
	check(not data.add_work(&"",1) and data.work_done == 0,"Unreserved tree rejects work")
	check(data.work_required == 60 and data.yield_amount == 3,"Data-driven work/yield defaults")
	check(data.claim(&"one") and not data.claim(&"two"),"Exclusive atomic reservation")
	check(data.add_work(&"one",30) and data.work_done == 30,"Tree owns partial work")
	data.release(&"one")
	check(data.work_done == 30 and data.claim(&"two"),"Release preserves progress for another worker")
	data.add_work(&"two",100)
	check(data.work_done == 60 and data.state == TreeData.State.DEPLETED and data.reservation_owner_id.is_empty() and not data.claim(&"three"),"Clamped depletion cannot reserve again")
	var grid = preload("res://scripts/navigation_grid.gd").new(Rect2(-5,-5,10,10),0.4)
	var resolver = preload("res://scripts/world_3d/tree_locations_3d.gd").new()
	resolver.navigation = grid
	var inaccessible = TreeData.new(&"disconnected",Vector2(56.25,6.25))
	grid.add_blocker(&"wall",Rect2(-0.5,-5,1,10))
	check(resolver.resolve(inaccessible,Vector2(-56.25,6.25)) == null,"All disconnected perimeter candidates rejected before work selection")
	grid.remove_blocker(&"wall")
	var accessible: Variant = resolver.resolve(inaccessible,Vector2(-56.25,6.25))
	check(accessible is Vector2,"Reachable perimeter becomes available after dynamic blocker removal")
	grid.add_blocker(&"cover",Rect2(-5,-5,10,10))
	check(resolver.resolve(inaccessible,Vector2(-56.25,6.25)) == null,"All blocked access candidates reject tree")
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for actor in scene.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.cancel_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	await physics_frame
	check(scene.trees.size() == 16 and scene.tree_views.size() == 16,"Deterministic starter forest has separate views")
	var ids: Dictionary = {}
	for tree in scene.trees:
		check(not ids.has(tree.id),"Unique tree ID")
		ids[tree.id] = true
		check(not scene.navigation.is_world_walkable(Coordinates.to_world(tree.position)),"Standing tree blocks navigation including clearance")
		check(scene.runtime_placement_blockers.has_blocker(tree.id),"Tree opt-in generic placement blocker")
		check(scene.build_grid.occupied_cells(tree.id).is_empty(),"Tree never occupies BuildGrid")
		var point: Variant = scene.tree_locations.resolve(tree,scene.resident_runtimes[1].view.get_sim_position())
		check(point is Vector2 and point.distance_to(tree.position) > tree.physical_radius*25 and scene.navigation.is_world_walkable(Coordinates.to_world(point)),"Access is outside footprint and navigable/reachable")
		check(point == scene.tree_locations.resolve(tree,scene.resident_runtimes[1].view.get_sim_position()),"Access resolver deterministic")
	var actor = scene.resident_runtimes[1]
	var worker = actor.get_node("Lumberjack")
	check(scene.player_control.assign_profession(actor.data.id,Profession.Type.LUMBERJACK) and Profession.display_name(actor.data.profession)=="Лесоруб","Existing management API allows world-work profession")
	check(not worker.request_work(),"No chopping outside WORK phase")
	scene.game_time.debug_skip_minutes(60)
	check(scene._work_available(actor) and actor.decision.collect_actions(true)[0].id == "WORK" and worker.request_work(),"Normal WORK category/provider selects reachable tree; no site score vs need utility")
	var target_tree = worker.tree
	check(target_tree.reservation_owner_id == StringName(actor.data.id) and not worker.chopping,"Reserved before travel; no work before arrival")
	var second = scene.resident_runtimes[2]
	scene.player_control.assign_profession(second.data.id,Profession.Type.LUMBERJACK)
	check(second.get_node("Lumberjack").best_target().tree != target_tree,"Second worker skips reserved tree")
	var definition = preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME)
	scene.placement.select(definition)
	scene.placement.update_world_position(Coordinates.to_world(target_tree.position))
	check(not scene.placement.can_place(),"Building over standing tree rejected")
	arrive(actor)
	check(worker.chopping and actor.view.get_sim_position().distance_to(worker.target)<8,"Real executor arrives at perimeter before chopping")
	var wood_before: int = scene.warehouse_data.resources.get_amount(Resources.Type.WOOD)
	scene.game_time.debug_skip_minutes(60)
	check(target_tree.state==TreeData.State.DEPLETED and target_tree.work_done==60 and target_tree.reservation_owner_id.is_empty(),"60 actual minutes deplete and release")
	check(not scene.tree_views.has(target_tree.id) and not scene.runtime_placement_blockers.has_blocker(target_tree.id),"View/placement registration removed")
	check(scene.navigation.is_world_walkable(Coordinates.to_world(target_tree.position)),"Navigation opens immediately without rebake")
	check(scene.ground_resources.drops.size()==3 and scene._ground_views.size()==3,"Exactly three individual ground objects and 3D views")
	for drop in scene.ground_resources.drops:
		check(drop.resource_type==Resources.Type.LOG and drop.amount==1 and scene.navigation.is_world_walkable(Coordinates.to_world(drop.world_position)),"One physical LOG with valid deterministic position")
	check(scene.warehouse_data.resources.get_amount(Resources.Type.WOOD)==wood_before and scene.warehouse_data.resources.get_amount(Resources.Type.LOG)==0,"No conversion/storage/logistics transfer")
	check(actor.data.get_skill_xp(Skill.Type.GATHERING)==1 and actor.data.get_skill_xp(Skill.Type.LOGISTICS)==0,"One completed tree grants Gathering XP only")
	actor.view.global_position = Vector3(0,0,20)
	check(scene.placement.can_place(),"Former tree space buildable after resident leaves; loose LOG not blockers")
	scene.placement.cancel()
	check(worker.request_work(),"Next decision can select another tree")
	arrive(actor)
	var partial = worker.tree
	scene.game_time.debug_skip_minutes(30)
	scene.player_control.move_to(actor.data.id,Vector2(0,500))
	check(partial.work_done==30 and partial.reservation_owner_id.is_empty() and worker.tree==null,"PlayerCommand preserves 30 minutes/releases task")
	check(actor.data.get_skill_xp(Skill.Type.GATHERING)==1,"Interrupted tree grants no XP")
	arrive(actor)
	# Keep only partial tree available to prove resume rather than fresh work.
	for tree in scene.trees:
		if tree != partial and tree.state == TreeData.State.STANDING: tree.claim(&"fixture")
	check(worker.request_work() and worker.tree==partial,"Another ordinary task resumes partial tree")
	arrive(actor)
	scene.game_time.debug_skip_minutes(30)
	check(partial.state==TreeData.State.DEPLETED and scene.ground_resources.drops.size()==6,"Resume 30 minutes completes remaining work and one additional yield")
	for tree in scene.trees: tree.release(&"fixture")
	check(worker.request_work(),"Critical interruption fixture starts")
	arrive(actor)
	var critical_tree = worker.tree
	scene.game_time.debug_skip_minutes(7)
	actor.intents.force_set_intent(preload("res://scripts/resident_intent.gd").new(preload("res://scripts/resident_intent.gd").Type.NONE,&"critical_sleep",Vector2.ZERO,0,false),100)
	check(critical_tree.work_done==7 and critical_tree.reservation_owner_id.is_empty(),"Critical forced pipeline preserves work/releases reservation")
	actor.intents.abort_current(actor.intents.current_intent)
	scene.game_time.total_minutes = 1015
	check(worker.request_work(),"Schedule interruption fixture starts")
	arrive(actor)
	var scheduled_tree = worker.tree
	scene.game_time.debug_skip_minutes(5)
	check(scheduled_tree.work_done>=5 and scheduled_tree.reservation_owner_id.is_empty(),"End-of-work schedule cleanup keeps partial work")
	scene.game_time.total_minutes = 420
	check(worker.request_work(),"Removal cleanup fixture starts")
	var removed_task = worker.tree
	worker.free()
	check(removed_task.reservation_owner_id.is_empty(),"Resident controller removal releases tree reservation")
	worker = second.get_node("Lumberjack")
	check(worker.request_work(),"Executor-removal fixture starts")
	var executor_task = worker.tree
	second.view.free()
	check(executor_task.reservation_owner_id.is_empty() and worker.tree == null,"World executor removal immediately releases tree reservation")
	for tree in scene.trees:
		if tree.state == TreeData.State.STANDING: tree.claim(&"fixture")
	check(worker.tree == null,"Removed worker leaves no hanging task")
	var idle = scene.resident_runtimes[3]
	scene.player_control.assign_profession(idle.data.id,Profession.Type.LUMBERJACK)
	check(not idle.get_node("Lumberjack").has_work() and not idle.get_node("Lumberjack").request_work(),"No available trees declines without hanging action")
	scene.free()
	print("Forestry: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
