extends "res://tests/test_clay_mining.gd"
const Stacks=preload("res://tests/ground_stack_fixture.gd")
class CountedLocations extends Locations:
	var queries:=0
	var rejected: StringName
	func resolve(source: RefCounted, origin: Vector2) -> Variant:
		queries+=1
		return null if source.id==rejected else super.resolve(source,origin)
func run() -> void:
	await free_clay()
	print("FREE clay mining: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func walk(actor: Node) -> void:
	for step in 8000:
		actor.view._physics_process(.05)
		if not actor.view.movement.is_moving():break
func free_clay() -> void:
	var world=F.create(self)
	var pc=world.player_control
	var actor=world.resident_runtimes[0];var rival=world.resident_runtimes[1]
	var worker=actor.get_node("Miner");var other=rival.get_node("Miner")
	var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16))
	var one: Dictionary=world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16))
	var two: Dictionary=world.debug_spawn.spawn_clay_deposit(Vector3(-23,0,16))
	check(one.ok and two.ok,"Normal finite clay fixture")
	if not one.ok or not two.ok:world.free();return
	var source=one.objects[0];var second=two.objects[0]
	check(pc.assign_profession(actor.data.id,P.CLAY_DIGGER) and pc.can_assign_work_area(actor.data.id),"Clay profession accepts personal areas")
	check(not worker.has_work() and not worker.request_work(),"No automatic territory without an area")
	actor.data.work_area_id=&"missing"
	check(not worker.has_work(),"Missing area also supplies no work")
	actor.data.work_area_id=&""
	var area=world.work_areas.create(source.position,Coord.length_to_sim(2))
	check(pc.assign_work_area(actor.data.id,area.id) and actor.data.work_location_id.is_empty(),"Personal assignment enters FREE")
	check(pc.assign_profession(actor.data.id,P.CLAY_DIGGER) and actor.data.work_area_id==area.id,"Repeated same profession preserves personal assignment")
	var counted=CountedLocations.new();counted.navigation=world.navigation;worker.locations=counted
	check(worker.has_work() and worker._available.rock==source and worker.request_work() and counted.queries==1,"One-use proposal reuses reachable in-area clay target")
	check(pc.assign_workplace(rival.data.id,hut.id) and pc.assign_building_work_area(hut.id,area.id),"Hut competitor uses same source area")
	check(other.best_target().is_empty() and source.reservation_owner_id==StringName(actor.data.id),"FREE claim excludes hut miner from the same deposit")
	walk(actor)
	check(worker.mining and world.rock_locations.in_range(source,actor.view.get_sim_position()),"FREE worker physically reaches mining annulus")
	source.stock=1
	world.game_time.debug_skip_minutes(59)
	check(source.stock==1 and Stacks.total(world.ground_resources,R.CLAY)==0,"No early unit")
	world.game_time.debug_skip_minutes(1)
	var amount: int=Stacks.total(world.ground_resources,R.CLAY)
	check(amount==1 and source.stock==0 and source not in world.rocks and worker.rock==null and actor.data.inventory.amount==0,"Last unit creates physical ground clay once without inventory/hut delivery")
	world._complete_rock_cycle(source,source.completed_cycles,actor.view.get_sim_position())
	check(Stacks.total(world.ground_resources,R.CLAY)==amount and other.best_target().is_empty() and not worker.has_work(),"Depleted target and duplicate receipt cannot produce another last unit")
	var drop=world.ground_resources.drops.filter(func(item):return item.resource_type==R.CLAY)[0]
	check(world.rock_locations.is_available(drop.world_position) and hut.resources.get_amount(R.CLAY)==0,"Yield follows FREE stone placement on walkable ground")
	check(drop.reserve(&"fixture_consumer") and world.ground_resources.take_reserved(drop,&"fixture_consumer"),"Completed ground yield can be consumed normally")
	area.update(second.position,Coord.length_to_sim(2))
	check(worker.request_work() and worker.rock==second,"Next ordinary search discovers remaining in-area work")
	area.update(Coord.to_sim(Vector3(-30,0,30)),Coord.length_to_sim(1))
	check(worker.rock==null and second.reservation_owner_id.is_empty() and second.stock==10 and not worker.has_work(),"Editing area cancels incompatible accepted clay without unpaid yield")
	area.update(second.position,Coord.length_to_sim(2))
	check(worker.request_work(),"Restored personal area can resume")
	check(pc.remove_work_area(area.id) and worker.rock==null and second.reservation_owner_id.is_empty() and actor.data.work_area_id.is_empty(),"Removing area clears assignment and live claim immediately")
	area=world.work_areas.create(second.position,Coord.length_to_sim(2))
	pc.assign_work_area(actor.data.id,area.id)
	check(worker.request_work(),"New personal period")
	pc.clear_work_assignment(rival.data.id)
	pc.reset_building_work_area(hut.id)
	check(pc.assign_workplace(actor.data.id,hut.id) and worker.rock==null and second.reservation_owner_id.is_empty() and actor.data.work_area_id.is_empty(),"FREE to hut cancels old operation before hut work")
	# The hut may COLLECT the preceding yield first; target selection remains unchanged.
	check(worker.best_target().get("rock")==second,"Hut still finds clay using its ordinary building area")
	pc.assign_building_work_area(hut.id,area.id)
	check(worker.request_work() and worker.committed_context!=null and worker.committed_context.workplace==hut,"Hut mining still captures workplace")
	check(pc.assign_work_area(actor.data.id,area.id) and actor.data.work_location_id.is_empty() and worker.rock==null and second.reservation_owner_id.is_empty(),"Hut to FREE cancels old claim and selects personal mode")
	check(worker.request_work() and worker.committed_context!=null and worker.committed_context.workplace==null,"Next task uses FREE context")
	check(pc.clear_work_assignment(actor.data.id) and worker.rock==null and second.reservation_owner_id.is_empty() and not worker.has_work(),"Clearing personal assignment stops mining without phantom work")
	pc.assign_work_area(actor.data.id,area.id);worker.request_work()
	pc.assign_profession(actor.data.id,P.POTTER)
	check(worker.rock==null and second.reservation_owner_id.is_empty(),"Profession change releases accepted clay")
	pc.assign_workplace(actor.data.id,hut.id);check(worker.request_work(),"Hut claim before building removal")
	pc.unregister_building(hut.id)
	check(worker.rock==null and second.reservation_owner_id.is_empty() and not worker.has_work(),"Removed hut releases accepted clay and never auto-selects territory")
	pc.assign_work_area(actor.data.id,area.id)
	check(worker.request_work(),"Personal assignment restores independent work after hut removal")
	worker.abort(false)
	area.update((source.position+second.position)/2,Coord.length_to_sim(5))
	# Resolver rejection proves continuing to later candidates; real WATER geometry is covered by test_clay_mining.
	var three: Dictionary=world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,22))
	check(three.ok,"Additional approach candidate")
	area.update(second.position,Coord.length_to_sim(10))
	counted.rejected=second.id
	check(worker.best_target().get("rock")==three.objects[0],"Unreachable first candidate is skipped for a later reachable clay source")
	counted.rejected=&""
	world.free();await process_frame
