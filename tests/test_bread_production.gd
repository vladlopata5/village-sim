extends "res://tests/test_textile_production.gd"
const Fields=preload("res://scripts/farm_fields.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const Coordinates=preload("res://scripts/world_3d/world_coordinates.gd")
var chain_events: Array=[]
func definitions() -> void:
	check(R.FLOUR==12 and R.BREAD==13 and C.FLOUR==11,"Goods/categories append stable IDs")
	check(Catalog.types_in_category(C.FLOUR)==[R.FLOUR] and Catalog.types_in_category(C.SIMPLE_FOOD)==[R.FOOD,R.FRIED_MUSHROOM,R.BREAD],"Flour separate; bread shares prepared food quota")
	check(not Catalog.is_ready_food(R.FLOUR) and Catalog.is_ready_food(R.BREAD) and Catalog.get_food_quality(R.BREAD)==Catalog.get_food_quality(R.FOOD),"Bread has ordinary food quality, flour is inedible")
	for type in [T.WINDMILL,T.BAKERY]:
		var d=D.for_type(type);var mill: bool=type==T.WINDMILL
		check(d.worker_capacity==1 and d.porter_capacity==1 and d.worker_profession==(P.MILLER if mill else P.BAKER),"One producer and optional porter")
		check(d.construction_requirements==({R.LOG:4,R.PLANK:6,R.STONE:4} if mill else {R.LOG:6,R.PLANK:8,R.STONE:4}) and d.construction_work_required==(180 if mill else 240),"Agreed costs/work")
		check(d.production_recipe.inputs==({R.WHEAT:2} if mill else {R.FLOUR:1}) and d.production_recipe.outputs==({R.FLOUR:1} if mill else {R.BREAD:1}) and d.production_recipe.work_required==60,"Exact sixty minute recipes, no fuel/optional product")
		var layout=preload("res://scripts/world_3d/building_layouts_3d.gd").create(d)
		check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(layout,d),"Valid physical slots/portal")
		layout.free()
func batches() -> void:
	for type in [T.WINDMILL,T.BAKERY]:
		var place=B.new(&"bread_factory",D.for_type(type));var recipe=place.definition.production_recipe
		var input: int=recipe.inputs.keys()[0];var output: int=recipe.outputs.keys()[0];var cost: int=recipe.inputs[input]
		check(place.resources.get_capacity(input)==20 and place.resources.get_capacity(output)==20 and not place.resources.is_warehouse(),"Independent20/20 producer buffers")
		place.resources.add(input,cost-1)
		check(place.claim_production_work("worker")==null and place.resources.get_reserved_out(input)==0,"Insufficient input blocks without loss/reservation")
		place.resources.add(input,1);place.resources.add(output,20)
		check(place.claim_production_work("worker")==null and place.resources.get_amount(input)==cost,"Full output blocks without spending")
		place.resources.try_take(output,1)
		var batch=place.claim_production_work("worker");place.accept_production_batch(batch)
		check(batch!=null and place.claim_production_work("second")==null and place.resources.get_reserved_in(output)==1,"Atomic single worker and output reservation")
		check(batch.begin("worker") and not batch.begin("worker") and place.resources.get_amount(input)==0,"Input consumed once only on start")
		batch.advance("worker",25);batch.release_worker("worker")
		check(batch.progress==25 and batch.claim("replacement") and batch.begin("replacement"),"Paid progress resumes with another worker")
		batch.advance("replacement",34);check(not batch.finish("replacement"),"No product before60")
		batch.advance("replacement",1)
		check(batch.finish("replacement") and not batch.finish("replacement") and place.resources.get_amount(output)==20,"Exactly one result at60")
		place.retire_production_batch(batch)
		check(place.production_batches.is_empty() and place.resources.get_reserved_in(output)==0 and place.resources.get_reserved_out(input)==0,"No reservations after completion")
func capture(_world: Node,_stage: String) -> void:
	# Flush deferred resource changes between observable integration stages.
	await process_frame
