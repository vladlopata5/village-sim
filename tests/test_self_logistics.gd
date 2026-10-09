extends SceneTree
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Ref = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
const Builder = preload("res://scripts/resident_builder_controller.gd")
const Fixture = preload("res://tests/forestry_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func scene() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes = 420
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.schedule._phase = "День"
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
	for resource in R.values(): world.warehouse_data.resources.try_take(resource,world.warehouse_data.resources.get_amount(resource))
	return world
func place(world: Node, type: int, at: Vector3, built: bool = true):
	world.placement.select(Def.for_type(type))
	world.placement.update_world_position(at)
	var building = world.placement.confirm()
	check(building!=null,"Physical placement succeeds")
	if building!=null and built:
		for resource in building.definition.construction_requirements: building.add_delivered_material(resource,building.get_required_amount(resource))
		building.add_construction_work(building.definition.construction_work_required)
		check(building.complete_construction(),"Normal building completion")
	return building
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(2000):
		actor.view._physics_process(0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id!=reason: break
		if not actor.view.movement.is_moving(): break
func idle(actor: Node) -> void:
	if actor.commands.active_command!=null: actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
func run() -> void:
	var world = scene()
	var saw = place(world,Types.SAWMILL,Vector3(4,0,14))
	var worker = world.resident_runtimes[1]
	check(world.player_control.assign_workplace(worker.data.id,saw.id),"Sawyer assigned through management")
	check(not world._work_available(worker),"No sources means no work")
	var drop = world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(1,0,10)))
	check(worker.self_logistics.task().kind==&"SUPPLY" and world._work_available(worker),"Ground LOG creates normal Sawyer supply candidate")
	check(worker.decision.collect_actions(true).any(func(row): return row.id=="WORK" and row.priority==7000),"Self logistics keeps standard WORK category")
	check(world._request_work(worker),"Sawyer self-supply starts shared committed haul")
	var job = world.logistics.get_job(worker.data.id)
	check(job.source_ref.kind==Ref.Kind.GROUND and drop.reservation_owner_id==job.id and saw.resources.get_reserved_in(R.LOG)==1,"Ground claim and inbound owned by job")
	check(world.logistics.claim_best_job(world.resident_runtimes[0].data.id)==null,"Porter cannot steal Sawyer ground claim")
	walk(worker,&"haul_source")
	check(worker.data.inventory.amount==1 and drop not in world.ground_resources.drops,"Pickup is physical, last Ground disappears")
	check(world.logistics._executors[worker.data.id].validate_job(),"After pickup haul no longer depends on Ground existence")
	walk(worker)
	check(job.state==Job.State.COMPLETED and saw.resources.get_amount(R.LOG)==1 and saw.resources.get_reserved_in(R.LOG)==0,"One LOG delivered, inbound released")
	check(worker.self_logistics.task().kind==&"PRODUCTION" and world._request_work(worker),"Available production wins over self-hauling")
	walk(worker)
	world.game_time.debug_skip_minutes(30)
	check(saw.resources.get_amount(R.PLANK)==1 and saw.resources.get_amount(R.LOG)==0,"Unchanged recipe consumes one LOG / produces PLANK")
	check(worker.self_logistics.task().kind==&"EXPORT" and world._request_work(worker),"Without input Sawyer self-exports output")
	job = world.logistics.get_job(worker.data.id)
	check(job.destination_location_id==world.warehouse_data.id and job.source_location_id==saw.id,"Self export is own workplace to Storage only")
	walk(worker,&"haul_source")
	walk(worker)
	check(world.warehouse_data.resources.get_amount(R.PLANK)==1 and saw.resources.get_amount(R.PLANK)==0,"Sawyer export reaches Storage physically")
	check(worker.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.LOGISTICS)==0,"Sawyer self hauling has no extra Logistics XP")
	# Ground despawn before pickup releases inbound, source claim, and job.
	drop = world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(-4,0,10)))
	check(world._request_work(worker),"Second supply starts")
	job = world.logistics.get_job(worker.data.id)
	world.ground_resources._on_minute(drop.created_at+drop.lifetime)
	world.logistics.recalculate()
	check(job.state==Job.State.CANCELLED and saw.resources.get_reserved_in(R.LOG)==0 and drop.reservation_owner_id.is_empty(),"Despawn before pickup cancels and cleans both reservations")
	idle(worker)
	# Interrupts before and after pickup.
	drop = world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(-4,0,10)))
	check(world._request_work(worker),"Supply before PlayerCommand")
	worker.commands.move_to(Vector2(0,500))
	check(drop.amount==1 and drop.reservation_owner_id.is_empty() and saw.resources.get_reserved_in(R.LOG)==0,"Before pickup interrupt preserves source and clears reserves")
	idle(worker)
	check(world._request_work(worker),"Supply resumes through decision")
	walk(worker,&"haul_source")
	worker.commands.move_to(Vector2(0,500))
	check(worker.data.inventory.amount==0 and saw.resources.get_amount(R.LOG)==0 and saw.resources.get_reserved_in(R.LOG)==0 and world.ground_resources.drops.size()==1,"After pickup interruption drops cargo, no source restoration")
	idle(worker)
	check(world._request_work(worker),"Dropped material is globally reusable")
	walk(worker,&"haul_source")
	world.game_time.total_minutes=1020
	world.game_time.phase_changed.emit("Вечер")
	check(world.logistics.get_job(worker.data.id)==null and worker.data.inventory.amount==0 and saw.resources.get_reserved_in(R.LOG)==0,"Worker safe cleanup at schedule end, no night forced haul")
	world.free()
	# Gatherer own output fallback; resume unchanged production when buffer freed.
	world = scene()
	worker = world.resident_runtimes[2]
	check(world.player_control.assign_workplace(worker.data.id,world.gatherer_hut_data.id),"Gatherer owns Hut")
	world.gatherer_hut_data.resources.add(R.FOOD,5)
	check(worker.self_logistics.task().kind==&"EXPORT" and world._request_work(worker),"Full Gatherer buffer creates self export")
	job = world.logistics.get_job(worker.data.id)
	check(job.source_location_id==world.gatherer_hut_data.id and job.destination_location_id==world.warehouse_data.id,"Gatherer never supplies Kitchen directly")
	walk(worker,&"haul_source")
	walk(worker)
	check(world.gatherer_hut_data.resources.get_amount(R.FOOD)==4 and world.warehouse_data.resources.get_amount(R.FOOD)==1 and worker.self_logistics.task().kind==&"PRODUCTION","Buffer freed: production first on next normal decision")
	world.free()
	# Builder vs Porter competition for same Ground PLANK and export policy.
	world = scene()
	var site = place(world,Types.HOME,Vector3(-12,0,14),false)
	worker = world.resident_runtimes[1]
	world.player_control.assign_profession(worker.data.id,P.BUILDER)
	drop = world.ground_resources.create_drop(R.PLANK,1,world.world_locations.get_position(site.id))
	await process_frame
	check(world._request_work(worker),"Builder sources Ground PLANK")
	check(worker.builder.source_ref.kind==Ref.Kind.GROUND and site.get_construction_reserved_in(R.PLANK)==1,"Builder keeps construction inbound outside normal HaulJob")
	check(world.logistics.collect_candidates(world.resident_runtimes[0].data.id).is_empty(),"Porter cannot claim Builder material")
	walk(worker,&"builder_source")
	walk(worker)
	check(site.get_delivered_amount(R.PLANK)==1 and site.get_construction_reserved_in(R.PLANK)==0,"Ground delivered physically to construction")
	saw = place(world,Types.SAWMILL,Vector3(4,0,14))
	saw.resources.add(R.LOG,2)
	site.definition.construction_requirements={R.LOG:1}
	worker.builder._on_world_changed()
	check(worker.builder.nearest_source(R.LOG,worker.view.get_sim_position())==null and not worker.builder.has_work(),"Builder generic LOG requirement cannot steal nonexportable Sawmill input")
	site.definition.construction_requirements={R.PLANK:10}
	saw.resources.add(R.PLANK,1)
	worker.builder._on_world_changed()
	check(world._request_work(worker) and worker.builder.source==saw,"Builder can use exportable Sawmill PLANK")
	var porter = world.resident_runtimes[0]
	check(not world.logistics.collect_candidates(porter.data.id).any(func(row): return row.resource_type==R.PLANK),"Container PLANK reservation prevents Porter double hauling")
	worker.commands.move_to(Vector2(0,500))
	check(saw.resources.get_reserved_out(R.PLANK)==0 and site.get_construction_reserved_in(R.PLANK)==0,"Builder source+site cleanup uses shared source ownership")
	world.free()
	# Actual three-way Ground LOG competition, with local forestry rules preserved.
	world = scene()
	var hut = Fixture.hut(world)
	saw = place(world,Types.SAWMILL,Vector3(-12,0,-14))
	worker = world.resident_runtimes[1]
	world.player_control.assign_workplace(worker.data.id,saw.id)
	var lumber = world.resident_runtimes[3]
	world.player_control.assign_workplace(lumber.data.id,hut.id)
	drop = world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(-14,0,-10)))
	check(lumber.get_node("Lumberjack").best_task().kind==&"COLLECT","Lumberjack sees global Ground within local radius")
	check(world._request_work(worker),"Sawyer wins only by first successful claim")
	check(lumber.get_node("Lumberjack").best_task().kind!=&"COLLECT" and not world.logistics.collect_candidates(world.resident_runtimes[0].data.id).any(func(row): return row.source_ref.id==drop.id),"Lumberjack and Porter respect same exclusive claim")
	worker.commands.move_to(Vector2(0,500))
	check(world._request_work(lumber) and lumber.get_node("Lumberjack").kind==&"COLLECT","After release Lumberjack can win same Ground")
	check(not world._work_available(worker),"Sawyer cannot reserve Lumberjack's claimed source")
	lumber.commands.move_to(Vector2(0,500))
	var candidates: Array = world.logistics.collect_candidates(world.resident_runtimes[0].data.id)
	check(candidates.any(func(row): return row.source_ref.id==drop.id),"Porter also sees released globally claimable LOG")
	var ground_candidate = candidates.filter(func(row): return row.source_ref.id==drop.id)[0]
	check(is_equal_approx(ground_candidate.porter_score,ground_candidate.world_urgency-ground_candidate.distance_penalty+preload("res://scripts/balance_config.gd").PORTER_GROUND_CLEANUP_BONUS),"Small Ground score bonus, no age term")
	job = world.logistics.claim_best_job(world.resident_runtimes[0].data.id)
	check(job!=null and job.source_ref.id==drop.id and job.destination_location_id==world.warehouse_data.id,"Porter Ground pickup goes only to own Storage")
	porter = world.resident_runtimes[0]
	check(world.logistics.start_claimed_job(job,porter.data.id),"Porter shared physical executor")
	walk(porter,&"haul_source")
	walk(porter)
	check(world.warehouse_data.resources.get_amount(R.LOG)==1 and job.state==Job.State.COMPLETED,"Porter completes Ground delivery")
	world.free()
	# Container supply is shared, and input-only Sawmill LOG never enters candidates.
	world = scene()
	saw = place(world,Types.SAWMILL,Vector3(4,0,14))
	var protected_saw = place(world,Types.SAWMILL,Vector3(-12,0,-14))
	worker = world.resident_runtimes[1]
	world.player_control.assign_workplace(worker.data.id,saw.id)
	protected_saw.resources.add(R.LOG,2)
	check(not world._work_available(worker) and not world.logistics.collect_candidates(world.resident_runtimes[0].data.id).any(func(row): return row.source_ref.id==protected_saw.id),"Other Sawmill LOG cannot supply Sawyer B / Porter")
	hut = Fixture.hut(world)
	hut.resources.add(R.LOG,1)
	check(worker.self_logistics.task().source.id==hut.id and world._request_work(worker),"Sawyer self-supply from exportable Lumberjack Hut")
	walk(worker,&"haul_source")
	walk(worker)
	check(hut.resources.get_amount(R.LOG)==0 and saw.resources.get_amount(R.LOG)==1,"Hut input delivered only to assigned Sawmill")
	check(worker.self_logistics.task().kind==&"PRODUCTION","Production chosen even with output available")
	saw.resources.try_take(R.LOG,1)
	world.warehouse_data.resources.add(R.LOG,1)
	check(worker.self_logistics.task().source.id==world.warehouse_data.id and world._request_work(worker),"Sawyer can self-supply from Storage")
	walk(worker,&"haul_source")
	walk(worker)
	check(world.warehouse_data.resources.get_amount(R.LOG)==0 and saw.resources.get_amount(R.LOG)==1,"Storage supply physical flow")
	saw.resources.add(R.PLANK,12)
	check(worker.self_logistics.task().kind==&"EXPORT" and world._request_work(worker),"Output blocked: export precedes supply")
	walk(worker,&"haul_source")
	walk(worker)
	check(worker.self_logistics.task().kind==&"PRODUCTION","Freed output returns to production on next decision")
	world.free()
	# Porter Ground resource eligibility and configured bonus remain relative to urgency.
	world = scene()
	porter = world.resident_runtimes[0]
	for resource in [R.FOOD,R.PLANK,R.LOG]:
		drop = world.ground_resources.create_drop(resource,1,world.world_locations.get_position(world.warehouse_data.id))
		candidates = world.logistics.collect_candidates(porter.data.id)
		check(candidates.any(func(row): return row.source_ref.id==drop.id and row.destination.id==porter.data.work_location_id),"Ground FOOD/PLANK/LOG only own Storage")
		world.warehouse_data.resources.reserve_in(resource,world.warehouse_data.resources.get_available_free_capacity(resource))
		check(not world.logistics.collect_candidates(porter.data.id).any(func(row): return row.source_ref.id==drop.id),"Projected full own Storage filters Ground")
		world.warehouse_data.resources.release_in(resource,world.warehouse_data.resources.get_reserved_in(resource))
		Fixture.clear_drops(world)
	world.warehouse_data.resources.add(R.FOOD,10)
	drop = world.ground_resources.create_drop(R.FOOD,1,C.to_sim(Vector3(40,0,28)))
	candidates = world.logistics.collect_candidates(porter.data.id)
	var normal = candidates.filter(func(row): return row.source_ref.kind==Ref.Kind.CONTAINER)[0]
	ground_candidate = candidates.filter(func(row): return row.source_ref.id==drop.id)[0]
	check(normal.porter_score>ground_candidate.porter_score and world.logistics._best(candidates).source_ref.kind==Ref.Kind.CONTAINER,"Distant Ground cleanup bonus cannot override much better normal delivery")
	world.free()
	# Builder Ground interruption semantics and re-use without duplication.
	world = scene()
	site = place(world,Types.HOME,Vector3(-12,0,14),false)
	worker = world.resident_runtimes[1]
	world.player_control.assign_profession(worker.data.id,P.BUILDER)
	drop = world.ground_resources.create_drop(R.PLANK,1,world.world_locations.get_position(site.id))
	worker.builder._on_world_changed()
	check(world._request_work(worker),"Ground Builder task before pickup")
	worker.commands.move_to(Vector2(0,500))
	check(drop.amount==1 and drop.reservation_owner_id.is_empty() and site.get_construction_reserved_in(R.PLANK)==0,"Builder Ground before pickup releases both claims")
	idle(worker)
	worker.builder._on_world_changed()
	check(world._request_work(worker),"Ground Builder task resumed")
	walk(worker,&"builder_source")
	worker.commands.move_to(Vector2(0,500))
	check(worker.data.inventory.amount==0 and site.get_delivered_amount(R.PLANK)==0 and site.get_construction_reserved_in(R.PLANK)==0 and world.ground_resources.drops.size()==1,"Builder Ground after pickup drops PLANK without duplicating")
	world.free()
	# Event-driven wakeup uses normal decision lifecycle, no forced self-haul timer.
	world = scene()
	saw = place(world,Types.SAWMILL,Vector3(4,0,14))
	worker = world.resident_runtimes[1]
	world.player_control.assign_workplace(worker.data.id,saw.id)
	worker.wander.target_provider=Callable()
	worker.decision._deciding=false
	worker.decision.request_decision("no_input")
	check(not worker.intents.has_current_action(),"Unavailable worker can idle normally")
	world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(1,0,10)))
	await process_frame
	await process_frame
	check(world.logistics.get_job(worker.data.id)!=null and worker.decision.last_selection.candidates.any(func(row): return row.id=="WORK"),"Ground availability wakes ordinary WORK through UtilitySelector")
	worker.decision._deciding=true
	world.free()
	# Revalidation and synchronous interrupt rollback apply to non-Porter hauls too.
	world = scene()
	saw = place(world,Types.SAWMILL,Vector3(4,0,14))
	worker = world.resident_runtimes[1]
	world.player_control.assign_workplace(worker.data.id,saw.id)
	drop = world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(1,0,10)))
	var interrupt = func(resource):
		if resource==R.LOG: worker.commands.move_to(Vector2(0,500))
	saw.resources.reservations_changed.connect(interrupt)
	check(not world._request_work(worker) and world.logistics.get_job(worker.data.id)==null and drop.reservation_owner_id.is_empty() and saw.resources.get_reserved_in(R.LOG)==0,"Synchronous forced change inside claim rolls back, creates no HaulJob")
	saw.resources.reservations_changed.disconnect(interrupt)
	idle(worker)
	check(world._request_work(worker),"Claim after rollback works normally")
	job = world.logistics.get_job(worker.data.id)
	saw.resources.release_in(R.LOG,1)
	check(job.state==Job.State.CANCELLED and drop.reservation_owner_id.is_empty(),"Lost inbound cancels before pickup; source untouched")
	idle(worker)
	check(world._request_work(worker),"Critical-before-pickup setup")
	worker.decision._deciding=false
	worker.data.fatigue=100
	check(world.logistics.get_job(worker.data.id)==null and drop.amount==1 and drop.reservation_owner_id.is_empty() and saw.resources.get_reserved_in(R.LOG)==0,"Critical need before pickup releases both promises")
	worker.decision._deciding=true
	idle(worker)
	worker.data.fatigue=0
	check(world._request_work(worker),"Critical-after-pickup setup")
	walk(worker,&"haul_source")
	worker.decision._deciding=false
	worker.data.fatigue=100
	check(worker.data.inventory.amount==0 and world.ground_resources.drops.size()==1 and saw.resources.get_reserved_in(R.LOG)==0 and world.logistics.get_job(worker.data.id)==null,"Critical need after pickup drops cargo without loss")
	worker.decision._deciding=true
	idle(worker)
	worker.data.fatigue=0
	check(world._request_work(worker),"Destination removal setup")
	job = world.logistics.get_job(worker.data.id)
	world.logistics.remove_building(saw.id)
	check(job.state==Job.State.CANCELLED and saw.resources.get_reserved_in(R.LOG)==0 and world.ground_resources.drops[0].reservation_owner_id.is_empty(),"Destination removal cancels owned workflow and releases Ground")
	world.free()
	# Ground-only full construction uses exactly the existing cycle/lifecycle.
	world = scene()
	site = place(world,Types.HOME,Vector3(-12,0,14),false)
	worker = world.resident_runtimes[1]
	world.player_control.assign_profession(worker.data.id,P.BUILDER)
	world.ground_resources.create_drop(R.PLANK,10,world.world_locations.get_position(site.id))
	worker.builder._on_world_changed()
	for cycle in range(3):
		check(world._request_work(worker),"Ground-only construction normal work cycle")
		walk(worker)
		check(worker.builder.phase==Builder.Phase.BUILDING,"Materials arrive before actual construction work")
		world.game_time.debug_skip_minutes(60)
	check(site.is_built() and site.get_delivered_amount(R.PLANK)==10 and world.ground_resources.drops.is_empty() and worker.data.inventory.amount==0,"Ground-only Home completes same instance without duplication")
	world.free()
	print("Self logistics: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
