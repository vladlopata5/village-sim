extends "res://tests/test_textile_production.gd"
const BuildPhase=preload("res://scripts/resident_builder_controller.gd").Phase
var observer: Callable
var transitions: Array=[]
func observe(world: Node,site: RefCounted,label: String) -> void:
	if observer.is_valid():await observer.call(world,label,site)
func place(world: Node,type: int,point: Vector3) -> RefCounted:
	world.placement.select(D.for_type(type));world.placement.update_world_position(point)
	var site=world.placement.confirm()
	check(site!=null,"Real staged site passes ordinary placement")
	return site
func supply(world: Node,site: RefCounted) -> void:
	for resource in site.definition.construction_requirements:
		check(world.warehouse_data.resources.add(resource,site.get_required_amount(resource)),"Exact unchanged construction materials prepared in source")
func drive(world: Node,site: RefCounted,actors: Array,stop: Callable=Callable()) -> void:
	var observed: int=site.completed_construction_stage_count()
	for step in 30000:
		if site.state==B.State.REMOVED or site.is_built() or (stop.is_valid() and stop.call()):return
		if world.game_time.total_minutes%1440>=1010:
			for actor in actors:actor.intents.abort_current(actor.intents.current_intent)
			world.game_time.debug_skip_minutes(1440-world.game_time.total_minutes%1440+420)
			for actor in actors:
				for need in actor.data.needs.values():need.value=0
		for actor in actors:
			if not actor.intents.has_current_action():world._request_work(actor)
			actor.view._physics_process(.05)
		world.game_time.advance(.05)
		var count: int=site.completed_construction_stage_count()
		if count!=observed:
			transitions.append({"building":site.id,"from":observed,"to":count,"work":site.construction_progress})
			if site.work_direction==B.WorkDirection.BUILD:check(count==observed+1,"Physical workers cross exactly one forward stage boundary")
			observed=count
			await observe(world,site,"stage_%d"%count)
		if step%40==0:await process_frame # Occupied authored courier wakes on its normal deferred callback.
	check(false,"Staged physical operation terminates")
func workers(world: Node,count: int=2) -> Array:
	var actors: Array=[]
	for index in count:
		var actor=world.resident_runtimes[index]
		check(world.player_control.assign_profession(actor.data.id,P.BUILDER),"Ordinary Builder assignment")
		actors.append(actor)
	return actors
func run() -> void:
	await production_building()
	await well()
	await cancellation()
	await interruptions()
	await covered_boundary()
	print("Staged builders: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func production_building() -> void:
	var world=F.create(self);var site=place(world,T.SAWMILL,Vector3(-12,0,16));supply(world,site)
	var actors=workers(world)
	world.resident_selection.select_building(site)
	await observe(world,site,"initial")
	check(not world.player_control.assign_workplace(world.resident_runtimes[2].data.id,site.id,P.SAWYER) and site.resources.get_capacity(R.LOG)==0,"No jobs or production buffers before final stage")
	check(world._request_work(actors[0]) and world._request_work(actors[1]) and site.active_builder_ids.size()==2 and not site.claim_builder_slot("third"),"Two independent builders never exceed real slot capacity")
	check(site.get_construction_reserved_in(R.LOG)==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Frame timber is not ordered before the stone base is finished")
	await drive(world,site,actors)
	check(site.is_built() and site.construction_progress==240 and site.construction_delivered=={R.LOG:6,R.STONE:6} and site.active_builder_ids.is_empty(),"Two real builders finish all stages at exact old cost and work")
	check(world._activated_buildings.has(site.id) and world.logistics._buildings.has(site.id),"Final stage enables ordinary existing production and logistics")
	for resource in [R.LOG,R.STONE]:check(site.get_construction_reserved_in(resource)==0 and world.warehouse_data.resources.get_reserved_out(resource)==0,"Final construction leaves no inbound or outbound reserve")
	await observe(world,site,"built")
	var sawyer=world.resident_runtimes[2]
	check(world.player_control.assign_workplace(sawyer.data.id,site.id,P.SAWYER),"Completed workplace accepts normal worker")
	check(world.warehouse_data.resources.add(R.LOG,1),"Prepare a separate actual production input")
	var job=await haul(world,sawyer)
	check(job!=null and job.resource_type==R.LOG,"Newly built Sawmill physically supplies production input")
	if await start_recipe(world,sawyer):world.game_time.debug_skip_minutes(60)
	check(site.resources.get_amount(R.PLANK)==1,"Production works after final activation, not during intermediate shapes")
	world.free();await process_frame
func well() -> void:
	var world=F.create(self);var site=place(world,T.WELL,Vector3(-12,0,16));supply(world,site)
	var actors=workers(world,1)
	check(world.water_sources.candidates().is_empty(),"Unbuilt well is not a source")
	await drive(world,site,actors,func():return site.completed_construction_stage_count()==1)
	check(not site.is_built() and site.construction_progress==60 and site.get_delivered_amount(R.STONE)==4 and site.get_delivered_amount(R.LOG)==0 and world.water_sources.candidates().is_empty(),"Well foundation exposes timber demand but cannot give water")
	await observe(world,site,"well_base")
	await drive(world,site,actors)
	check(site.is_built() and site.construction_progress==120 and site.construction_delivered=={R.LOG:4,R.STONE:4},"Well completes two stages with original balance")
	var kitchen=F.building(world,T.FOOD,Vector3(16,0,16));kitchen.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF);kitchen.resources.add(R.FLOUR,1)
	kitchen.consumable_receivers[&"fuel"].reserve_in(R.LOG,1);kitchen.consumable_receivers[&"fuel"].add_reserved(R.LOG,1)
	var cook=world.resident_runtimes[2];world.player_control.assign_workplace(cook.data.id,kitchen.id,P.COOK)
	var job=await haul(world,cook)
	check(job!=null and job.resource_type==R.WATER and job.source_location_id==site.id and kitchen.consumable_stocks[&"water"].amount==5,"Completed staged well supplies real finite water cargo through WAT1")
	await observe(world,site,"well_water")
	world.free();await process_frame
func cancellation() -> void:
	for boundary in [1,2]:
		var world=F.create(self);var site=place(world,T.SAWMILL,Vector3(-12,0,16));supply(world,site)
		var actors=workers(world)
		await drive(world,site,actors,func():return site.completed_construction_stage_count()==boundary and site.get_delivered_amount(R.LOG)>(0 if boundary==1 else 3))
		check(site.construction_progress==(60 if boundary==1 else 160) and site.get_delivered_amount(R.STONE)==6,"Partial next stage retains completed base")
		await observe(world,site,"cancel_partial_%d"%boundary)
		var owned: Dictionary=site.construction_delivered
		for actor in actors:
			if actor.data.inventory.amount>0:owned[actor.data.inventory.resource_type]=int(owned.get(actor.data.inventory.resource_type,0))+actor.data.inventory.amount
		check(world.cancel_construction(site.id),"Cancel intermediate staged building through D1")
		await drive(world,site,actors)
		check(site.state==B.State.REMOVED and world.demolition_results.has(site.id),"Ordinary reverse labour removes unfinished building")
		for resource in [R.LOG,R.STONE]:
			var amount: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==resource).reduce(func(total,drop):return total+drop.amount,0)
			check(amount==int(owned.get(resource,0)) and world.warehouse_data.resources.get_reserved_out(resource)==0 and site.get_construction_reserved_in(resource)==0,"D1 returns100percent delivered including completed stages and drops carried cargo once")
		check(actors.all(func(actor):return actor.data.inventory.amount==0 and actor.builder.site==null) and site.active_builder_ids.is_empty(),"Cancellation removes assignments, subscriptions and cargo ownership")
		world.free();await process_frame
