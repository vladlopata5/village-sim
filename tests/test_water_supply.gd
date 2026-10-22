extends "res://tests/test_textile_production.gd"
const Fields=preload("res://scripts/farm_fields.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const Coordinates=preload("res://scripts/world_3d/world_coordinates.gd")
var observer: Callable
func observe(world: Node, stage: String) -> void:
	if observer.is_valid():await observer.call(world,stage)
func kitchen(world: Node) -> RefCounted:
	var place=F.building(world,T.FOOD,Vector3(16,0,16))
	place.definition.logistics_flow[R.FOOD]["import"]=false
	place.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF)
	place.consumable_receivers[&"fuel"].reserve_in(R.LOG,1);place.consumable_receivers[&"fuel"].add_reserved(R.LOG,1)
	place.resources.add(R.FLOUR,2)
	return place
func lake(world: Node) -> Vector2i:
	var center: Vector2i=world.build_grid.world_to_cell(Vector3(-12,0,16))
	var cells: Array=[]
	for y in 4:
		for x in 6:cells.append(center+Vector2i(x,y))
	check(world.paint_terrain(cells,Fields.Terrain.WATER),"Create real lake")
	var sand: Array=[]
	for x in 6:sand.append(center+Vector2i(x,-1))
	check(world.paint_terrain(sand,Fields.Terrain.SAND),"Optional sand only on one side")
	return center
func arrive_without_time(actor: Node) -> void:
	for step in 18000:
		actor.view._physics_process(.05)
		if not actor.intents.current_intent.resource_handling.is_empty():return
	check(false,"Physical source reached")
func run() -> void:
	stock_contracts()
	await from_lake()
	await wells()
	interruptions()
	await concurrent_and_removal()
	print("Water supply: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func from_lake() -> void:
	var world=F.create(self);var place=kitchen(world);var cell=lake(world)
	var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,place.id,P.COOK)
	# Force the chosen bank to be normal grass; sand is optional, never privileged.
	var grass: Vector2i=cell+Vector2i(6,2)
	actor.view.global_position=world.build_grid.cell_to_world(grass+Vector2i(2,0))
	actor.view.movement.reset_physical_origin()
	check(world._request_work(actor),"Zero water triggers ordinary cook SUPPLY")
	var job=world.logistics.get_job(actor.data.id)
	check(job!=null and job.source_ref.kind==Source.Kind.WATER and job.receiver==place.consumable_receivers[&"water"],"Explicit water source and C1 receiver")
	arrive_without_time(actor)
	var bank: Vector2i=world.build_grid.world_to_cell(actor.view.global_position)
	check(world.farm_fields.terrain(bank)==Fields.Terrain.GRASS and world.water_sources.banks.has(bank) and actor.data.inventory.amount==0,"Resident reaches adjacent grass without entering water")
	check(not world.paint_terrain([bank],Fields.Terrain.WATER),"Claimed bank cannot be changed under an action")
	await observe(world,"01-lake-bank")
	world.game_time.debug_skip_minutes(9)
	check(actor.data.inventory.amount==0 and place.consumable_stocks[&"water"].amount==0,"No water before ten minutes")
	world.game_time.debug_skip_minutes(1)
	check(actor.data.inventory.amount==1 and actor.data.inventory.resource_type==R.WATER and place.consumable_stocks[&"water"].amount==0,"Ten minutes create exactly one finite cargo, not numerical water")
	await observe(world,"02-carrying-water")
	for step in 18000:
		if world.logistics.get_job(actor.data.id)==null:break
		Step.move_3d(actor,.05)
	check(job.state==job.State.COMPLETED and place.consumable_stocks[&"water"].amount==5 and actor.data.inventory.amount==0 and place.resources.get_amount(R.WATER)==0,"Successful real unload converts one cargo into five units once")
	check(not world.logistics.deliver_inbound(job) and place.consumable_stocks[&"water"].amount==5,"Repeated unload has no claim")
	await observe(world,"03-lake-delivered")
	if not await start_recipe(world,actor):world.free();return
	check(place.consumable_stocks[&"fuel"].amount==4 and place.consumable_stocks[&"water"].amount==4 and place.resources.get_amount(R.FLOUR)==1,"Actual start pays flour/fuel/water together")
	var batch=actor.recipe_work.batch
	world.game_time.debug_skip_minutes(10);actor.intents.abort_current(actor.intents.current_intent)
	check(batch.can_resume() and batch.progress==10,"Paid water survives pause")
	if not await start_recipe(world,actor):world.free();return
	check(place.consumable_stocks[&"water"].amount==4,"Resume does not repay water")
	world.game_time.debug_skip_minutes(20)
	check(place.resources.get_amount(R.BREAD)==2,"Two bread after thirty actual work minutes")
	await observe(world,"04-bread")
	place.consumable_stocks[&"water"].reserve(&"test",4);place.consumable_stocks[&"water"].commit_payment(&"test")
	place.set_recipe_mode(&"bake_bread",B.ProductionMode.OFF);place.set_recipe_mode(&"fried_mushroom",B.ProductionMode.UNLIMITED);place.resources.add(R.MUSHROOM,1)
	check(not place.can_start_production(&"bake_bread") and place.can_start_production(&"fried_mushroom"),"No water blocks bread but never mushrooms")
	if not await start_recipe(world,actor):world.free();return
	world.game_time.debug_skip_minutes(30)
	check(place.resources.get_amount(R.FRIED_MUSHROOM)==2 and place.consumable_stocks[&"water"].amount==0,"Mushrooms use no water")
	await observe(world,"05-mushrooms-no-water")
	world.free()
