extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const D=preload("res://scripts/building_definition.gd")
const B=preload("res://scripts/building_instance.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/resource_category.gd").Type
const Catalog=preload("res://scripts/resource_catalog.gd")
const Work=preload("res://scripts/resident_recipe_controller.gd").Phase
const Intent=preload("res://scripts/resident_intent.gd")
const Step=preload("res://tests/handling_test_step.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func definitions() -> void:
	check(R.WOOL==6 and R.WOOL_CLOTH==7 and R.WOOL_CLOTHING==8 and C.WOOL==5 and C.WOOL_CLOTH==6 and C.SIMPLE_CLOTHING==7,"New concrete goods/categories append IDs")
	check(Catalog.types_in_category(C.WOOL_CLOTH)==[R.WOOL_CLOTH] and Catalog.types_in_category(C.SIMPLE_CLOTHING)==[R.WOOL_CLOTHING] and not Catalog.is_ready_food(R.WOOL_CLOTHING),"Concrete cloth and substitutable finished clothing remain separate categories, not food")
	var catalog=preload("res://scripts/ui/construction_catalog_data.gd").categories()[0].entries
	check(catalog.map(func(row):return row.definition.type)==[T.LUMBERJACK_HUT,T.QUARRY,T.GATHERER_HUT,T.SAWMILL,T.SHEPHERD_HUT,T.WEAVER_WORKSHOP,T.TAILOR_WORKSHOP,T.WINDMILL,T.FARM,T.CLAY_HUT,T.POTTERY_WORKSHOP],"Both independent workshops append to production catalogue; original order preserved")
	for type in [T.WEAVER_WORKSHOP,T.TAILOR_WORKSHOP]:
		var definition=D.for_type(type);var weaving: bool=type==T.WEAVER_WORKSHOP
		check(definition.construction_requirements==({R.LOG:4,R.PLANK:6,R.STONE:4} if weaving else {R.LOG:6,R.PLANK:8,R.STONE:4}) and definition.construction_work_required==(180 if weaving else 240),"Exact construction materials including stone and work")
		check(definition.worker_profession==(P.WEAVER if weaving else P.TAILOR) and definition.worker_capacity==1 and definition.porter_capacity==1,"One producer and one optional porter")
		var recipe=definition.production_recipe
		check(recipe.inputs==({R.WOOL:1} if weaving else {R.WOOL_CLOTH:3}) and recipe.outputs==({R.WOOL_CLOTH:1} if weaving else {R.WOOL_CLOTHING:1}) and recipe.work_required==(60 if weaving else 120),"Concrete recipes and exact work duration")
		var layout=preload("res://scripts/world_3d/building_layouts_3d.gd").create(definition)
		check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(layout,definition),"Authored entrance, worker, courier and construction layout")
		layout.free()
func batches() -> void:
	for type in [T.WEAVER_WORKSHOP,T.TAILOR_WORKSHOP]:
		var place=B.new(&"factory",D.for_type(type));var recipe=place.definition.production_recipe
		var input: int=recipe.inputs.keys()[0];var output: int=recipe.outputs.keys()[0];var cost: int=recipe.inputs[input]
		check(place.resources.get_capacity(input)==20 and place.resources.get_capacity(output)==(20 if type==T.WEAVER_WORKSHOP else 10) and not place.resources.add(R.FOOD,1),"Independent concrete buffers, foreign goods rejected")
		place.resources.add(input,cost-1)
		check(not place.can_start_production(recipe.id) and place.claim_production_work("worker")==null,"Insufficient input never partially spends")
		place.resources.add(input,1)
		place.resources.add(output,place.resources.get_capacity(output))
		check(place.claim_production_work("worker")==null and place.resources.get_amount(input)==cost,"Full output prevents start without input loss")
		place.resources.try_take(output,1)
		var batch=place.claim_production_work("worker");place.accept_production_batch(batch)
		check(batch!=null and place.resources.get_amount(input)==cost and place.resources.get_reserved_out(input)==cost and place.resources.get_reserved_in(output)==1,"Preparation reserves all input atomically without consumption")
		check(batch.begin("worker") and not batch.begin("worker") and place.resources.get_amount(input)==0,"Input consumed exactly once at actual begin")
		batch.advance("worker",recipe.work_required-1);batch.release_worker("worker")
		check(place.resumable_production_batch()==batch and batch.progress==recipe.work_required-1 and place.resources.get_reserved_in(output)==1,"Paid progress and output place belong to building during pause")
		check(place.claim_production_work("replacement")==batch and batch.begin("replacement") and place.resources.get_amount(input)==0,"Replacement resumes without repeated input")
		batch.advance("replacement",1)
		check(batch.finish("replacement") and not batch.finish("replacement") and place.resources.get_amount(output)==place.resources.get_capacity(output),"Whole output issued once after exact duration")
		place.retire_production_batch(batch)
		check(place.production_batches.is_empty() and place.resources.get_reserved_in(output)==0 and place.resources.get_reserved_out(input)==0,"Completed batch retires with no reservations")