func interruptions() -> void:
	for mode in [&"player",&"profession",&"phase",&"critical"]:
		var world=F.create(self);var site=place(world,T.FOOD,Vector3(-12,0,16));supply(world,site)
		var actors=workers(world,1);var actor=actors[0]
		await drive(world,site,actors,func():return site.construction_progress>=17)
		var work: int=site.construction_progress;var delivered: Dictionary=site.construction_delivered
		if mode==&"player":actor.commands.move_to(Vector2.ZERO)
		elif mode==&"profession":world.player_control.assign_profession(actor.data.id,P.NONE);actor.intents.abort_current(actor.intents.current_intent)
		elif mode==&"critical":actor.decision._deciding=false;actor.data.fatigue=100
		else:
			world.game_time.total_minutes=1019;actor.builder._last_work_minute=1019
			world.game_time.debug_skip_minutes(1);work+=1 # The minute ending at17:00 is a real final work minute.
		check(actor.builder.site==null and site.active_builder_ids.is_empty() and site.construction_progress==work and site.construction_delivered==delivered,"Stage work/materials survive forced interruption without leaked slot")
		world.free();await process_frame

func covered_boundary() -> void:
	var world=F.create(self);var site=place(world,T.STORAGE,Vector3(-12,0,16));var actor=workers(world,1)[0]
	site.add_delivered_material(R.STONE,4)
	check(world._request_work(actor),"Ready first stage admits an ordinary Builder")
	for step in 12000:
		actor.view._physics_process(.05)
		if actor.builder.phase==BuildPhase.BUILDING:break
	# This promise becomes possible only after the first boundary, in its notification.
	var promise=func():
		if site.construction_stage_index()==1 and site.get_construction_reserved_in(R.LOG)==0 and site.get_delivered_amount(R.LOG)==0:site.reserve_construction_material(R.LOG,2)
	site.construction_changed.connect(promise)
	check(site.add_construction_work(60),"First stage completes with another participant promising the next materials")
	site.construction_changed.disconnect(promise)
	await process_frame;await process_frame
	check(actor.builder.phase==BuildPhase.WAITING_FOR_MATERIALS and actor.builder.site==site,"Related worker enters event-driven waiting rather than pretending to build a material-less next stage")
	var searches: int=actor.builder.source_search_count
	world.game_time.debug_skip_minutes(3)
	check(site.construction_progress==60 and actor.builder.source_search_count==searches,"Covered stage boundary neither works nor polls for new sources")
	check(site.deliver_reserved_construction_material(R.LOG,2),"Accepted next-stage promise arrives once")
	await process_frame;await process_frame
	for step in 12000:
		actor.view._physics_process(.05)
		if actor.builder.phase==BuildPhase.BUILDING:break
	world.game_time.debug_skip_minutes(1)
	check(actor.builder.phase==BuildPhase.BUILDING and site.construction_progress==61 and site.get_construction_reserved_in(R.LOG)==0,"Addressed delivery wakes the same Builder and advances only the next real work minute")
	world.free();await process_frame
