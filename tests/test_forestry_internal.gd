extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Job = preload("res://scripts/haul_job.gd")
const Skill = preload("res://scripts/skill_type.gd").Type
const Source = preload("res://scripts/resource_source_ref.gd")
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
var world: Node
var actor: Node
var worker: Node
var hut: RefCounted
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> void:
	world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	for resident in world.resident_runtimes:
		resident.decision._deciding=true
		resident.view.set_physics_process(false)
		resident.intents.abort_current(resident.intents.current_intent)
		for need in resident.data.needs.values():
			need.value=0
			need.base_weight=0
	world.game_time.total_minutes=419
	world.game_time.debug_skip_minutes(1)
	actor=world.resident_runtimes[3]
	worker=actor.get_node("Lumberjack")
	hut=preload("res://tests/forestry_fixture.gd").hut(world)
	world.player_control.assign_workplace(actor.data.id,hut.id)
func drop_at(point: Vector3 = Vector3(-24,0,-4)) -> RefCounted:
	return world.ground_resources.create_drop(R.LOG,1,C.to_sim(point))
func start() -> RefCounted:
	actor.decision._deciding=false
	actor.decision.request_decision("forestry_internal_test")
	await preload("res://tests/ai_queue_fixture.gd").drain(world)
	actor.decision._deciding=true
	var job = world.logistics.get_job(actor.data.id)
	check(job!=null and job.admission==Job.Admission.INTERNAL,"Normal WORK owns INTERNAL job")
	return job