func haul(world: Node,actor: Node) -> RefCounted:
	await physics_frame;await process_frame
	check(world._request_work(actor),"Normal worker/porter decision accepts physical transport")
	var job=world.logistics.get_job(actor.data.id)
	check(job!=null,"Real shared haul job exists")
	if job==null:return null
	for i in 18000:
		if world.logistics.get_job(actor.data.id)==null:break
		Step.move_3d(actor,.05)
	check(job.state==job.State.COMPLETED and actor.data.inventory.amount==0,"Physical pickup/delivery completes with empty inventory")
	return job
func start_recipe(world: Node,actor: Node) -> bool:
	await physics_frame;await process_frame
	check(world._request_work(actor),"Ordinary work selects production")
	for i in 12000:
		if actor.recipe_work.phase!=Work.GOING_TO_WORK:break
		Step.move_3d(actor,.05)
	check(actor.recipe_work.phase==Work.WORKING,"Physical entrance/worker slot precedes material consumption")
	return actor.recipe_work.phase==Work.WORKING
func physical_chain() -> void:
	var world=F.create(self)
	var loom=F.building(world,T.WEAVER_WORKSHOP,Vector3(-10,0,16))
	var tailor=F.building(world,T.TAILOR_WORKSHOP,Vector3(16,0,16))
	var hut=F.building(world,T.SHEPHERD_HUT,Vector3(30,0,24));hut.resources.add(R.WOOL,3)
	var weaver=world.resident_runtimes[0];var sewing=world.resident_runtimes[1];var porter=world.resident_runtimes[2]
	check(world.player_control.assign_workplace(weaver.data.id,loom.id) and weaver.data.profession==P.WEAVER and world.player_control.assign_workplace(sewing.data.id,tailor.id) and sewing.data.profession==P.TAILOR,"Default assignment selects correct professions")
	check(not world.player_control.assign_workplace(porter.data.id,loom.id,P.WEAVER),"Cannot overfill producer position")
	check(world.interactions.get_interactions([porter.data.id],loom.id).any(func(option):return option.id==&"employment" and not option.enabled),"Existing context employment respects worker capacity")
	check(world._request_work(weaver),"Textile supply can be accepted before cancellation")
	var cancelled=world.logistics.get_job(weaver.data.id)
	world.logistics.cancel_transport(cancelled,"Контроль отмены снабжения")
	check(hut.resources.get_amount(R.WOOL)==3 and hut.resources.get_reserved_out(R.WOOL)==0 and loom.resources.get_reserved_in(R.WOOL)==0 and weaver.data.inventory.amount==0,"Cancelled wool supply preserves stock and releases both owned obligations")
	for i in 3:
		var delivery=await haul(world,weaver)
		check(delivery!=null and delivery.resource_type==R.WOOL and delivery.source_location_id==hut.id and loom.resources.get_amount(R.WOOL)==1,"Weaver physically supplies one wool from shepherd hut")
		if not await start_recipe(world,weaver):world.free();return
		world.game_time.debug_skip_minutes(60)
		check(loom.resources.get_amount(R.WOOL_CLOTH)==i+1 and loom.resources.get_amount(R.WOOL)==0,"Sixty actual work minutes produce one cloth")
	check(not weaver.self_logistics.has_work(),"No fake destination: cloth stays with no warehouse quota or remaining input")
	for i in 3:
		var delivery=await haul(world,sewing)
		check(delivery!=null and delivery.resource_type==R.WOOL_CLOTH and delivery.source_location_id==loom.id and tailor.resources.get_amount(R.WOOL_CLOTH)==i+1,"Tailor supplies concrete cloth from another workplace output")
	if not await start_recipe(world,sewing):world.free();return
	world.game_time.debug_skip_minutes(70)
	var paid=sewing.recipe_work.batch
	var forced=Intent.new(Intent.Type.NONE,&"textile_interrupt",Vector2.ZERO,100,false)
	sewing.intents.force_set_intent(forced,100)
	check(paid.progress==70 and paid.state==paid.State.PAUSED and tailor.resources.get_amount(R.WOOL_CLOTH)==0 and tailor.resources.get_amount(R.WOOL_CLOTHING)==0,"Forced interruption keeps70/120 at building, no partial clothes/refund")
	sewing.intents.clear_completed(forced)
	if not await start_recipe(world,sewing):world.free();return
	check(sewing.recipe_work.batch==paid and paid.progress==70,"Actual worker resumes same paid batch")
	world.game_time.debug_skip_minutes(50)
	check(tailor.resources.get_amount(R.WOOL_CLOTHING)==1 and tailor.production_batches.is_empty(),"Remaining50 minutes finish exactly one clothing")
	var warehouse=world.warehouse_data
	warehouse.resources.set_category_quota(C.PLANK,40);warehouse.resources.set_category_quota(C.SIMPLE_CLOTHING,10)
	var exported=await haul(world,sewing)
	check(exported!=null and exported.resource_type==R.WOOL_CLOTHING and warehouse.resources.get_amount(R.WOOL_CLOTHING)==1,"Tailor self-exports actual clothing to real quota-admitting storage")
	loom.resources.add(R.WOOL_CLOTH,1)
	warehouse.resources.set_category_quota(C.PLANK,30);warehouse.resources.set_category_quota(C.WOOL_CLOTH,10)
	check(world.player_control.assign_workplace(porter.data.id,loom.id,P.PORTER) and not world.player_control.assign_workplace(world.resident_runtimes[3].data.id,loom.id,P.PORTER),"One optional porter only")
	var carried=await haul(world,porter)
	check(carried!=null and carried.resource_type==R.WOOL_CLOTH,"Optional porter uses common concrete resource transport")
	for place in [loom,tailor,hut,warehouse]:
		for resource in [R.WOOL,R.WOOL_CLOTH,R.WOOL_CLOTHING]:check(place.resources.get_reserved_in(resource)==0 and place.resources.get_reserved_out(resource)==0,"Completed physical chain leaves no resource reservations")
	world.free()