func field_work(world: Node,actor: Node) -> bool:
	if not actor.farmer.request_work():check(false,"Farmer accepts actual field operation");return false
	for step in 20000:
		Step.move_3d(actor,.05)
		if actor.farmer.phase==actor.farmer.Phase.WORKING:break
	check(actor.farmer.phase==actor.farmer.Phase.WORKING,"Physical field arrival")
	world.game_time.debug_skip_minutes(10)
	return true
func eat(world: Node,actor: Node,source: RefCounted) -> void:
	for place in world.buildings:
		for food in [R.FOOD,R.FRIED_MUSHROOM]:place.resources.try_take(food,place.resources.get_available_amount(food))
	actor.data.hunger=80
	check(actor.needs.food_availability.total()>0 and actor.needs.try_eat(8000) and actor.needs._meal_selection.concrete_type==R.BREAD,"FoodAvailability discovers and reserves actual bread")
	var other=world.resident_runtimes[2] if actor!=world.resident_runtimes[2] else world.resident_runtimes[1]
	other.data.hunger=80
	check(not other.needs.try_eat(8000),"Second resident cannot consume reserved single bread")
	for step in 12000:
		Step.move_3d(actor,.05)
		if actor.needs._meal_active:break
	check(actor.needs._meal_active and source.resources.get_amount(R.BREAD)==0 and source.resources.get_reserved_out(R.BREAD)==0 and actor.data.hunger==80,"Physical arrival consumes bread once before gradual satiety")
	var intent=actor.needs._active_intent
	actor.needs._on_arrival(intent)
	world.game_time.debug_skip_minutes(actor.needs._minutes_left)
	check(actor.data.hunger==20 and not actor.needs._meal_active,"Normal SIMPLE_FOOD hunger80→20, no double consumption")