func wells() -> void:
	var world=F.create(self);var place=kitchen(world)
	var def=D.for_type(T.WELL)
	check(def.construction_requirements=={R.LOG:4,R.STONE:4} and def.construction_work_required==120 and def.worker_capacity==0 and def.porter_capacity==0,"Well agreed materials/labour and no employees")
	world.placement.select(def);world.placement.update_world_position(Vector3(-12,0,16))
	var site=world.placement.confirm()
	check(site!=null and not site.is_built() and world.water_sources.candidates().is_empty(),"Unfinished well has no infinite supply")
	world.warehouse_data.resources.add(R.LOG,4);world.warehouse_data.resources.add(R.STONE,4)
	var builder=world.resident_runtimes[1];world.player_control.assign_profession(builder.data.id,P.BUILDER)
	for step in 22000:
		if site.is_built():break
		if not builder.intents.has_current_action():world._request_work(builder)
		Step.move_3d(builder,.05);world.game_time.advance(.05)
	check(site.is_built() and site.construction_progress==120 and site.construction_delivered=={R.LOG:4,R.STONE:4},"Ordinary builder delivers eight items and completes120 work")
	builder.intents.abort_current(builder.intents.current_intent)
	var actor=world.resident_runtimes[0];world.player_control.assign_workplace(actor.data.id,place.id,P.COOK)
	var job=await haul(world,actor)
	check(job!=null and job.source_location_id==site.id and place.consumable_stocks[&"water"].amount==5,"Real well delivers five without any lake")
	await observe(world,"06-well-delivered")
	var porter=world.resident_runtimes[2];world.player_control.assign_workplace(porter.data.id,place.id,P.PORTER)
	# Isolate water from the equally ordinary fuel prefill.
	place.consumable_receivers[&"fuel"].reserve_in(R.LOG,3);place.consumable_receivers[&"fuel"].add_reserved(R.LOG,3)
	job=await haul(world,porter)
	check(job.resource_type==R.WATER and place.consumable_stocks[&"water"].amount==10,"Porter prefills nonzero water")
	check(actor.self_logistics.task().kind==&"PRODUCTION","Cook does not top up nonempty water")
	var receiver: RefCounted=place.consumable_receivers[&"water"]
	check(receiver.reserve_in(R.WATER,2) and not receiver.reserve_in(R.WATER,1),"Ten water permits two full inbound cargoes, not three")
	receiver.release_in(R.WATER,2)
	var reserve_ids: Array=[]
	for worker in world.resident_runtimes.slice(0,2):
		var ref=world.water_sources.candidates()[0]
		reserve_ids.append(world.logistics.claim_transport(worker.data.id,ref,place,R.WATER,func():return true,false,Callable(),false,0.0,null,&"",false,0,receiver))
	check(reserve_ids.all(func(delivery):return delivery!=null) and receiver.get_reserved_in(R.WATER)==2,"Multiple well users own independent inbound promises")
	for delivery in reserve_ids:world.logistics.cancel_transport(delivery,"cancel concurrent")
	check(receiver.get_reserved_in(R.WATER)==0,"All cancelled users release own inbound")
	world.free()
