extends "res://tests/test_textile_production.gd"
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
var observer: Callable
func observe(world: Node,stage: String) -> void:
	if observer.is_valid():await observer.call(world,stage)
func run() -> void:
	batches_and_orders()
	await physical_stone_chain()
	await cancellation_and_receivers()
	await stack_and_external()
	print("Stone brick production: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func batches_and_orders() -> void:
	var place=B.new(&"stoneworks",D.for_type(T.STONEMASON_WORKSHOP));var recipe=place.definition.production_recipe
	check(place.consumable_stocks.is_empty() and place.consumable_receivers.is_empty() and recipe.consumables.is_empty(),"No fake fuel/water stocks or receivers")
	check(recipe.inputs=={R.STONE:1} and recipe.outputs=={R.STONE_BRICK:1} and recipe.work_required==30,"Exact no-fuel physical recipe")
	check(place.resources.get_capacity(R.STONE)==10 and place.resources.get_capacity(R.STONE_BRICK)==10 and not place.resources.add(R.BRICK,1),"Independent10/10 buffers and no stone-brick substitution")
	check(place.claim_production_work("one")==null,"No input prevents production")
	place.resources.add(R.STONE,3)
	place.set_recipe_mode(recipe.id,B.ProductionMode.OFF)
	check(place.claim_production_work("one")==null,"OFF prevents preparation")
	place.set_recipe_mode(recipe.id,B.ProductionMode.ORDER,1)
	var batch=place.claim_production_work("one");place.accept_production_batch(batch)
	check(batch!=null and place.resources.get_amount(R.STONE)==3 and place.resources.get_reserved_out(R.STONE)==1 and place.resources.get_reserved_in(R.STONE_BRICK)==1,"Preparation reserves exact costs/output without payment")
	check(batch.begin("one") and not batch.begin("one") and place.resources.get_amount(R.STONE)==2,"Actual begin pays one stone once")
	batch.advance("one",11);batch.release_worker("one")
	place.set_recipe_mode(recipe.id,B.ProductionMode.OFF)
	check(batch.can_resume() and place.select_production_work().kind==&"RESUME" and batch.progress==11,"Paid11/30 keeps RESUME priority even OFF")
	check(place.claim_production_work("replacement")==batch and batch.begin("replacement") and place.resources.get_amount(R.STONE)==2,"Replacement resumes without repayment")
	batch.advance("replacement",18)
	check(not batch.finish("replacement") and place.resources.get_amount(R.STONE_BRICK)==0,"29 minutes cannot publish output")
	batch.advance("replacement",1)
	check(batch.finish("replacement") and not batch.finish("replacement") and place.resources.get_amount(R.STONE_BRICK)==1,"Exactly30 work minutes publish once")
	place.retire_production_batch(batch)
	check(place.get_order_remaining(recipe.id)==0 and place.resources.get_reserved_in(R.STONE_BRICK)==0 and place.resources.get_reserved_out(R.STONE)==0,"Completion clears promises and ORDER count")
	place.set_recipe_mode(recipe.id,B.ProductionMode.MAINTAIN,1)
	check(not place.can_start_production(recipe.id),"MAINTAIN counts actual output")
	place.resources.try_take(R.STONE_BRICK,1)
	check(place.can_start_production(recipe.id),"Export makes MAINTAIN eligible")
	place.set_recipe_mode(recipe.id,B.ProductionMode.UNLIMITED)
	place.resources.add(R.STONE_BRICK,10)
	check(place.claim_production_work("one")==null and place.resources.get_amount(R.STONE)==2,"Full output blocks preparation/payment")
	place.resources.try_take(R.STONE_BRICK,1);batch=place.claim_production_work("one")
	batch.cancel();batch.cancel();place.retire_production_batch(batch)
	check(place.resources.get_reserved_out(R.STONE)==0 and place.resources.get_reserved_in(R.STONE_BRICK)==0 and place.resources.get_amount(R.STONE)==2,"Repeated unpaid cancellation releases exact promises")
	batch=place.claim_production_work("nested");place.accept_production_batch(batch)
	place.resources.changed.connect(func(_type,_amount):batch.cancel(),CONNECT_ONE_SHOT)
	check(not batch.begin("nested") and batch.is_terminal() and place.resources.get_amount(R.STONE)==1,"Reentrant payment cancellation cannot refund/duplicate stone")
	place.retire_production_batch(batch)
	check(place.resources.get_reserved_in(R.STONE_BRICK)==0 and place.resources.get_reserved_out(R.STONE)==0,"Nested cancellation leaves no promises")
func physical_stone_chain() -> void:
	var world=F.create(self)
	var hut=F.building(world,T.QUARRY,Vector3(-10,0,16))
	var workshop=F.building(world,T.STONEMASON_WORKSHOP,Vector3(5,0,16))
	var digger=world.resident_runtimes[0];var mason=world.resident_runtimes[1];var porter=world.resident_runtimes[2]
	world.player_control.assign_workplace(digger.data.id,hut.id)
	world.player_control.assign_workplace(mason.data.id,workshop.id)
	world.player_control.assign_workplace(porter.data.id,workshop.id,P.PORTER)
	var result: Dictionary={"ok":true,"objects":[preload("res://scripts/rock_data.gd").new(&"st1_stone",Coord.to_sim(Vector3(-17,0,16)))]}
	world._register_rock(result.objects[0])
	var deposit=result.objects[0];var miner=digger.get_node("Miner")
	await observe(world,"01-stone-deposit")
	check(miner.has_work() and miner.request_work(),"Normal digger assignment starts extraction")
	for i in 12000:
		digger.view._physics_process(.05)
		if miner.mining:break
	check(miner.mining,"Digger physically arrives before work")
	await observe(world,"02-stone-mining")
	world.game_time.debug_skip_minutes(60)
	check(deposit.stock==9 and digger.data.inventory.amount==0,"One mine cycle creates real ground stone, not phantom inventory")
	var job=await haul(world,digger)
	check(job!=null and job.resource_type==R.STONE and hut.resources.get_amount(R.STONE)==1,"Digger physically collects and unloads into hut")
	await observe(world,"03-stone-hut")
	job=await haul(world,mason)
	check(job!=null and job.resource_type==R.STONE and job.source_location_id==hut.id and workshop.resources.get_amount(R.STONE)==1,"Physical hut-to-workshop stone supply")
	await observe(world,"05-stone-delivery")
	check(mason.self_logistics.task().kind==&"PRODUCTION","Ordinary no-consumable production is ready")
	if not await start_recipe(world,mason):world.free();return
	check(workshop.resources.get_amount(R.STONE)==0,"Arrival at WORKER pays exactly one stone")
	world.game_time.debug_skip_minutes(11)
	var paid=mason.recipe_work.batch
	mason.commands.move_to(Coord.to_sim(Vector3(0,0,24)))
	check(paid.can_resume() and paid.progress==11,"Player interruption keeps paid brick batch")
	mason.commands.cancel_current();mason.intents.abort_current(mason.intents.current_intent)
	check(world.player_control.clear_work_assignment(mason.data.id),"Original worker releases assignment after paid pause")
	mason=world.resident_runtimes[3]
	check(world.player_control.assign_workplace(mason.data.id,workshop.id,P.STONEMASON),"Replacement mason uses ordinary assignment")
	if not await start_recipe(world,mason):world.free();return
	check(mason.recipe_work.batch==paid,"Physical return resumes same paid batch")
	world.game_time.debug_skip_minutes(19)
	check(workshop.resources.get_amount(R.STONE_BRICK)==1 and workshop.production_batches.is_empty(),"One actual brick after thirty actual work minutes")
	await observe(world,"06-brick-output")
	check(world.warehouse_data.resources.set_category_quota(C.PLANK,30) and world.warehouse_data.resources.set_category_quota(C.STONE_BRICK,10),"Independent new warehouse quotas use existing shared capacity")
	workshop.set_recipe_mode(&"cut_stone_brick",B.ProductionMode.OFF)
	job=await haul(world,mason)
	check(job!=null and job.resource_type==R.STONE_BRICK and world.warehouse_data.resources.get_amount(R.STONE_BRICK)==1,"Real output exported to warehouse")
	await observe(world,"07-brick-export")
	hut.resources.add(R.STONE,1)
	job=await haul(world,porter)
	check(job!=null and job.resource_type==R.STONE and workshop.resources.get_amount(R.STONE)==1,"Assigned porter physically supplies one stone")
	for place in [hut,workshop,world.warehouse_data]:
		for resource in [R.STONE,R.STONE_BRICK,R.LOG]:check(place.resources.get_reserved_in(resource)==0 and place.resources.get_reserved_out(resource)==0,"Completed physical chain has no inbound/outbound leaks")
	check(world.logistics.jobs.is_empty(),"No lost haul or consumable promise")
	world.free();await process_frame
func cancellation_and_receivers() -> void:
	for picked in [false,true]:
		var world=F.create(self);var workshop=F.building(world,T.STONEMASON_WORKSHOP,Vector3(5,0,16))
		var actor=world.resident_runtimes[0];world.player_control.assign_workplace(actor.data.id,workshop.id,P.PORTER)
		world.warehouse_data.resources.add(R.STONE,4)
		check(world._request_work(actor),"Ordinary porter accepts stone before cancel")
		var job=world.logistics.get_job(actor.data.id)
		if picked:
			for i in 18000:
				Step.move_3d(actor,.05)
				if actor.data.inventory.amount==1:break
			check(actor.data.inventory.amount==1,"Real pickup occurs before cancel")
		world.logistics.cancel_transport(job,"ST1 cancellation");world.logistics.cancel_transport(job,"repeat")
		check(actor.data.inventory.amount==0 and workshop.resources.get_reserved_in(R.STONE)==0 and workshop.resources.get_amount(R.STONE)==0 and world.warehouse_data.resources.get_reserved_out(R.STONE)==0,"Cancel before/after pickup clears exact own obligations")
		var dropped: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.STONE).reduce(func(n,drop):return n+drop.amount,0)
		check(dropped==(1 if picked else 0),"Repeated cancel cannot duplicate carried stone")
		world.free();await process_frame
	for remove_source in [true,false]:
		var world=F.create(self);var workshop=F.building(world,T.STONEMASON_WORKSHOP,Vector3(5,0,16))
		var hut=F.building(world,T.QUARRY,Vector3(-10,0,16));hut.resources.add(R.STONE,2)
		var source=Source.new(Source.Kind.CONTAINER,hut.id)
		var jobs: Array=[]
		for i in 2:
			var actor=world.resident_runtimes[i]
			jobs.append(world.logistics.claim_transport(actor.data.id,source,workshop,R.STONE,func():return true))
		check(jobs[0]!=null and jobs[1]!=null and hut.resources.get_reserved_out(R.STONE)==2 and workshop.resources.get_reserved_in(R.STONE)==2,"Independent external suppliers reserve two real stone units")
		world.logistics.cancel_transport(jobs[0],"first")
		check(workshop.resources.get_reserved_in(R.STONE)==1 and world.logistics.inbound_valid(jobs[1]),"One cancellation preserves foreign supplier promise")
		world.logistics.remove_building(hut.id if remove_source else workshop.id,false)
		check(hut.resources.get_reserved_out(R.STONE)==0 and workshop.resources.get_reserved_in(R.STONE)==0,"Removed source or destination promptly releases remaining claim")
		world.free();await process_frame