func chain() -> void:
	var world=F.create(self);var farm=F.building(world,T.FARM,Vector3(-10,0,16));var mill=F.building(world,T.WINDMILL,Vector3(5,0,16));var bakery=F.building(world,T.BAKERY,Vector3(19,0,16))
	var farmer=world.resident_runtimes[0];var miller=world.resident_runtimes[1];var baker=world.resident_runtimes[2];var consumer=world.resident_runtimes[3]
	check(world.warehouse_data.resources.get_amount(R.WHEAT)==10 and world.warehouse_data.resources.get_amount(R.FOOD)==20 and world.warehouse_data.resources.get_amount(R.PLANK)==0,"New-game stocks unchanged; no flour/bread")
	for pair in [[farmer,farm,P.FARMER],[miller,mill,P.MILLER],[baker,bakery,P.BAKER]]:check(world.player_control.assign_workplace(pair[0].data.id,pair[1].id,pair[2]),"Assign bread-chain producer")
	farm.set_stock_target(R.WHEAT,0);farm.resources.add(R.WHEAT,1)
	for index in 5:if not field_work(world,farmer):world.free();return
	check(farmer.farmer.task().kind==&"SOW" and farmer.farmer.request_work(),"Actual five-cell sow starts")
	for index in 5:
		for step in 12000:
			Step.move_3d(farmer,.05)
			if farmer.farmer.phase==farmer.farmer.Phase.WORKING:break
		world.game_time.debug_skip_minutes(10)
	check(farm.resources.get_amount(R.WHEAT)==0,"Actual sow consumes one seed")
	world.game_time.debug_skip_minutes(6*1440+420-world.game_time.total_minutes)
	for cycle in 30:
		var task=farmer.farmer.task()
		if task.get("kind")==&"MOW":field_work(world,farmer)
		elif task.get("kind")==&"COLLECT":await haul(world,farmer)
		else:break
	check(farm.resources.get_amount(R.SHEAF)>=5,"Mature crops harvested and physically collected")
	await capture(world,"01-harvest")
	var sheaves: int=farm.resources.get_amount(R.SHEAF)
	for index in sheaves:
		if not await start_recipe(world,farmer):world.free();return
		world.game_time.debug_skip_minutes(30)
	check(farm.resources.get_amount(R.WHEAT)==sheaves and farm.resources.get_amount(R.SHEAF)==0,"AG1 real threshing supplies grain")
	world.game_time.debug_skip_minutes(1440-world.game_time.total_minutes%1440+420)
	for actor in world.resident_runtimes:
		actor.intents.abort_current(actor.intents.current_intent)
		for need in actor.data.needs.values():need.value=0
	# Exclude starter wheat as a source; the mill must use this farm harvest.
	world.warehouse_data.resources.try_take(R.WHEAT,world.warehouse_data.resources.get_available_amount(R.WHEAT))
	farm.set_stock_target(R.WHEAT,sheaves)
	await process_frame
	check(miller.self_logistics.task().is_empty(),"Farm grain floor protects all stock from mill")
	farm.set_stock_target(R.WHEAT,sheaves-2)
	for index in 2:
		var grain_job=await haul(world,miller)
		check(grain_job!=null and grain_job.source_location_id==farm.id and grain_job.resource_type==R.WHEAT,"Miller self-supplies farm surplus through SourceRef")
	check(farm.resources.get_amount(R.WHEAT)==sheaves-2 and mill.resources.get_amount(R.WHEAT)==2,"Farm floor preserved, two actual units arrived")
	if not await start_recipe(world,miller):world.free();return
	world.game_time.debug_skip_minutes(30)
	var paid=miller.recipe_work.batch
	var forced=Intent.new(Intent.Type.NONE,&"bread_interrupt",Vector2.ZERO,100,false)
	miller.intents.force_set_intent(forced,100)
	check(paid.progress==30 and paid.state==paid.State.PAUSED and mill.resources.get_amount(R.FLOUR)==0,"Forced command pauses paid batch without partial flour")
	miller.intents.clear_completed(forced)
	if not await start_recipe(world,miller):world.free();return
	world.game_time.debug_skip_minutes(30)
	check(mill.resources.get_amount(R.FLOUR)==1 and mill.resources.get_amount(R.WHEAT)==0,"Miller finishes one flour, no repeated wheat cost")
	await capture(world,"02-flour")
	check(world._request_work(baker),"Baker claims supply")
	var cancelled=world.logistics.get_job(baker.data.id);world.logistics.cancel_transport(cancelled,"AG2 cancel before pickup")
	check(mill.resources.get_amount(R.FLOUR)==1 and mill.resources.get_reserved_out(R.FLOUR)==0 and bakery.resources.get_reserved_in(R.FLOUR)==0,"Cancelled supply releases ownership with stock intact")
	var job=await haul(world,baker)
	check(job!=null and job.source_location_id==mill.id and job.resource_type==R.FLOUR,"Baker physically receives mill flour")
	if not await start_recipe(world,baker):world.free();return
	world.game_time.debug_skip_minutes(60)
	check(bakery.resources.get_amount(R.BREAD)==1 and bakery.resources.get_amount(R.FLOUR)==0,"Sixty-minute bake creates one bread without fuel")
	await capture(world,"03-bread")
	eat(world,consumer,bakery)
	await capture(world,"04-consumption")
	for place in [farm,mill,bakery]:
		for resource in [R.WHEAT,R.FLOUR,R.BREAD]:check(place.resources.get_reserved_in(resource)==0 and place.resources.get_reserved_out(resource)==0,"Chain ends without leaked claims")
	chain_events.append({"grain_produced":sheaves,"farm_grain":farm.resources.get_amount(R.WHEAT),"flour":mill.resources.get_amount(R.FLOUR),"bread":bakery.resources.get_amount(R.BREAD),"hunger":consumer.data.hunger})
	world.free()
