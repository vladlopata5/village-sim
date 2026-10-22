extends "res://tests/test_textile_production.gd"
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const Clay=preload("res://scripts/clay_deposit_data.gd")
const Rock=preload("res://scripts/rock_data.gd")
const Locations=preload("res://scripts/world_3d/natural_source_locations_3d.gd")
const Grid=preload("res://scripts/navigation_grid.gd")
func run() -> void:
	finite_source()
	await mining_lifecycle()
	print("Clay mining: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func finite_source() -> void:
	var clay=Clay.new(&"clay",Vector2.ZERO);var stone=Rock.new(&"stone",Vector2.ZERO)
	check(clay.resource_type==R.CLAY and clay.stock==stone.stock and clay.work_required==stone.work_required and clay.physical_radius==stone.physical_radius,"Separate clay source follows actual finite stone balance")
	check(clay.claim(&"one") and not clay.claim(&"two") and clay.add_work(&"two",60)==0,"Exclusive claim rejects another worker")
	check(clay.add_work(&"one",59)==0 and clay.stock==10,"No unpaid yield")
	clay.release(&"two");check(clay.reservation_owner_id==&"one","Foreign release cannot steal claim")
	clay.release(&"one");check(clay.claim(&"two") and clay.add_work(&"two",1)==1 and clay.stock==9,"Interrupted partial work resumes and produces exactly one receipt")
	for cycle in 9:check(clay.claim(&"one") and clay.add_work(&"one",60)==cycle+2,"Each finite unit has unique receipt")
	check(clay.stock==0 and not clay.claim(&"two") and clay.add_work(&"one",999)==0,"Last unit cannot be duplicated")
	var map=Grid.new(Rect2(-10,-10,20,20));var resolver=Locations.new();resolver.navigation=map
	clay=Clay.new(&"water_clay",Coord.to_sim(Vector3(4.25,0,.25)))
	map.add_blocker(clay.id,Rect2(3.35,-.65,1.8,1.8))
	check(resolver.resolve(clay,Coord.to_sim(Vector3(-4.25,0,.25))) is Vector2,"Ordinary approach is reachable")
	var cells: Dictionary={}
	for z in range(-20,20):cells[map.world_to_cell(Vector3(.25,0,float(z)*.5+.25))]=true
	map.edit_terrain_cells(cells)
	check(resolver.resolve(clay,Coord.to_sim(Vector3(-4.25,0,.25)))==null,"WATER separates source; no accepted impossible approach")
func mining_lifecycle() -> void:
	var world=F.create(self)
	var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16))
	var actor=world.resident_runtimes[0];var rival=world.resident_runtimes[1];var miner=actor.get_node("Miner")
	check(hut.resources.get_capacity(R.CLAY)==12 and hut.definition.worker_capacity==1 and hut.definition.porter_capacity==1 and hut.definition.work_radius==15,"Hut repeats quarry slots/buffer/world radius")
	check(world.player_control.assign_workplace(actor.data.id,hut.id) and actor.data.profession==P.CLAY_DIGGER and not world.player_control.assign_workplace(rival.data.id,hut.id,P.CLAY_DIGGER),"Default clay role and capacity")
	var result: Dictionary=world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16));check(result.ok,"Debug creates normal finite source")
	if not result.ok:world.free();return
	var deposit=result.objects[0]
	check(deposit in world.rocks and world.rock_views.has(deposit.id) and not world.navigation.is_world_walkable(Coord.to_world(deposit.position)),"Clay enters normal view/obstacle registries")
	check(not world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16)).ok and not world.debug_spawn.spawn_clay_deposit(Vector3(-10,0,16)).ok,"Reject occupied source and building")
	check(not world.debug_spawn.spawn_clay_deposit(Vector3(INF,0,0)).ok and not world.debug_spawn.spawn_clay_deposit(Vector3(100,0,0)).ok,"Reject invalid and outside positions")
	var wet:=Vector3(-23,0,23);var cell: Vector2i=world.build_grid.world_to_cell(wet)
	check(world.paint_terrain([cell],world.farm_fields.Terrain.WATER) and not world.debug_spawn.spawn_clay_deposit(wet).ok,"F10 source rejects WATER")
	check(miner.has_work() and miner._available.rock==deposit and miner.request_work(),"Building mining targets clay, never nearby stone")
	var previous_stock: int=deposit.stock
	actor.intents.abort_current(actor.intents.current_intent)
	check(deposit.stock==previous_stock and deposit.reservation_owner_id.is_empty(),"Cancel before arrival releases source without yield")
	check(miner.request_work(),"Reclaim after cancel")
	var area=world.work_areas.create(Coord.to_sim(Vector3(-10,0,16)),Coord.length_to_sim(2))
	check(world.player_control.assign_building_work_area(hut.id,area.id),"Existing building CUSTOM assignment")
	check(miner.rock==null and deposit.reservation_owner_id.is_empty() and miner.best_target().is_empty(),"Area change immediately cancels incompatible accepted mining")
	check(world.player_control.reset_building_work_area(hut.id) and miner.request_work(),"DEFAULT area resumes discoverability")
	world.player_control.assign_profession(actor.data.id,P.POTTER)
	check(miner.rock==null and deposit.reservation_owner_id.is_empty(),"Profession change releases clay claim immediately")
	world.player_control.assign_workplace(actor.data.id,hut.id)
	hut.resources.add(R.CLAY,12)
	check(miner.best_target().is_empty(),"Full physical buffer blocks new extraction")
	hut.resources.try_take(R.CLAY,1);hut.resources.reserve_in(R.CLAY,1)
	check(miner.best_target().is_empty(),"Inbound promise also fills last place")
	hut.resources.release_in(R.CLAY,1);hut.resources.try_take(R.CLAY,11)
	check(miner.request_work(),"Space admits normal mining again")
	world.rocks.erase(deposit);world.game_time.debug_skip_minutes(1)
	check(miner.rock==null and deposit.reservation_owner_id.is_empty(),"Removed moving target aborts on next ordinary minute")
	world.rocks.append(deposit)
	check(miner.request_work(),"Source can be selected after fixture restores it")
	for i in 8000:
		actor.view._physics_process(.05)
		if miner.mining:break
	check(miner.mining,"Actual movement reaches annulus")
	deposit.stock=1
	world.game_time.debug_skip_minutes(59)
	check(deposit.stock==1,"No early last unit")
	world.game_time.debug_skip_minutes(1)
	check(deposit.stock==0 and deposit not in world.rocks and not world.rock_views.has(deposit.id) and miner.rock==null,"Depletion removes registry/view and clears operation")
	var total:=0
	for stack in world.ground_resources.drops:
		if stack.resource_type==R.CLAY:total+=stack.amount
	world._complete_rock_cycle(deposit,deposit.completed_cycles,actor.view.get_sim_position())
	var repeated:=0
	for stack in world.ground_resources.drops:
		if stack.resource_type==R.CLAY:repeated+=stack.amount
	check(total==1 and repeated==1 and actor.data.inventory.amount==0,"Public physical yield once; repeated receipt cannot duplicate")
	check(miner.has_work() and miner._available.kind==&"COLLECT","Next normal work collects yielded clay")
	var job=await haul(world,actor)
	check(job!=null and job.resource_type==R.CLAY and hut.resources.get_amount(R.CLAY)==1,"Real unit delivered through shared HaulExecutor")
	check(miner.best_target().is_empty() and not miner.has_work(),"No remaining deposit or receiver: no endless fake task")
	for resource in R.values():check(hut.resources.get_reserved_in(resource)==0 and hut.resources.get_reserved_out(resource)==0,"Completed clay cycle leaves no reservations")
	world.free();await process_frame
