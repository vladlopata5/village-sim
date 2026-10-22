extends "res://tests/test_textile_production.gd"
const Source=preload("res://scripts/resource_source_ref.gd")
var observer: Callable
func kitchen_fixture(world: Node) -> RefCounted:
	var place=F.building(world,T.FOOD,Vector3(16,0,16))
	place.definition.logistics_flow[R.FOOD]["import"]=false # Isolate fuel/ingredients from catering FOOD demand.
	return place
func observe(world: Node, stage: String) -> void:
	if observer.is_valid():await observer.call(world,stage)
func run() -> void:
	await chain()
	cancellations()
	efficiency()
	await receiver_lifecycle()
	print("Consumable logistics: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func chain() -> void:
	var world=F.create(self)
	var kitchen=kitchen_fixture(world)
	kitchen.consumable_receivers[&"water"].reserve_in(R.WATER,1)
	kitchen.consumable_receivers[&"water"].add_reserved(R.WATER,1) # C1 isolates fuel; WAT1 separately exercises physical water.
	var mill=F.building(world,T.WINDMILL,Vector3(-10,0,16))
	var cook=world.resident_runtimes[0]
	world.player_control.assign_workplace(cook.data.id,kitchen.id,P.COOK)
	kitchen.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF)
	world.warehouse_data.resources.add(R.LOG,4);mill.resources.add(R.FLOUR,2)
	var stock: RefCounted=kitchen.consumable_stocks[&"fuel"]
	var cursor: Dictionary=kitchen._recipe_cursors.duplicate()
	var offer=cook.self_logistics.task()
	check(offer.kind==&"SUPPLY" and offer.resource==R.LOG and offer.receiver==kitchen.consumable_receivers[&"fuel"] and kitchen._recipe_cursors==cursor,"Zero-fuel SUPPLY uses explicit receiver, probes do not rotate")
	var job=await haul(world,cook)
	check(job!=null and job.receiver==kitchen.consumable_receivers[&"fuel"] and stock.amount==5 and kitchen.resources.get_amount(R.LOG)==0,"Physical LOG unload becomes five fuel, no log inventory")
	await observe(world,"01-fuel-delivered")
	job=await haul(world,cook)
	check(job.resource_type==R.FLOUR and job.receiver==kitchen.resources and kitchen.resources.get_amount(R.FLOUR)==1,"Flour from real mill uses ordinary receiver")
	check(cook.self_logistics.task().kind==&"PRODUCTION","Nonzero fuel never creates a cook top-up")
	if not await start_recipe(world,cook):world.free();return
	check(stock.amount==4 and kitchen.resources.get_amount(R.FLOUR)==0,"Physical worker arrival atomically spends flour and fuel")
	world.game_time.debug_skip_minutes(29)
	check(kitchen.resources.get_amount(R.BREAD)==0,"No bread before thirty work minutes")
	world.game_time.debug_skip_minutes(1)
	check(kitchen.resources.get_amount(R.BREAD)==2 and stock.amount==4,"Thirty minutes produce two bread once")
	await observe(world,"02-bread")
	kitchen.set_recipe_mode(&"bake_bread",B.ProductionMode.OFF)
	kitchen.set_recipe_mode(&"fried_mushroom",B.ProductionMode.ORDER,2)
	var gatherer_hut=F.building(world,T.GATHERER_HUT,Vector3(-10,0,-18))
	gatherer_hut.resources.add(R.MUSHROOM,1)
	job=await haul(world,cook)
	check(job.resource_type==R.MUSHROOM,"ORDER kit supplies mushroom")
	if not await start_recipe(world,cook):world.free();return
	world.game_time.debug_skip_minutes(30)
	check(kitchen.resources.get_amount(R.FRIED_MUSHROOM)==2 and stock.amount==3,"Second recipe pays same generic stock and outputs two")
	await observe(world,"03-mushrooms")
	var porter=world.resident_runtimes[1]
	world.player_control.assign_workplace(porter.data.id,kitchen.id,P.PORTER)
	job=await haul(world,porter)
	check(job.resource_type==R.LOG and stock.amount==8,"Own porter prefills nonempty stock")
	await observe(world,"04-porter-prefill")
	# Existing forestry worker export can use the same receiver with nonzero fuel.
	var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(3,0,-18))
	var exporter=world.resident_runtimes[2]
	world.player_control.assign_workplace(exporter.data.id,hut.id,P.LUMBERJACK)
	hut.resources.add(R.LOG,1)
	job=world.logistics.claim_worker_export(exporter.data.id,hut,kitchen,R.LOG)
	check(job!=null and world.logistics.start_claimed_job(job,exporter.data.id),"External exporting worker claims fuel delivery")
	for step in 18000:
		if world.logistics.get_job(exporter.data.id)==null:break
		Step.move_3d(exporter,.05)
	check(job.state==job.State.COMPLETED and stock.amount==13 and hut.resources.get_amount(R.LOG)==0,"External physical export converts once")
	await observe(world,"05-external-prefill")
	world.resident_selection.select_building(kitchen)
	await process_frame
	var card=world.building_card_view()
	check(card.consumable_rows.has(&"fuel") and card.consumable_rows[&"fuel"].label.text.contains("13 / 20") and card.recipe_views.size()==2,"Local stock bar and both recipes in real card")
	await observe(world,"06-kitchen-card")
	for actor in world.resident_runtimes:check(actor.data.inventory.amount==0,"All physical transfers settle inventory")
	check(stock.incoming_units()==0 and stock.reserved_units()==0 and world.logistics.jobs.is_empty(),"No orphan receiver promises or batches")
	world.free()