func speeds_and_ports() -> void:
	for speed in [1,2,4,10,20]:
		var speed_world=F.create(self);speed_world.game_time.set_speed(speed)
		for type in [T.WINDMILL,T.BAKERY]:
			var place=F.building(speed_world,type,Vector3(-10 if type==T.WINDMILL else 16,0,16));var recipe=place.definition.production_recipe
			var actor=speed_world.resident_runtimes[0 if type==T.WINDMILL else 1]
			place.resources.add(recipe.inputs.keys()[0],recipe.inputs.values()[0]);speed_world.player_control.assign_workplace(actor.data.id,place.id)
			if not await start_recipe(speed_world,actor):speed_world.free();return
			var began: int=speed_world.game_time.total_minutes
			for i in 1300:
				speed_world.game_time.advance(.05)
				if actor.recipe_work.phase==Work.NONE:break
			check(speed_world.game_time.total_minutes-began==60 and place.resources.get_amount(recipe.outputs.keys()[0])==1,"Exactly60work minutes at speed%d"%speed)
		speed_world.free()
	var world=F.create(self);var mill=F.building(world,T.WINDMILL,Vector3(-10,0,16));var bakery=F.building(world,T.BAKERY,Vector3(16,0,16))
	var porter=world.resident_runtimes[0]
	mill.resources.add(R.FLOUR,1)
	check(world.player_control.assign_workplace(porter.data.id,bakery.id,P.PORTER) and not world.player_control.assign_workplace(world.residents[1].id,bakery.id,P.PORTER),"One optional porter")
	var job=await haul(world,porter)
	check(job!=null and job.resource_type==R.FLOUR and bakery.resources.get_amount(R.FLOUR)==1,"Optional porter supplies concrete flour")
	bakery.resources.add(R.BREAD,1);var warehouse=world.warehouse_data
	warehouse.resources.set_category_quota(C.PLANK,40);warehouse.resources.set_category_quota(C.FLOUR,10)
	mill.resources.add(R.FLOUR,1)
	warehouse.resources.try_take(R.WHEAT,warehouse.resources.get_available_amount(R.WHEAT))
	world.player_control.assign_workplace(porter.data.id,mill.id,P.PORTER)
	job=await haul(world,porter)
	check(job!=null and job.resource_type==R.FLOUR,"Optional mill porter exports through ordinary logistics")
	world.free()
func food_sources() -> void:
	for type in [T.FOOD,T.WINDMILL]:
		var world=F.create(self);var place=F.building(world,T.FOOD if type==T.FOOD else T.BAKERY,Vector3(-10,0,16))
		place.resources.add(R.BREAD,1)
		eat(world,world.resident_runtimes[0],place)
		world.free()
func bread_faults() -> void:
	var world=F.create(self);var mill=F.building(world,T.WINDMILL,Vector3(-10,0,16));var bakery=F.building(world,T.BAKERY,Vector3(16,0,16));var actor=world.resident_runtimes[0]
	for place in world.buildings:
		for food in [R.FOOD,R.FRIED_MUSHROOM,R.BREAD]:place.resources.try_take(food,place.resources.get_available_amount(food))
	mill.resources.add(R.FLOUR,1);actor.data.hunger=80
	check(actor.needs.food_availability.total()==0 and not actor.needs.try_eat(8000),"Flour never satisfies food availability or meal selection")
	var stack=world.ground_resources.try_place(R.BREAD,2,world.build_grid.world_to_cell(actor.view.global_position+Vector3(1,0,0))).stack
	check(stack!=null and stack.reserve(&"foreign"),"Two-unit ground bread with foreign reservation")
	await process_frame
	check(actor.needs.try_eat(8000) and actor.needs._food_source.kind==Source.Kind.GROUND,"Free unit of partly reserved ground bread stays edible")
	var intent=actor.needs._active_intent
	actor.intents.cancel_current(intent)
	check(stack.reserved_total()==1 and stack.reserved_amount(&"foreign")==1 and stack.amount==2,"Cancelled meal releases only its bread claim")
	check(actor.needs.try_eat(8000),"Bread can be reselected after cancellation")
	for step in 12000:
		Step.move_3d(actor,.05)
		if actor.needs._meal_active:break
	check(actor.needs._meal_active and stack.amount==1 and stack.reserved_amount(&"foreign")==1,"Physical partial bread pickup preserves stable stack and foreign claim")
	world.game_time.debug_skip_minutes(actor.needs._minutes_left)
	check(actor.data.hunger==20,"Ground bread uses same meal satiety")
	stack.release(&"foreign");world.ground_resources.remove_drop(stack)
	world.free()
	for removed in [T.WINDMILL,T.BAKERY]:
		world=F.create(self);mill=F.building(world,T.WINDMILL,Vector3(-10,0,16));bakery=F.building(world,T.BAKERY,Vector3(16,0,16));actor=world.resident_runtimes[0]
		mill.resources.add(R.FLOUR,1);world.player_control.assign_workplace(actor.data.id,bakery.id,P.BAKER)
		await process_frame
		check(world._request_work(actor),"Supply accepted before demolition")
		var job=world.logistics.get_job(actor.data.id)
		if removed==T.BAKERY:
			for step in 12000:
				Step.move_3d(actor,.05)
				if actor.data.inventory.amount==1:break
			check(actor.data.inventory.amount==1 and mill.resources.get_amount(R.FLOUR)==0,"Real flour pickup before target demolition")
		var target=mill if removed==T.WINDMILL else bakery
		check(world.change_construction_direction(target.id,true),"Demolition during active supply")
		check(not job.is_active() and actor.data.inventory.amount==0 and mill.resources.get_reserved_out(R.FLOUR)==0 and bakery.resources.get_reserved_in(R.FLOUR)==0,"Immediate transport cleanup and cargo settlement")
		var flour: int=world.ground_resources.drops.filter(func(d):return d.resource_type==R.FLOUR).reduce(func(n,d):return n+d.amount,0)
		world.logistics.cancel_transport(job,"repeat")
		check(flour==world.ground_resources.drops.filter(func(d):return d.resource_type==R.FLOUR).reduce(func(n,d):return n+d.amount,0),"Repeated cancellation cannot duplicate ground flour")
		world.free()