func interruptions() -> void:
	for stage in [0,5,10]:
		var world=F.create(self);var place=kitchen(world);var well=F.building(world,T.WELL,Vector3(-12,0,16));var actor=world.resident_runtimes[0]
		world.player_control.assign_workplace(actor.data.id,place.id,P.COOK)
		check(world._request_work(actor),"Water request before interruption")
		var job=world.logistics.get_job(actor.data.id)
		if stage>0:
			arrive_without_time(actor);world.game_time.debug_skip_minutes(stage)
		world.logistics.cancel_transport(job,"interruption");world.logistics.cancel_transport(job,"repeat")
		check(actor.data.inventory.amount==0 and place.consumable_stocks[&"water"].amount==0 and place.consumable_stocks[&"water"].incoming_units()==0,"Cancelled collection/delivery cannot credit water")
		var dropped: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.WATER).reduce(func(total,drop):return total+drop.amount,0)
		check(dropped==(1 if stage==10 else 0),"Only completed collection may leave one safe dropped cargo")
		check(world.water_sources.exists(StringName("well:"+String(well.id))),"Well never depletes")
		world.free()

func concurrent_and_removal() -> void:
	var world=F.create(self);var place=kitchen(world);var well=F.building(world,T.WELL,Vector3(-12,0,16))
	var a=world.resident_runtimes[0];var b=world.resident_runtimes[1]
	var ref=world.water_sources.candidates()[0]
	var jobs: Array=[]
	for actor in [a,b]:
		var job=world.logistics.claim_transport(actor.data.id,ref,place,R.WATER,func():return true)
		check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Two users can commit finite hauls from infinite well")
		jobs.append(job)
	for step in 18000:
		a.view._physics_process(.05);b.view._physics_process(.05)
		if b.view._waiting and not a.intents.current_intent.resource_handling.is_empty():break
	check(b.view._waiting and a.intents.current_intent.resource_handling==&"loading" and b.intents.current_intent.resource_handling.is_empty(),"Only one user occupies actual well courier; second waits event-driven")
	world.game_time.debug_skip_minutes(10)
	for step in 18000:
		a.view._physics_process(.05)
		if not world.building_uses.occupied_by(well.id,a.data.id,1):break
	await process_frame # Slot notification resumes waiting arrival through its normal deferred callback.
	arrive_without_time(b)
	check(a.data.inventory.amount==1 and b.data.inventory.amount==0,"First pickup releases source slot before second collection")
	world.game_time.debug_skip_minutes(10)
	for step in 18000:
		for actor in [a,b]:
			if world.logistics.get_job(actor.data.id)!=null:Step.move_3d(actor,.05)
		if a.view._waiting or b.view._waiting:await process_frame
		if world.logistics.jobs.is_empty():break
	check(jobs.all(func(job):return job.state==job.State.COMPLETED) and place.consumable_stocks[&"water"].amount==10 and world.water_sources.exists(ref.id),"Both physical deliveries complete without exhausting well or leaking slot")
	await observe(world,"07-concurrent-well")
	world.free()
	for remove_source in [true,false]:
		var removal_world=F.create(self);var target=kitchen(removal_world);var source=F.building(removal_world,T.WELL,Vector3(-12,0,16));var carrier=removal_world.resident_runtimes[0]
		removal_world.player_control.assign_workplace(carrier.data.id,target.id,P.COOK)
		check(removal_world._request_work(carrier),"Water before removal accepted")
		var delivery=removal_world.logistics.get_job(carrier.data.id)
		arrive_without_time(carrier)
		removal_world.game_time.debug_skip_minutes(10 if not remove_source else 5)
		removal_world.logistics.remove_building(source.id if remove_source else target.id,false)
		check(not delivery.is_active() and carrier.data.inventory.amount==0 and target.consumable_stocks[&"water"].incoming_units()==0 and target.consumable_stocks[&"water"].amount==0,"Source removal during collection / receiver removal while carrying cleans up immediately")
		removal_world.free()
	var callback_world=F.create(self);var receiver_building=kitchen(callback_world);F.building(callback_world,T.WELL,Vector3(-12,0,16));var user=callback_world.resident_runtimes[0]
	callback_world.player_control.assign_workplace(user.data.id,receiver_building.id,P.COOK)
	check(callback_world._request_work(user),"Callback scenario water claim")
	var active=callback_world.logistics.get_job(user.data.id)
	var stock: RefCounted=receiver_building.consumable_stocks[&"water"]
	stock.changed.connect(func():
		if stock.amount>0:
			callback_world.logistics.cancel_transport(active,"nested delivery")
			check(not callback_world.logistics.deliver_inbound(active),"Nested callback cannot deliver twice"))
	for step in 18000:
		if callback_world.logistics.get_job(user.data.id)==null:break
		Step.move_3d(user,.05)
	check(stock.amount==5 and stock.incoming_units()==0 and user.data.inventory.amount==0,"Nested completion preserves exact conversion")
	stock.reserve(&"consume",5);stock.commit_payment(&"consume") # Back to zero; directly exercising C1 numeric admission next.
	var receiver: RefCounted=receiver_building.consumable_receivers[&"water"]
	receiver.reserve_in(R.WATER,3);receiver.add_reserved(R.WATER,3)
	check(stock.amount==15 and receiver.reserve_in(R.WATER,1) and receiver.add_reserved(R.WATER,1) and stock.amount==20,"Fifteen admits one whole five-unit cargo")
	stock.reserve(&"consume",2);stock.commit_payment(&"consume")
	check(stock.amount==18 and not receiver.reserve_in(R.WATER,1),"Eighteen rejects full cargo without discarding any unit")
	callback_world.free()

func stock_contracts() -> void:
	for missing in [&"flour",&"fuel",&"water"]:
		var place=B.new(&"kitchen",D.for_type(T.FOOD))
		place.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF)
		if missing!=&"flour":place.resources.add(R.FLOUR,1)
		for pair in [[&"fuel",R.LOG],[&"water",R.WATER]]:
			if missing==pair[0]:continue
			place.consumable_receivers[pair[0]].reserve_in(pair[1],1)
			place.consumable_receivers[pair[0]].add_reserved(pair[1],1)
		var before: Array=[place.resources.get_amount(R.FLOUR),place.consumable_stocks[&"fuel"].amount,place.consumable_stocks[&"water"].amount]
		check(not place.can_start_production(&"bake_bread") and place.claim_production_work("cook")==null,"Missing each mandatory component blocks bread preparation")
		check(before==[place.resources.get_amount(R.FLOUR),place.consumable_stocks[&"fuel"].amount,place.consumable_stocks[&"water"].amount] and place.resources.get_reserved_out(R.FLOUR)==0 and place.resources.get_reserved_in(R.BREAD)==0,"No partial payment or leaked claims on bread failure")
