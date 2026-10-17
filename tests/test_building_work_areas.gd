extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const TreeData = preload("res://scripts/tree_data.gd")
const RockData = preload("res://scripts/rock_data.gd")
const Stacks = preload("res://tests/ground_stack_fixture.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Building = preload("res://scripts/building_instance.gd")
class CountedArea extends "res://scripts/world_3d/forestry_area_3d.gd":
	var searches := 0
	var probes := 0
	func spot_valid(building: RefCounted, point: Vector2, owner: String = "") -> bool:
		probes += 1
		return super.spot_valid(building,point,owner)
	func planting_target(building: RefCounted, origin: Vector2) -> Dictionary:
		searches += 1
		return super.planting_target(building,origin)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func capture(world: Node, label: String, center: Vector2) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	world._focus_work_area(center)
	world.get_node("World/Camera3D").set_zoom_distance(48)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w5b/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func show_worker(world: Node, actor: Node) -> void:
	world.resident_selection.select(actor.data)
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.info_panel.select_tab(&"work")
func run() -> void:
	root.size = Vector2i(1600,900)
	var world = F.create(self)
	await settle()
	var pc = world.player_control
	var hut = F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var second = F.building(world,T.LUMBERJACK_HUT,Vector3(-14,0,-20))
	var quarry = F.building(world,T.QUARRY,Vector3(26,0,-20))
	var second_quarry = F.building(world,T.QUARRY,Vector3(36,0,-20))
	var area = world.work_areas.create(C.to_sim(Vector3(36,0,20)),C.length_to_sim(8))
	var other_area = world.work_areas.create(C.to_sim(Vector3(-40,0,25)),C.length_to_sim(5))
	var actor = world.resident_runtimes[0]
	var miner = world.resident_runtimes[1]
	var other = world.resident_runtimes[2]
	var other_miner = world.resident_runtimes[3]
	var worker = actor.get_node("Lumberjack")
	var mining = miner.get_node("Miner")
	check(pc.get_building_work_area(hut.id).center==hut.position and pc.get_building_work_area(hut.id).radius==C.length_to_sim(hut.definition.work_radius),"DEFAULT preserves definition radius and building center")
	check(pc.get_building_work_area(&"absent")==null and not pc.assign_building_work_area(&"absent",area.id) and not pc.assign_building_work_area(world.warehouse_data.id,area.id),"Unknown and unsupported buildings reject CUSTOM")
	check(not pc.assign_building_work_area(hut.id,&"") and not pc.assign_building_work_area(hut.id,&"absent"),"Unknown/empty custom IDs are rejected")
	var pending = Building.new(&"pending",hut.definition,Vector2.ZERO,Building.State.UNDER_CONSTRUCTION)
	world.buildings.append(pending)
	check(not pc.assign_building_work_area(pending.id,area.id) and pc.get_building_work_area(pending.id)==null,"Under-construction buildings reject overrides")
	world.buildings.erase(pending)
	for building in [hut,second,quarry,second_quarry]:
		check(pc.assign_building_work_area(building.id,area.id) and pc.get_building_work_area(building.id)==area,"Buildings of both types share the original registry geometry")
	check(pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK) and pc.assign_workplace(miner.data.id,quarry.id,P.MINER) and pc.assign_workplace(other.data.id,second.id,P.LUMBERJACK) and pc.assign_workplace(other_miner.data.id,second_quarry.id,P.MINER),"Every building retains independent worker capacity")
	check(actor.data.work_area_id.is_empty() and miner.data.work_area_id.is_empty(),"Building override does not become a direct resident assignment")
	hut.resources.add(R.LOG,1)
	check(second.resources.get_amount(R.LOG)==0 and hut.resources!=second.resources and quarry.resources!=second_quarry.resources,"Shared geometry does not share buffers")
	var purpose := preload("res://scripts/building_slot_purpose.gd").Type.COURIER
	var uses = world.world_locations.uses
	var slot = uses.acquire(hut.id,purpose,"slot_a",Vector3.ZERO)
	var second_slot = uses.acquire(second.id,purpose,"slot_b",Vector3.ZERO)
	check(slot!=null and second_slot!=null and slot!=second_slot and uses.occupied_by(hut.id,"slot_a",purpose) and not uses.occupied_by(hut.id,"slot_b",purpose),"Shared geometry preserves independent COURIER slots and occupancy")
	uses.release(hut.id,slot,"slot_a")
	uses.release(second.id,second_slot,"slot_b")
	var first_tree = TreeData.new(&"custom_tree",C.to_sim(Vector3(34,0,20)))
	var next_tree = TreeData.new(&"custom_tree_second",C.to_sim(Vector3(38,0,20)))
	world._register_tree(first_tree)
	world._register_tree(next_tree)
	var rock = RockData.new(&"custom_rock",C.to_sim(Vector3(42,0,20)))
	world._register_rock(rock)
	check(world.forestry_area.tree_count(hut)==2 and world.forestry_area.tree_count(second)==2,"Tree count uses CUSTOM, excluding the old forest")
	check(worker.best_target().tree in [first_tree,next_tree] and mining.best_target().rock==rock,"CHOP and MINE select remote CUSTOM targets")
	check(worker.has_work() and worker.request_work() and mining.has_work() and mining.request_work(),"Normal has_work/request_work accepts remote CHOP and MINE")
	var accepted_tree = worker.tree
	check(not accepted_tree.claim(&"competitor") and not rock.claim(&"competitor"),"Existing source claims reject duplicate owners across shared buildings")
	check(other.get_node("Lumberjack").best_target().tree!=accepted_tree and other_miner.get_node("Miner").best_target().is_empty(),"Other buildings respect shared target claims")
	F.walk(world,actor)
	F.walk(world,miner)
	check(worker.chopping and mining.mining,"Both workers physically arrive at remote CUSTOM sources")
	world.game_time.debug_skip_minutes(10)
	show_worker(world,actor)
	check(world.work_highlight.circle.position.is_equal_approx(C.to_world(area.center)+Vector3(0,0.02,0)) and is_equal_approx(world.work_highlight.circle.mesh.get_aabb().size.x,16) and world.world_locations.get_view(hut.id).indicator.visible,"W2 highlights the assigned hut and effective CUSTOM circle")
	await capture(world,"01-custom-chop",area.center)
	show_worker(world,miner)
	await capture(world,"02-custom-mine",area.center)
	await settle()
	pc.edit_work_area(other_area.id,other_area.center+Vector2(10,0),other_area.radius)
	check(world._work_updates.is_empty(),"Unrelated area edit does not schedule any workers")
	var original_intents: Array = [actor.intents.current_intent,miner.intents.current_intent]
	pc.edit_work_area(area.id,C.to_sim(Vector3(-5,0,25)),C.length_to_sim(4))
	check(world._work_updates.size()==4 and world._work_updates.has(other_miner.data.id),"Geometry edit targets only the four assigned building workers")
	check(worker.best_target().is_empty() and mining.best_target().is_empty() and [actor.intents.current_intent,miner.intents.current_intent]==original_intents,"New searches use the edit while accepted CHOP/MINE retain their targets")
	pc.assign_workplace(other_miner.data.id,second_quarry.id,P.PORTER)
	await settle()
	pc.edit_work_area(area.id,area.center+Vector2(10,0),area.radius)
	check(not world._work_updates.has(other_miner.data.id),"A quarry porter does not receive mining-area decision notifications")
	# A direct FREE user and all buildings are cleaned in the same deletion command.
	pc.assign_work_area(other.data.id,area.id)
	world._view_work_area(area.id)
	world.work_area_dialog.open_delete(area.id)
	check(hut.id in world.work_area_dialog.warning.text and quarry.id in world.work_area_dialog.warning.text and second.id in world.work_area_dialog.warning.text and other.data.resident_name in world.work_area_dialog.warning.text,"Deletion warning names actual building and resident users")
	check(pc.remove_work_area(area.id),"Shared area can be deleted")
	for building in [hut,second,quarry,second_quarry]: check(building.work_area_override_id.is_empty(),"Deletion restores every building to DEFAULT")
	check(other.data.work_area_id.is_empty() and other.data.profession==P.LUMBERJACK and actor.data.work_location_id==hut.id and miner.data.work_location_id==quarry.id,"Deletion clears FREE assignment, preserving building memberships and professions")
	var stock: int = rock.stock
	var logs: int = Stacks.total(world.ground_resources,R.LOG)
	world.game_time.debug_skip_minutes(60)
	check(accepted_tree.state==TreeData.State.DEPLETED and rock.stock==stock-1 and worker.kind.is_empty() and mining.rock==null,"Accepted real CHOP/MINE finish after edit and deletion")
	check(Stacks.total(world.ground_resources,R.LOG)==logs+3 and accepted_tree.reservation_owner_id.is_empty() and rock.reservation_owner_id.is_empty(),"Accepted extraction yields once and releases source claims")
	show_worker(world,actor)
	check(world.work_highlight.circle.position.is_equal_approx(C.to_world(hut.position)+Vector3(0,0.02,0)),"Deletion restores the DEFAULT resident highlight")
	check(pc.assign_building_work_area(hut.id,other_area.id) and pc.reset_building_work_area(hut.id) and actor.data.work_location_id==hut.id and hut.resources.get_amount(R.LOG)==1,"Explicit reset preserves membership and inventory")
	pc.assign_building_work_area(hut.id,other_area.id)
	pc.assign_building_work_area(second.id,other_area.id)
	var replacement = world.work_areas.create(Vector2.ZERO,C.length_to_sim(5))
	var callback := func(id):
		if id==hut.id: pc.assign_building_work_area(second.id,replacement.id)
	pc.building_work_area_changed.connect(callback)
	pc.remove_work_area(other_area.id)
	pc.building_work_area_changed.disconnect(callback)
	check(hut.work_area_override_id.is_empty() and second.work_area_override_id==replacement.id,"Removal callbacks cannot erase a newly assigned different area")
	world.free()
	await planting_checks()
	print("Building work areas: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func planting_checks() -> void:
	var world = F.create(self)
	await settle()
	var pc = world.player_control
	var hut = F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var second = F.building(world,T.LUMBERJACK_HUT,Vector3(-14,0,-20))
	var actor = world.resident_runtimes[0]
	var worker = actor.get_node("Lumberjack")
	var counted := CountedArea.new()
	counted.setup(world)
	world.forestry_area = counted
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var collect_area = world.work_areas.create(C.to_sim(Vector3(35,0,25)),C.length_to_sim(8))
	pc.assign_building_work_area(hut.id,collect_area.id)
	var drop = Stacks.create(world.ground_resources,R.LOG,1,collect_area.center)
	check(worker.best_task().get("kind")==&"COLLECT" and worker.request_work(),"Remote CUSTOM admits ground COLLECT before CHOP/PLANT")
	var job = world.logistics.get_job(actor.data.id)
	check(job!=null and hut.resources.get_reserved_in(R.LOG)==1 and second.resources.get_reserved_in(R.LOG)==0,"COLLECT reserves only its own hut buffer")
	for leg in range(3): F.walk(world,actor)
	check(world.logistics.get_job(actor.data.id)==null and hut.resources.get_amount(R.LOG)==1 and drop.amount==0 and actor.data.inventory.amount==0,"Remote COLLECT physically delivers exactly one unit into its own hut")
	hut.definition.target_tree_count=0
	check(worker.best_task().get("kind")==&"EXPORT" and worker.request_work(),"CUSTOM preserves ordinary EXPORT when no local work exists")
	job = world.logistics.get_job(actor.data.id)
	var destination = world.player_control.get_building(job.destination_location_id)
	var delivered_before: int = destination.resources.get_amount(R.LOG)
	for leg in range(3): F.walk(world,actor)
	check(hut.resources.get_amount(R.LOG)==0 and destination.resources.get_amount(R.LOG)==delivered_before+1 and world.logistics.get_job(actor.data.id)==null,"EXPORT retains physical delivery and reserve cleanup")
	hut.definition.target_tree_count=12
	pc.remove_work_area(collect_area.id)
	for remove in [false,true]:
		world.game_time.total_minutes=420
		var area = world.work_areas.create(C.to_sim(Vector3(-5,0,25)),C.length_to_sim(8))
		pc.assign_building_work_area(hut.id,area.id)
		pc.assign_building_work_area(second.id,area.id)
		counted.probes=0
		var candidate := counted.planting_target(hut,actor.view.get_sim_position())
		check(not candidate.is_empty() and area.contains(candidate.spot) and counted.probes<112 and (remove or counted.probes==1),"Remote PLANT stops lazily; an empty region needs exactly one spot check")
		counted.searches=0
		check(worker.has_work() and worker.request_work() and worker.kind==&"PLANT" and counted.searches==1,"CUSTOM PLANT proposal avoids a second candidate search")
		var spot: Vector2 = counted.claims[actor.data.id]
		check(not counted.claim("other_hut_worker",second,spot),"Shared area prevents conflicting planting claims between huts")
		var intent = actor.intents.current_intent
		if remove: pc.remove_work_area(area.id)
		else: pc.edit_work_area(area.id,C.to_sim(Vector3(35,0,25)),C.length_to_sim(3))
		check(actor.intents.current_intent==intent and not counted.inside(hut,spot),"Accepted PLANT remains at the original spot after geometry changes")
		F.walk(world,actor)
		check(actor.data.activity==preload("res://scripts/resident_activity.gd").Type.WORKING,"Accepted planting physically arrives outside the new area")
		show_worker(world,actor)
		await capture(world,"03-planting-"+str(remove),spot)
		var before: int = world.trees.size()
		world.game_time.debug_skip_minutes(Balance.TREE_PLANTING_MINUTES)
		check(world.trees.size()==before+1 and world.trees.back().position==spot and counted.claims.is_empty() and counted._claim_areas.is_empty(),"Snapshot allows exactly one completed sapling and releases both claim records")
		if not remove: pc.remove_work_area(area.id)
	# Accepted geometry must never waive physical obstruction checks at completion.
	var safety_area = world.work_areas.create(C.to_sim(Vector3(35,0,25)),C.length_to_sim(8))
	pc.assign_building_work_area(hut.id,safety_area.id)
	check(worker.has_work(),"CUSTOM produces a one-use planting offer before a same-frame geometry edit")
	counted.searches=0
	pc.edit_work_area(safety_area.id,C.to_sim(Vector3(35,0,30)),C.length_to_sim(4))
	check(worker.request_work() and counted.searches==1 and safety_area.contains(counted.claims[actor.data.id]),"Edited geometry invalidates the offer and searches the new area before claiming")
	worker.abort(false)
	check(counted.claims.is_empty() and counted._claim_areas.is_empty(),"Cancelled CUSTOM planting releases its geometry snapshot and claim")
	var safety_candidate := counted.planting_target(hut,actor.view.get_sim_position())
	check(not safety_candidate.is_empty() and counted.claim("blocked",hut,safety_candidate.spot),"Physical safety fixture claims a valid spot")
	pc.remove_work_area(safety_area.id)
	world.runtime_placement_blockers.register_circle(&"late_blocker",func():return C.to_world(safety_candidate.spot),1.0)
	var safety_count: int = world.trees.size()
	check(not counted.complete("blocked",hut) and world.trees.size()==safety_count and counted.claims.is_empty(),"New physical obstruction still prevents accepted PLANT after deletion")
	world.runtime_placement_blockers.unregister(&"late_blocker")
	world.free()
