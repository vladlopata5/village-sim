extends "res://tests/test_textile_production.gd"
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
var observer: Callable
func observe(world: Node, stage: String) -> void:
	if observer.is_valid():await observer.call(world,stage)
func run() -> void:
	batches_and_orders()
	await physical_clay_chain()
	await cancellation_and_receivers()
	print("Pottery: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func batches_and_orders() -> void:
	var place=B.new(&"pottery",D.for_type(T.POTTERY_WORKSHOP))
	var recipe=place.definition.production_recipe;var fuel=place.consumable_stocks[&"fuel"];var receiver=place.consumable_receivers[&"fuel"]
	check(place.definition.worker_profession==P.POTTER and place.definition.worker_capacity==1 and place.definition.porter_capacity==1,"One potter and one optional porter")
	check(place.resources.get_capacity(R.CLAY)==10 and place.resources.get_capacity(R.BRICK)==10 and fuel.capacity==20 and fuel.conversions=={R.LOG:5},"Ordinary physical buffers and shared C1 conversion")
	check(recipe.inputs=={R.CLAY:1} and recipe.outputs=={R.BRICK:1} and recipe.consumables=={&"fuel":1} and recipe.work_required==30,"Exact approved brick recipe")
	check(place.next_upgrade()==null and D.for_type(T.CLAY_HUT).upgrades.is_empty(),"No fictional CL1 upgrades")
	for type in T.values():
		check(not D.for_type(type).construction_requirements.has(R.BRICK),"Brick does not change construction costs")
	place.resources.add(R.CLAY,3)
	check(place.claim_production_work("potter")==null and place.resources.get_amount(R.CLAY)==3,"No fuel prevents both preparation and payment")
	check(receiver.reserve_in(R.LOG,1) and receiver.add_reserved(R.LOG,1) and not receiver.add_reserved(R.LOG,1) and fuel.amount==5,"One log converts once to five numerical fuel")
	place.set_recipe_mode(recipe.id,B.ProductionMode.OFF)
	check(place.claim_production_work("potter")==null,"OFF prevents new batch")
	place.set_recipe_mode(recipe.id,B.ProductionMode.ORDER,1)
	var batch=place.claim_production_work("potter");place.accept_production_batch(batch)
	check(batch!=null and fuel.amount==5 and fuel.reserved_units()==1 and place.resources.get_amount(R.CLAY)==3,"Preparation reserves both costs without paying")
	var ledger: Array=[]
	fuel.changed.connect(func():ledger.append([fuel.amount,place.resources.get_amount(R.CLAY)]),CONNECT_ONE_SHOT)
	check(batch.begin("potter") and ledger==[[4,2]] and not batch.begin("potter"),"Observers see atomic CLAY/FUEL payment once")
	batch.advance("potter",11);batch.release_worker("potter")
	check(batch.can_resume() and batch.progress==11 and place.select_production_work().kind==&"RESUME","Paid pause retains priority and progress")
	check(batch.claim("replacement") and batch.begin("replacement") and fuel.amount==4 and place.resources.get_amount(R.CLAY)==2,"Resume costs no extra material/fuel")
	batch.advance("replacement",18);check(not batch.finish("replacement") and place.resources.get_amount(R.BRICK)==0,"29 minutes cannot emit brick")
	batch.advance("replacement",1);check(batch.finish("replacement") and not batch.finish("replacement"),"Exactly thirty work minutes finish once")
	place.retire_production_batch(batch)
	check(place.resources.get_amount(R.BRICK)==1 and place.get_order_remaining(recipe.id)==0 and place.claim_production_work("potter")==null,"ORDER counts actual brick and stops")
	place.set_recipe_mode(recipe.id,B.ProductionMode.MAINTAIN,1)
	check(not place.can_start_production(recipe.id),"MAINTAIN sees local output stock")
	place.resources.try_take(R.BRICK,1)
	check(place.can_start_production(recipe.id),"MAINTAIN detects physical export")
	place.set_recipe_mode(recipe.id,B.ProductionMode.UNLIMITED)
	place.resources.add(R.BRICK,10)
	check(place.claim_production_work("potter")==null and fuel.amount==4,"Full output blocks payment")
	place.resources.try_take(R.BRICK,1)
	batch=place.claim_production_work("potter")
	check(batch!=null,"One free output admits one brick")
	batch.cancel();batch.cancel();place.retire_production_batch(batch)
	check(fuel.amount==4 and fuel.reserved_units()==0 and place.resources.get_reserved_out(R.CLAY)==0 and place.resources.get_reserved_in(R.BRICK)==0,"Repeated unpaid cancel frees all own promises")
	batch=place.claim_production_work("nested")
	check(batch!=null,"One remaining output place prepares nested cancellation")
	fuel.changed.connect(func():batch.cancel(),CONNECT_ONE_SHOT)
	check(not batch.begin("nested") and batch.is_terminal() and fuel.amount==3 and place.resources.get_amount(R.CLAY)==1,"Reentrant cancellation sees both costs already paid, with no partial refund")
	place.retire_production_batch(batch)
	check(fuel.reserved_units()==0 and place.resources.get_reserved_in(R.BRICK)==0 and place.resources.get_reserved_out(R.CLAY)==0,"Nested cancellation clears all own obligations")
func physical_clay_chain() -> void:
	var world=F.create(self)
	var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16))
	var pottery=F.building(world,T.POTTERY_WORKSHOP,Vector3(5,0,16))
	var digger=world.resident_runtimes[0];var potter=world.resident_runtimes[1];var porter=world.resident_runtimes[2]
	world.player_control.assign_workplace(digger.data.id,hut.id)
	world.player_control.assign_workplace(potter.data.id,pottery.id)
	world.player_control.assign_workplace(porter.data.id,pottery.id,P.PORTER)
	var result: Dictionary=world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16));check(result.ok,"Physical chain starts at a normal clay deposit")
	if not result.ok:world.free();return
	var deposit=result.objects[0];var miner=digger.get_node("Miner")
	await observe(world,"01-clay-deposit")
	check(miner.has_work() and miner.request_work(),"Normal digger assignment starts extraction")
	for i in 12000:
		digger.view._physics_process(.05)
		if miner.mining:break
	check(miner.mining,"Digger physically arrives before work")
	await observe(world,"02-clay-mining")
	world.game_time.debug_skip_minutes(60)
	check(deposit.stock==9 and digger.data.inventory.amount==0,"One mine cycle creates real ground clay, not phantom inventory")
	var job=await haul(world,digger)
	check(job!=null and job.resource_type==R.CLAY and hut.resources.get_amount(R.CLAY)==1,"Digger physically collects and unloads into hut")
	await observe(world,"03-clay-hut")
	world.warehouse_data.resources.add(R.LOG,4)
	job=await haul(world,potter)
	check(job!=null and job.resource_type==R.LOG and pottery.consumable_stocks[&"fuel"].amount==5,"Potter zero-fuel self-supply delivers actual log")
	check(not world.logistics.deliver_inbound(job) and pottery.consumable_stocks[&"fuel"].amount==5,"Repeated delivery callback cannot convert another five fuel")
	await observe(world,"04-pottery-fuel")
	job=await haul(world,potter)
	check(job!=null and job.resource_type==R.CLAY and job.source_location_id==hut.id and pottery.resources.get_amount(R.CLAY)==1,"Physical hut-to-pottery clay supply")
	await observe(world,"05-clay-delivery")
	check(potter.self_logistics.task().kind==&"PRODUCTION","Nonzero fuel never replaces ready production with self top-up")
	if not await start_recipe(world,potter):world.free();return
	check(pottery.consumable_stocks[&"fuel"].amount==4 and pottery.resources.get_amount(R.CLAY)==0,"Arrival at WORKER pays clay and fuel")
	world.game_time.debug_skip_minutes(11)
	var paid=potter.recipe_work.batch
	potter.commands.move_to(Coord.to_sim(Vector3(0,0,24)))
	check(paid.can_resume() and paid.progress==11,"Player interruption keeps paid brick batch")
	potter.commands.cancel_current();potter.intents.abort_current(potter.intents.current_intent)
	if not await start_recipe(world,potter):world.free();return
	check(potter.recipe_work.batch==paid and pottery.consumable_stocks[&"fuel"].amount==4,"Physical return resumes same paid batch")
	world.game_time.debug_skip_minutes(19)
	check(pottery.resources.get_amount(R.BRICK)==1 and pottery.production_batches.is_empty(),"One actual brick after thirty actual work minutes")
	await observe(world,"06-brick-output")
	check(world.warehouse_data.resources.set_category_quota(C.PLANK,30) and world.warehouse_data.resources.set_category_quota(C.BRICK,10) and world.warehouse_data.resources.set_category_quota(C.CLAY,10),"Independent new warehouse quotas use existing shared capacity")
	pottery.set_recipe_mode(&"fire_brick",B.ProductionMode.OFF)
	job=await haul(world,potter)
	check(job!=null and job.resource_type==R.BRICK and world.warehouse_data.resources.get_amount(R.BRICK)==1,"Real output exported to warehouse")
	await observe(world,"07-brick-export")
	job=await haul(world,porter)
	check(job!=null and job.resource_type==R.LOG and pottery.consumable_stocks[&"fuel"].amount==9,"Optional porter prefills fuel with normal logistics")
	for place in [hut,pottery,world.warehouse_data]:
		for resource in [R.CLAY,R.BRICK,R.LOG]:check(place.resources.get_reserved_in(resource)==0 and place.resources.get_reserved_out(resource)==0,"Completed physical chain has no inbound/outbound leaks")
	check(pottery.consumable_stocks[&"fuel"].incoming_units()==0 and world.logistics.jobs.is_empty(),"No lost haul or consumable promise")
	world.free();await process_frame
