extends "res://tests/test_farming.gd"
const Step=preload("res://tests/handling_test_step.gd")
func patch() -> Dictionary:
	var env:=fixture();env.farm.set_stock_target(R.WHEAT,5)
	var cell: Vector2i=env.world.build_grid.world_to_cell(Vector3(-10,0,22))
	var area=env.world.work_areas.create(C.to_sim(env.world.build_grid.cell_to_world(cell)),C.length_to_sim(.76))
	env.world.player_control.assign_building_work_area(env.farm.id,area.id)
	return env
func finish_plow(world: Node,actor: Node) -> void:
	check(actor.farmer.request_work() and arrive(actor),"Real plow claim and physical arrival")
	world.game_time.debug_skip_minutes(10)
func finish_sow(world: Node,actor: Node,count: int) -> void:
	check(actor.farmer.request_work() and world.farm_fields.owned_cells(actor.farmer._owner).size()==count,"Sow reserves complete patch before moving")
	for index in count:
		check(arrive(actor),"Actual approach to sow cell")
		world.game_time.debug_skip_minutes(10)
func empty_first_patch() -> void:
	var env:=patch();var world=env.world;var farm=env.farm;var actor=env.actor
	for index in 5:
		check(actor.farmer.task().get("kind")==&"PLOW" and world.logistics.jobs.is_empty() and farm.resources.get_reserved_in(R.WHEAT)==0,"Initial plow precedes available grain import")
		finish_plow(world,actor)
	check(world.farm_fields.plot_cells().size()==5 and actor.farmer.task().kind==&"IMPORT","Five reachable cells with no seed choose import")
	await physics_frame;await process_frame
	check(actor.farmer.request_work(),"Normal farmer accepts one grain delivery")
	var job=world.logistics.get_job(actor.data.id)
	check(job!=null and job.resource_type==R.WHEAT and farm.resources.get_reserved_in(R.WHEAT)==1,"One inbound unit, not a five-unit bulk delivery")
	for index in 5:check(not actor.farmer.request_work() and farm.resources.get_reserved_in(R.WHEAT)==1,"Accepted haul prevents duplicate transport reserves")
	for step in 16000:
		Step.move_3d(actor,.05)
		if world.logistics.get_job(actor.data.id)==null:break
	check(job.state==job.State.COMPLETED and farm.resources.get_amount(R.WHEAT)==1 and farm.supply.stock_deficits().get(R.WHEAT)==4,"One physical delivery leaves target deficit4")
	check(actor.farmer.task().kind==&"SOW","Seed starts sowing before four additional imports")
	finish_sow(world,actor,5)
	check(farm.resources.get_amount(R.WHEAT)==0 and world.farm_fields.plot_cells().all(func(cell):return world.farm_fields.state(cell)==Fields.State.SOWN),"One seed pays all five real crops")
	check(actor.farmer.task().kind==&"PLOW","Next patch starts before refilling all five reserve units")
	world.free()
func one_seed_and_collect() -> void:
	var env:=patch();var world=env.world;var farm=env.farm;var actor=env.actor
	farm.resources.add(R.WHEAT,1)
	for index in 5:
		check(actor.farmer.task().kind==&"PLOW" and farm.resources.get_reserved_in(R.WHEAT)==0,"Existing one seed does not trigger reserve refill before initial patch")
		finish_plow(world,actor)
	var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,23.5))
	var stack=world.ground_resources.try_place(R.SHEAF,1,cell).stack
	# Put the sheaf inside the same small area, on a cell already prepared.
	world.ground_resources.remove_drop(stack)
	cell=world.farm_fields.plot_cells()[0]
	stack=world.ground_resources.try_place(R.SHEAF,1,cell).stack
	check(actor.farmer.task().kind==&"COLLECT","Collect supersedes both ready sow and import deficit")
	world.ground_resources.remove_drop(stack)
	check(actor.farmer.task().kind==&"SOW","Removing sheaf restores five-cell sow")
	check(actor.farmer.request_work(),"Accept sow before higher priority opportunity appears")
	var accepted=actor.farmer._intent
	stack=world.ground_resources.try_place(R.SHEAF,1,cell).stack
	check(actor.intents.current_intent==accepted and actor.farmer.phase!=actor.farmer.Phase.NONE and actor.farmer.task().is_empty(),"New sheaf cannot interrupt already accepted sow")
	actor.farmer.cancel();world.ground_resources.remove_drop(stack)
	check(farm.resources.get_amount(R.WHEAT)==1 and farm.resources.get_reserved_out(R.WHEAT)==0,"Unstarted sow cancels without seed loss")
	world.free()