func run() -> void:
	definitions();batches();await chain();await bread_construction();await speeds_and_ports();food_sources();await bread_faults()
	print("AG2 bread production: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func bread_construction() -> void:
	for type in [T.WINDMILL,T.BAKERY]:
		var world=F.create(self)
		world.placement.select(D.for_type(type));world.placement.update_world_position(Vector3(-10,0,16))
		var site=world.placement.confirm()
		check(site!=null and not site.is_built() and not world.player_control.assign_workplace(world.residents[0].id,site.id),"Real placement creates nonoperational construction site")
		var builder=world.resident_runtimes[0];world.player_control.assign_profession(builder.data.id,P.BUILDER)
		for resource in [R.LOG,R.STONE,R.PLANK]:world.warehouse_data.resources.add(resource,site.get_required_amount(resource))
		var before: int=world.warehouse_data.resources.get_total_amount()
		await physics_frame;await process_frame
		world.game_time.set_speed(20)
		for i in 20000:
			if site.is_built():break
			if not builder.intents.has_current_action():world._request_work(builder)
			Step.move_3d(builder,.05);world.game_time.advance(.05)
		check(site.is_built() and site.are_construction_materials_complete() and site.construction_progress==site.definition.construction_work_required,"All real materials physically delivered and full construction labor completed")
		var total: int=0
		for amount in site.definition.construction_requirements.values():total+=amount
		check(before-world.warehouse_data.resources.get_total_amount()==total and builder.data.inventory.amount==0,"Construction consumes exact14/18 physical units without cargo duplication")
		check(world.logistics._buildings.get(site.id)==site,"Normal construction activates logistics and buffers")
		var recipe=site.definition.production_recipe;var input: int=recipe.inputs.keys()[0]
		site.resources.add(input,recipe.inputs[input]);var batch=site.claim_production_work("paid");site.accept_production_batch(batch);batch.begin("paid");batch.advance("paid",20);batch.release_worker("paid")
		check(world.change_construction_direction(site.id,true) and batch.is_terminal() and site.production_batches.is_empty() and site.resources.get_amount(input)==0,"D1 cancels paid WIP, without returning spent materials")
		site.work_paused=false;site.add_construction_work(20)
		check(world.change_construction_direction(site.id,false),"Demolition can be reversed")
		site.work_paused=false;site.add_construction_work(site.work_remaining())
		check(site.complete_construction() and not site.production_removed and site.production_batches.is_empty() and site.resources.get_reserved_in(recipe.outputs.keys()[0])==0,"Restoration reactivates empty process and releases old output obligations")
		world.free()