func cancellation_and_receivers() -> void:
	for picked in [false,true]:
		var world=F.create(self);var pottery=F.building(world,T.POTTERY_WORKSHOP,Vector3(5,0,16))
		var actor=world.resident_runtimes[0];world.player_control.assign_workplace(actor.data.id,pottery.id,P.PORTER)
		world.warehouse_data.resources.add(R.LOG,4)
		check(world._request_work(actor),"Ordinary porter accepts fuel before cancel")
		var job=world.logistics.get_job(actor.data.id)
		if picked:
			for i in 18000:
				Step.move_3d(actor,.05)
				if actor.data.inventory.amount==1:break
			check(actor.data.inventory.amount==1,"Real pickup occurs before cancel")
		world.logistics.cancel_transport(job,"CL1 cancellation");world.logistics.cancel_transport(job,"repeat")
		check(actor.data.inventory.amount==0 and pottery.consumable_stocks[&"fuel"].incoming_units()==0 and pottery.consumable_stocks[&"fuel"].amount==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Cancel before/after pickup clears exact own obligations")
		var dropped: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.LOG).reduce(func(n,drop):return n+drop.amount,0)
		check(dropped==(1 if picked else 0),"Repeated cancel cannot duplicate carried log")
		world.free();await process_frame
	for remove_source in [true,false]:
		var world=F.create(self);var pottery=F.building(world,T.POTTERY_WORKSHOP,Vector3(5,0,16))
		var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16));hut.resources.add(R.CLAY,2)
		var source=Source.new(Source.Kind.CONTAINER,hut.id)
		var jobs: Array=[]
		for i in 2:
			var actor=world.resident_runtimes[i]
			jobs.append(world.logistics.claim_transport(actor.data.id,source,pottery,R.CLAY,func():return true))
		check(jobs[0]!=null and jobs[1]!=null and hut.resources.get_reserved_out(R.CLAY)==2 and pottery.resources.get_reserved_in(R.CLAY)==2,"Independent external suppliers reserve two real clay units")
		world.logistics.cancel_transport(jobs[0],"first")
		check(pottery.resources.get_reserved_in(R.CLAY)==1 and world.logistics.inbound_valid(jobs[1]),"One cancellation preserves foreign supplier promise")
		world.logistics.remove_building(hut.id if remove_source else pottery.id,false)
		check(hut.resources.get_reserved_out(R.CLAY)==0 and pottery.resources.get_reserved_in(R.CLAY)==0,"Removed source or destination promptly releases remaining claim")
		world.free();await process_frame