func cancellations() -> void:
	for picked in [false,true]:
		var world=F.create(self)
		var kitchen=kitchen_fixture(world)
		var actor=world.resident_runtimes[0]
		world.player_control.assign_workplace(actor.data.id,kitchen.id,P.PORTER)
		world.warehouse_data.resources.add(R.LOG,1)
		var stock: RefCounted=kitchen.consumable_stocks[&"fuel"]
		check(world._request_work(actor),"Fuel job accepted before cancellation")
		var job=world.logistics.get_job(actor.data.id)
		if picked:
			for step in 18000:
				Step.move_3d(actor,.05)
				if actor.data.inventory.amount==1:break
			check(actor.data.inventory.amount==1,"Real log pickup before cancellation")
		world.logistics.cancel_transport(job,"test cancellation")
		world.logistics.cancel_transport(job,"repeat")
		check(stock.amount==0 and stock.incoming_units()==0 and actor.data.inventory.amount==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Cancel before/after pickup releases exact receiver and source promises")
		check(world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.LOG).reduce(func(n,drop):return n+drop.amount,0)==(1 if picked else 0),"Cargo survives cancellation once")
		world.free()
func efficiency() -> void:
	var world=F.create(self)
	var kitchen=kitchen_fixture(world)
	var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,kitchen.id,P.PORTER)
	var stock: RefCounted=kitchen.consumable_stocks[&"fuel"]
	stock.conversions[R.PLANK]=10 # Hypothetical alternative, no new real goods.
	kitchen.definition.logistics_flow[R.PLANK]={"import":true,"export":false}
	world.warehouse_data.resources.add(R.LOG,4);world.warehouse_data.resources.add(R.PLANK,1)
	var job=world.logistics.claim_best_job(actor.data.id)
	check(job!=null and job.resource_type==R.PLANK,"Porter prefers highest-yield reachable available material")
	world.logistics.cancel_transport(job,"retry")
	stock.amount=15
	job=world.logistics.claim_best_job(actor.data.id)
	check(job!=null and job.resource_type==R.LOG,"Whole-item fit skips higher-yield source")
	world.logistics.cancel_transport(job,"retry")
	stock.amount=18
	check(world.logistics.claim_best_job(actor.data.id)==null,"No partial fuel delivery fits at eighteen")
	stock.amount=10
	var owners: Array=[]
	for index in 3:
		var worker=world.resident_runtimes[index]
		var source=Source.new(Source.Kind.CONTAINER,world.warehouse_data.id)
		owners.append(world.logistics.claim_transport(worker.data.id,source,kitchen,R.LOG,func():return true,false,Callable(),false,0.0,null,&"",false,0,kitchen.consumable_receivers[&"fuel"]))
	check(owners[0]!=null and owners[1]!=null and owners[2]==null and stock.incoming_units()==10,"Competing physical jobs reserve shared converted capacity")
	world.logistics.cancel_transport(owners[0],"first")
	check(stock.incoming_units()==5 and world.logistics.inbound_valid(owners[1]),"One cancellation preserves foreign receiver claim")
	world.logistics.remove_building(kitchen.id)
	check(stock.incoming_units()==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Removed receiver releases remaining job immediately")
	world.free()

func receiver_lifecycle() -> void:
	for removed_source in [true,false]:
		var removed_world=F.create(self)
		var removed_kitchen=kitchen_fixture(removed_world)
		var removed_actor=removed_world.resident_runtimes[0]
		removed_world.player_control.assign_workplace(removed_actor.data.id,removed_kitchen.id,P.PORTER)
		removed_world.warehouse_data.resources.add(R.LOG,1)
		check(removed_world._request_work(removed_actor),"Claim fuel before entity removal")
		var removed_job=removed_world.logistics.get_job(removed_actor.data.id)
		for step in 18000:
			Step.move_3d(removed_actor,.05)
			if removed_actor.data.inventory.amount==1:break
		removed_world.logistics.remove_building(removed_world.warehouse_data.id if removed_source else removed_kitchen.id,false)
		check(not removed_job.is_active() and removed_actor.data.inventory.amount==0 and removed_kitchen.consumable_stocks[&"fuel"].incoming_units()==0 and removed_kitchen.consumable_stocks[&"fuel"].amount==0,"Removed source/receiver settles already-carried fuel immediately")
		removed_world.free()
	var world=F.create(self)
	var kitchen=kitchen_fixture(world)
	var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,kitchen.id,P.COOK)
	kitchen.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF)
	kitchen.resources.add(R.FLOUR,1)
	check(actor.self_logistics.task().is_empty() and not kitchen.can_start_production(&"bake_bread"),"No available fuel creates no fictitious work")
	world.warehouse_data.resources.add(R.LOG,1)
	var stock: RefCounted=kitchen.consumable_stocks[&"fuel"]
	check(world._request_work(actor),"New source found at ordinary decision")
	var job=world.logistics.get_job(actor.data.id)
	stock.changed.connect(func():
		if stock.amount>0:
			world.logistics.cancel_transport(job,"nested unload callback")
			check(not world.logistics.deliver_inbound(job),"Nested completion cannot convert twice"))
	for step in 18000:
		if world.logistics.get_job(actor.data.id)==null:break
		Step.move_3d(actor,.05)
	check(job.state==job.State.COMPLETED and stock.amount==5 and stock.incoming_units()==0 and actor.data.inventory.amount==0,"Committed unloading survives nested cancellation exactly once")
	check(not world.logistics.deliver_inbound(job) and stock.amount==5,"Repeated completion has no receiver claim")
	world.free()
	# The same physical good can independently feed two logical stocks and a normal buffer.
	world=F.create(self)
	var definition=D.for_type(T.FOOD)
	definition.consumable_definitions[&"test_water"]={"label":"Тестовый запас","capacity":30,"materials":{R.LOG:3}}
	var spawned: Dictionary=world.debug_spawn.spawn_building(Vector3(16,0,16),definition)
	kitchen=spawned.objects[0]
	world.resident_selection.select_building(kitchen)
	await process_frame
	var card=world.building_card_view()
	var water: RefCounted=kitchen.consumable_receivers[&"test_water"]
	water.reserve_in(R.LOG,1);water.add_reserved(R.LOG,1)
	check(card.consumable_rows.size()==3 and card.consumable_rows[&"test_water"].label.text.contains("3 / 30") and card.consumable_rows[&"fuel"].label.text.contains("0 / 20"),"Multiple local stock bars update independently")
	world.resident_selection.select_building(world.warehouse_data)
	check(not kitchen.consumable_stocks[&"test_water"].changed.is_connected(card._refresh_consumables) and card.consumable_rows.is_empty(),"Changing selection disconnects every previous stock")
	world.free()