func stack_and_external() -> void:
	var world=F.create(self);var sources=world.logistics.sources
	var result: Dictionary=world.ground_resources.place_near(R.STONE_BRICK,3,world.ground_resources.cell_from_position(Coord.to_sim(Vector3(0,0,20))),world.ground_resources.PlacementMode.NATURAL,func(_cell):return true)
	check(result.placed==3,"Stone bricks use canonical cell placement")
	var drop=world.ground_resources.drops.filter(func(item):return item.resource_type==R.STONE_BRICK)[0]
	var id: StringName=drop.id;var ref=Source.new(Source.Kind.GROUND,id)
	check(drop.capacity==10 and sources.reserve(ref,R.STONE_BRICK,&"first") and sources.reserve(ref,R.STONE_BRICK,&"second"),"Two owners reserve separate units of one ten-unit stack")
	var inventory=preload("res://scripts/resident_inventory.gd").new()
	check(inventory.receive(R.STONE_BRICK,1,sources.pickup.bind(ref,R.STONE_BRICK,&"first")) and drop.amount==2 and drop.id==id and drop.reserved_amount(&"second")==1,"Partial physical pickup preserves ID and foreign claim")
	sources.release(ref,R.STONE_BRICK,&"second")
	var warehouse=world.warehouse_data
	check(warehouse.resources.set_category_quota(C.PLANK,30) and warehouse.resources.set_category_quota(C.STONE_BRICK,10),"New standalone warehouse quota is editable")
	check(warehouse.resources.reserve_in(R.STONE_BRICK,1) and inventory.deliver(R.STONE_BRICK,1,warehouse.resources.add_reserved.bind(R.STONE_BRICK,1)),"Inventory delivers concrete stone brick against inbound promise")
	check(warehouse.resources.get_amount(R.STONE_BRICK)==1 and warehouse.resources.get_amount(R.BRICK)==0 and D.for_type(T.STORAGE).allows_external_export(R.STONE_BRICK) and D.for_type(T.TOWN_CENTER).allows_external_import(R.STONE_BRICK),"Storage import/export keeps clay brick distinct")
	var importer=world.resident_runtimes[3]
	check(world.player_control.assign_workplace(importer.data.id,warehouse.id,P.PORTER),"External warehouse porter uses normal assignment")
	var imported=await haul(world,importer)
	check(imported!=null and imported.resource_type==R.STONE_BRICK and warehouse.resources.get_amount(R.STONE_BRICK)==2,"External porter imports actual ground stone brick")
	var workshop=F.building(world,T.STONEMASON_WORKSHOP,Vector3(5,0,16))
	workshop.resources.add(R.STONE,9);warehouse.resources.add(R.STONE,2)
	world.game_time.debug_skip_minutes(30)
	check(workshop.resources.get_amount(R.STONE_BRICK)==0 and workshop.production_batches.is_empty(),"Building with input never produces without worker")
	var source=Source.new(Source.Kind.CONTAINER,warehouse.id)
	var job=world.logistics.claim_transport(world.residents[0].id,source,workshop,R.STONE,func():return true)
	var excess=world.logistics.claim_transport(world.residents[1].id,source,workshop,R.STONE,func():return true)
	check(job!=null and excess==null and workshop.resources.get_reserved_in(R.STONE)==1 and warehouse.resources.get_reserved_out(R.STONE)==1,"Concurrent suppliers cannot overbook last input place")
	world.logistics.cancel_transport(job,"ST1 capacity control")
	check(workshop.resources.get_reserved_in(R.STONE)==0 and warehouse.resources.get_reserved_out(R.STONE)==0,"Last-place cancellation releases both obligations")
	world.free();await process_frame