func construction_and_demolition() -> void:
	for type in [T.WEAVER_WORKSHOP,T.TAILOR_WORKSHOP]:
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
func speeds_and_shift() -> void:
	for speed in [1,2,4,10,20]:
		var world=F.create(self);world.game_time.set_speed(speed)
		var loom=F.building(world,T.WEAVER_WORKSHOP,Vector3(-10,0,16));loom.resources.add(R.WOOL,1)
		var tailor=F.building(world,T.TAILOR_WORKSHOP,Vector3(16,0,16));tailor.resources.add(R.WOOL_CLOTH,3)
		var weaver=world.resident_runtimes[0];var sewing=world.resident_runtimes[1]
		world.player_control.assign_workplace(weaver.data.id,loom.id);world.player_control.assign_workplace(sewing.data.id,tailor.id)
		if not await start_recipe(world,weaver) or not await start_recipe(world,sewing):world.free();return
		var began: int=world.game_time.total_minutes
		var first_completion: int=-1
		for i in 4000:
			world.game_time.advance(.05)
			if first_completion<0 and loom.resources.get_amount(R.WOOL_CLOTH)==1:first_completion=world.game_time.total_minutes-began
			if tailor.resources.get_amount(R.WOOL_CLOTHING)==1:break
		check(first_completion==60 and world.game_time.total_minutes-began==120 and tailor.resources.get_amount(R.WOOL_CLOTHING)==1,"Exact work minutes at x%d"%speed)
		world.free()
	var shift_world=F.create(self);var place=F.building(shift_world,T.WEAVER_WORKSHOP,Vector3(-10,0,16));place.resources.add(R.WOOL,1)
	var worker=shift_world.resident_runtimes[0];shift_world.player_control.assign_workplace(worker.data.id,place.id)
	if await start_recipe(shift_world,worker):
		shift_world.game_time.total_minutes=1379;worker.recipe_work._last_minute=1379
		shift_world.game_time.debug_skip_minutes(1)
		check(worker.recipe_work.phase==Work.WORKING and worker.recipe_work.batch.progress==1,"Ordinary night transition retains accepted textile work")
		shift_world.game_time.debug_skip_minutes(59)
		check(place.resources.get_amount(R.WOOL_CLOTH)==1,"Accepted textile batch finishes after shift")
	shift_world.free()
func run() -> void:
	definitions();batches();await physical_chain();await construction_and_demolition();await speeds_and_shift()
	print("Textile production: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