func walk() -> void:
	for step in range(3000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func cargo_count() -> int:
	var amount: int = hut.resources.get_amount(R.LOG)+actor.data.inventory.amount
	for drop in world.ground_resources.drops:
		if drop.resource_type==R.LOG: amount += drop.amount
	return amount
func run() -> void:
	fixture()
	check(hut.resources.get_capacity(R.LOG)==Balance.LUMBERJACK_LOG_CAPACITY and Balance.LUMBERJACK_LOG_CAPACITY==12,"Actual unchanged buffer is 12")
	var outside = drop_at(Vector3(10,0,-4))
	var far = drop_at(Vector3(-30,0,-9))
	var close = drop_at()
	var occupied = drop_at(Vector3(-23,0,-4))
	occupied.reserve(&"competitor")
	world.ground_resources.create_drop(R.STONE,1,close.world_position)
	var area = worker._context().area
	var expected: Array = world.logistics.sources.find(R.LOG,actor.view.get_sim_position(),world.world_locations.get_position(hut.id),hut.id,hut,area).filter(func(ref): return ref.kind==Source.Kind.GROUND and area.contains(world.logistics.sources.point(ref)))
	check(worker.has_work() and worker._available_task.kind==&"COLLECT","COLLECT before CHOP")
	check(worker._available_task.reference.id==expected[0].id and worker._available_task.reference.id==close.id,"Same legacy route-distance/stable-ID selection, early LOG/in-area filter")
	var job = await start()
	check(job.source_ref.id==close.id and close.reservation_owner_id==job.id and hut.resources.get_reserved_in(R.LOG)==1,"Owned Ground claim and normal inbound")
	check(worker.kind.is_empty() and actor.intents.current_intent.priority==Balance.WORK_PRIORITY,"No parallel forestry haul state, priority preserved")
	walk()
	world.game_time.debug_skip_minutes(9)
	check(close.amount==1 and actor.data.inventory.amount==0,"Loading needs ten minutes")
	world.game_time.debug_skip_minutes(1)
	check(actor.data.inventory.amount==1 and close not in world.ground_resources.drops,"Pickup transfers exactly once")
	walk()
	check(actor.view._marker!=null and actor.view._marker.purpose==1,"Arrival through portal acquires interior COURIER")
	world.game_time.debug_skip_minutes(9)
	check(hut.resources.get_amount(R.LOG)==0,"Unloading needs ten minutes")
	world.game_time.debug_skip_minutes(1)
	check(job.state==Job.State.COMPLETED and hut.resources.get_amount(R.LOG)==1 and actor.view._marker==null and hut.resources.get_reserved_in(R.LOG)==0,"Deposit, exit, cleanup")
	check(actor.data.get_skill_xp(Skill.GATHERING)==0 and actor.data.get_skill_xp(Skill.LOGISTICS)==0,"COLLECT does not award XP")
	check(outside.reservation_owner_id.is_empty() and far.amount==1,"Other Ground untouched")
	world.free()
	# Assignment/profession changes before and after pickup preserve captured destination.
	for change in ["profession","workplace","FREE","area_edit"]:
		for picked_up in [false,true]:
			fixture()
			var drop = drop_at()
			job=await start()
			if picked_up:
				walk()
				world.game_time.debug_skip_minutes(10)
			match change:
				"profession": world.player_control.assign_profession(actor.data.id,P.NONE)
				"workplace":
					var other = preload("res://tests/forestry_fixture.gd").hut(world,&"other",Vector3(-20,0,4))
					world.player_control.assign_workplace(actor.data.id,other.id)
				"FREE", "area_edit":
					var changed_area = world.work_areas.create(C.to_sim(Vector3(-45,0,25)),C.length_to_sim(15))
					world.player_control.assign_work_area(actor.data.id,changed_area.id)
					if change=="area_edit": changed_area.update(Vector2.ZERO,1.0)
			if not picked_up:
				walk()
				world.game_time.debug_skip_minutes(10)
			walk()
			world.game_time.debug_skip_minutes(10)
			check(job.state==Job.State.COMPLETED and job.destination_location_id==hut.id and hut.resources.get_amount(R.LOG)==1 and cargo_count()==1,"Captured delivery survives %s / picked=%s"%[change,picked_up])
			check(drop.reservation_owner_id.is_empty() and world.logistics.get_job(actor.data.id)==null,"No orphan reservations after captured completion")
			world.free()
	# Forced/critical/ordinary aborts during timed loading, carrying and unloading.
	for cause in ["command","critical","cancel","remove"]:
		for stage in ["loading","carrying","unloading"]:
			fixture()
			drop_at()
			job=await start()
			walk()
			if stage!="loading": world.game_time.debug_skip_minutes(10)
			if stage=="unloading": walk()
			match cause:
				"command": world.player_control.move_to(actor.data.id,C.to_sim(Vector3(0,0,-10)))
				"critical":
					actor.decision._deciding=false
					actor.data.fatigue=100
					actor.decision._deciding=true
				"cancel": actor.intents.cancel_current(actor.intents.current_intent)
				"remove": world.logistics.remove_building(hut.id)
			check(job.state==Job.State.CANCELLED and hut.resources.get_reserved_in(R.LOG)==0 and world.logistics.get_job(actor.data.id)==null,"Cancel cleanup %s/%s"%[cause,stage])
			check(cargo_count()==1 and actor.data.inventory.amount==0 and actor.view._marker==null,"No lost/duplicated cargo or occupied slot %s/%s"%[cause,stage])
			for drop in world.ground_resources.drops: check(world.navigation.is_world_walkable(C.to_world(drop.world_position)),"Cancelled Ground on walkable plane")
			world.free()
	fixture()
	var expiring = drop_at()
	job=await start()
	world.ground_resources._on_minute(expiring.created_at+expiring.lifetime)
	world.logistics.recalculate()
	check(job.state==Job.State.CANCELLED and hut.resources.get_reserved_in(R.LOG)==0 and expiring.reservation_owner_id.is_empty(),"Expiry before pickup cleans promises")
	world.free()
	fixture()
	drop_at()
	job=await start()
	world.game_time.total_minutes=1019
	world.game_time.debug_skip_minutes(1)
	walk()
	world.game_time.debug_skip_minutes(10)
	walk()
	world.game_time.debug_skip_minutes(10)
	check(job.state==Job.State.COMPLETED and hut.resources.get_amount(R.LOG)==1 and not worker.request_work(),"Committed collect finishes after17, no new work")
	world.free()
	# Same-frame assignment/revision changes invalidate unclaimed availability.
	fixture()
	drop_at()
	check(worker.has_work(),"Availability before reassignment")
	var region = world.work_areas.create(C.to_sim(Vector3(55,0,25)),1.0)
	world.player_control.assign_work_area(actor.data.id,region.id)
	region.update(C.to_sim(Vector3(50,0,25)),1.0)
	check(not worker.request_work() and world.logistics.get_job(actor.data.id)==null,"Same-frame FREE area revision cannot use old COLLECT")
	world.free()
	# Last inbound and competing Porter claim remain common reservations.
	fixture()
	var common = drop_at()
	hut.resources.add(R.LOG,11)
	job=await start()
	check(hut.resources.get_available_free_capacity(R.LOG)==0,"Collect owns last inbound room")
	var porter=world.resident_runtimes[0]
	world.player_control.assign_workplace(porter.data.id,world.warehouse_data.id)
	porter.view.global_position=C.to_world(common.world_position)+Vector3(1,0,0) # Last-resource competition within resident circle.
	check(not world.logistics.collect_candidates(porter.data.id).any(func(row): return row.source_ref.id==common.id),"Porter cannot claim owned Ground")
	world.logistics._executors[actor.data.id].cancel("competition")
	check(world.logistics.collect_candidates(porter.data.id).any(func(row): return row.source_ref.id==common.id),"Cancellation releases Ground for Porter")
	hut.resources.add(R.LOG,1)
	check(worker.best_task().get("kind")!=&"COLLECT" and worker.best_target().is_empty(),"Full buffer rejects COLLECT and CHOP")
	world.free()
	# Reentrant portal entry/exit and resource callbacks at timed operation boundaries.
	for edge in ["entry","exit","pickup_callback","deposit_callback","before_loading_tick","before_unloading_tick"]:
		fixture()
		drop_at()
		job=await start()
		var move_command := func(): world.player_control.move_to(actor.data.id,C.to_sim(Vector3(0,0,-10)))
		var portal_callback := func(id: StringName, purpose: int):
			if id!=hut.id or purpose!=1: return
			var inside: bool = world.building_uses.occupied_by(id,actor.data.id,1)
			if (edge=="entry" and inside) or (edge=="exit" and not inside): move_command.call()
		var pickup_callback := func(drop):
			if drop.resource_type==R.LOG: move_command.call()
		var deposit_callback := func(resource: int, _amount: int):
			if resource==R.LOG: move_command.call()
		walk()
		if edge=="pickup_callback": world.ground_resources.removed.connect(pickup_callback)
		if edge=="before_loading_tick":
			world.game_time.debug_skip_minutes(9)
			move_command.call()
			world.game_time.debug_skip_minutes(1)
		else: world.game_time.debug_skip_minutes(10)
		if edge=="pickup_callback": world.ground_resources.removed.disconnect(pickup_callback)
		if edge in ["entry","exit"]: world.building_uses.slots_changed.connect(portal_callback)
		if job.is_active(): walk()
		if edge=="deposit_callback": hut.resources.changed.connect(deposit_callback)
		if edge=="before_unloading_tick":
			world.game_time.debug_skip_minutes(9)
			move_command.call()
			world.game_time.debug_skip_minutes(1)
		elif job.is_active(): world.game_time.debug_skip_minutes(10)
		if edge=="deposit_callback": hut.resources.changed.disconnect(deposit_callback)
		if edge in ["entry","exit"]: world.building_uses.slots_changed.disconnect(portal_callback)
		var delivered: bool = edge in ["exit","deposit_callback"]
		check(job.state==(Job.State.COMPLETED if delivered else Job.State.CANCELLED),"Deterministic completion/cancel edge %s"%edge)
		check(cargo_count()==1 and hut.resources.get_reserved_in(R.LOG)==0 and world.logistics.get_job(actor.data.id)==null and actor.view._marker==null,"No duplicate cargo/reservation/slot at %s"%edge)
		world.free()
	# After completion, ordinary decision lifecycle may choose new work, never a linked delivery.
	fixture()
	drop_at()
	job=await start()
	walk()
	world.game_time.debug_skip_minutes(10)
	walk()
	var decisions_before: int = actor.decision.decision_count
	actor.decision._deciding=false
	world.game_time.debug_skip_minutes(10)
	await preload("res://tests/ai_queue_fixture.gd").drain(world)
	actor.decision._deciding=true
	check(job.state==Job.State.COMPLETED and actor.decision.decision_count>decisions_before,"Delivery completion returns to ordinary AI")
	check(worker.kind==&"CHOP" and worker.tree!=null,"Ordinary next decision chooses forestry CHOP")
	world.free()
	print("Forestry internal: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