func absent_grain() -> void:
	var env:=patch();var world=env.world;var farm=env.farm;var actor=env.actor
	world.warehouse_data.resources.try_take(R.WHEAT,10)
	for index in 5:finish_plow(world,actor)
	for index in 8:check(actor.farmer.task().kind==&"PLOW" and world.logistics.jobs.is_empty() and farm.resources.get_reserved_in(R.WHEAT)==0,"Unavailable import falls back to plow without claiming transport")
	check(actor.farmer.request_work(),"Accept sixth plow beyond initial patch")
	var accepted=actor.farmer._intent
	world.warehouse_data.resources.add(R.WHEAT,1)
	check(actor.intents.current_intent==accepted and actor.farmer.task().is_empty(),"Newly possible import does not interrupt accepted plow")
	check(arrive(actor),"Sixth real plow arrives");world.game_time.debug_skip_minutes(10)
	check(actor.farmer.task().kind==&"IMPORT","Next choice sees newly available external grain")
	farm.resources.add(R.WHEAT,1)
	check(actor.farmer.task().kind==&"SOW","Next choice sees newly available local seed instead of import")
	world.free()
func partial_and_porter() -> void:
	var env: Dictionary={}
	var world: Node
	var farm: RefCounted
	var actor: Node
	for count in range(1,5):
		env=patch();world=env.world;farm=env.farm;actor=env.actor
		var center: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,22))
		var area=world.work_areas.get_area(farm.work_area_override_id)
		world.player_control.edit_work_area(area.id,area.center,C.length_to_sim(.51))
		var candidates: Array=[center,center+Vector2i.UP,center+Vector2i.DOWN,center+Vector2i.LEFT,center+Vector2i.RIGHT]
		for cell in candidates.slice(count):world.ground_resources.try_place(R.LOG,1,cell)
		farm.resources.add(R.WHEAT,1)
		for index in count:finish_plow(world,actor)
		check(actor.farmer.task().kind==&"SOW" and actor.farmer.task().cells.size()==count,"No more legal cells permits partial sow ahead of import: %d"%count)
		finish_sow(world,actor,count)
		check(farm.resources.get_amount(R.WHEAT)==0 and world.farm_fields.plot_cells().size()==count,"Partial sow spends one seed without refund: %d"%count)
		world.free()
	env=patch();world=env.world;farm=env.farm;actor=env.actor
	for index in 5:finish_plow(world,actor)
	var porter=world.resident_runtimes[1]
	check(world.player_control.assign_workplace(porter.data.id,farm.id,P.PORTER),"Optional porter shares real farm stock demand")
	await physics_frame;await process_frame
	check(actor.farmer.request_work() and world._request_work(porter),"Farmer and porter can claim independent grain units")
	var first=world.logistics.get_job(actor.data.id);var second=world.logistics.get_job(porter.data.id)
	check(first!=null and second!=null and first!=second and farm.resources.get_reserved_in(R.WHEAT)==2 and farm.supply.stock_deficits().get(R.WHEAT)==3,"Inbound promises reduce deficit without double claiming")
	world.logistics.cancel_transport(first,"test");world.logistics.cancel_transport(second,"test")
	check(farm.resources.get_reserved_in(R.WHEAT)==0 and world.warehouse_data.resources.get_reserved_out(R.WHEAT)==0,"Both owners release only real obligations")
	world.free()
func autumn_order() -> void:
	var env:=patch();var world=env.world;var farm=env.farm;var actor=env.actor
	var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,22))
	world.farm_fields.reserve([cell],&"setup",Fields.State.BARE);world.farm_fields.plow(cell,&"setup")
	world.farm_fields.reserve([cell],&"setup",Fields.State.PLOWED);world.farm_fields.sow(cell,&"setup",1,func():return true)
	world.game_time.debug_skip_minutes(6*1440+420-world.game_time.total_minutes)
	for resident in world.resident_runtimes:resident.intents.abort_current(resident.intents.current_intent)
	check(actor.farmer.task().kind==&"IMPORT","Autumn import remains ahead of mow when real seed deficit exists")
	farm.set_stock_target(R.WHEAT,0);farm.resources.add(R.WHEAT,50);farm.resources.add(R.SHEAF,1)
	world.warehouse_data.resources.try_take(R.WHEAT,10)
	check(actor.farmer.task().kind==&"MOW","Mature crop precedes full-buffer export and thresh")
	world.farm_fields._plots.clear();world.farm_fields.revision+=1
	check(actor.farmer.task().kind==&"EXPORT","Full output exports before thresh")
	farm.resources.try_take(R.WHEAT,1)
	check(actor.farmer.task().kind==&"THRESH","With output room and no other work, thresh remains available")
	world.free()
func run() -> void:
	await empty_first_patch();one_seed_and_collect();absent_grain();await partial_and_porter();autumn_order()
	print("UX3 farmer priorities: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
