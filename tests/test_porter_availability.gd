extends SceneTree
## Read-only existence probes must not change the subsequent exact, fresh claim.
const Ref = preload("res://tests/porter_exhaustive_reference.gd")
const Building = preload("res://scripts/building_data.gd")
const Data = preload("res://scripts/resident_data.gd")
const Ground = preload("res://scripts/ground_resources.gd")
const Drop = preload("res://scripts/ground_resource.gd")
const BT = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const Job = preload("res://scripts/haul_job.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
class Counted extends "res://scripts/logistics_controller.gd":
	var pools := 0
	var scores := 0
	var rankings := 0
	func _cheap_candidates(id: String) -> Array:
		pools += 1
		return super._cheap_candidates(id)
	func _get_personal_delivery_modifier(worker: ResidentData, candidate: Candidate) -> float:
		scores += 1
		return super._get_personal_delivery_modifier(worker,candidate)
	func _first_reachable(id: String, candidates: Array, attempted: Dictionary = {}) -> Candidate:
		rankings += 1
		return super._first_reachable(id,candidates,attempted)
class RejectFirst extends Counted:
	var rejected := false
	func _claim_candidate(worker: ResidentData, candidate: Candidate) -> HaulJob:
		if not rejected:
			rejected = true
			sources.ground.remove_drop(sources.resolve(candidate.source_ref))
		return super._claim_candidate(worker,candidate)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(service: Counted = null) -> Dictionary:
	if service == null: service = Counted.new()
	var base = Building.new(&"base","Base",BT.STORAGE)
	var worker = Data.new("porter","Porter",30,P.PORTER)
	worker.work_location_id = base.id
	for resource in R.values(): base.resources.set_capacity(resource,500)
	service.setup(base,null,worker)
	service.position_provider = func(_id): return Vector2(-50,0)
	var ground := Ground.new()
	service.sources.ground = ground
	return {"service":service,"base":base,"worker":worker,"ground":ground}
func drop(f: Dictionary, id: StringName, resource: int = R.LOG, point: Vector2 = Vector2(25,0)):
	var value := Drop.new(resource,3,point,0)
	value.id = id
	check(f.ground.register_drop(value),"Fixture registers existing quantity >1")
	return value
func reference(f: Dictionary):
	var old := Ref.new()
	old.setup(f.base,null,f.worker)
	for building in f.service._buildings.values(): old.register_building(building)
	old.position_provider = f.service.position_provider
	old.sources.ground = f.ground
	old.sources.route_available = f.service.sources.route_available
	old.bind_world(f.service._clock,f.service._locations)
	return old
func verify_claim(f: Dictionary, label: String) -> void:
	var old = reference(f)
	var expected = old._best(old.collect_candidates(f.worker.id))
	check(f.service.has_available_job(f.worker.id)==(expected!=null),label+": boolean exhaustive equivalence")
	check(f.service.jobs.is_empty() and f.service._inbound.is_empty() and f.ground.drops.all(func(d): return d.reservation_owner_id.is_empty()),label+": probe is read-only")
	var actual = f.service.claim_best_job(f.worker.id)
	check((actual==null)==(expected==null),label+": actual production claim presence")
	if actual!=null and expected!=null:
		check(actual.source_ref.stable_key()==expected.source_ref.stable_key() and actual.destination_location_id==expected.destination.id and actual.resource_type==expected.resource_type and actual.priority==expected.porter_score,label+": exact claimed identity and score")
		check(f.service.cancel_job(actual),label+": cleanup owned promises")
	f.ground.free()
func run() -> void:
	for count in [100,300]:
		var bulk_fixture := fixture()
		for index in count: drop(bulk_fixture,StringName("ground_%d"%index))
		var service: Counted = bulk_fixture.service
		check(service.has_available_job(bulk_fixture.worker.id),"Large pool has work")
		check(service.scores==1 and service.pools==0 and service.rankings==0,"Probe stops at one score, no full pool or sort")
		verify_claim(bulk_fixture,"large/tied pool %d"%count)
	var f := fixture()
	drop(f,&"ground_2")
	drop(f,&"ground_10")
	check(f.service.has_available_job(f.worker.id),"Tie probe")
	var job = f.service.claim_best_job(f.worker.id)
	check(job.source_ref.id==&"ground_10","Claim uses ranked key, not first enumerated probe")
	f.service.cancel_job(job)
	var second = Data.new("second","Second",30,P.PORTER)
	second.work_location_id=f.base.id
	f.service.register_resident(second)
	check(f.service.has_available_job(f.worker.id) and f.service.has_available_job(second.id),"Two read-only probes share availability")
	job=f.service.claim_best_job(second.id)
	var other=f.service.claim_best_job(f.worker.id)
	check(job.source_ref.id!=other.source_ref.id and f.service.jobs.size()==2,"Fresh competing claims remain exclusive even for quantity >1")
	for active in f.service.jobs.duplicate(): f.service.cancel_job(active)
	f.ground.free()
	# Every change is read afresh: no frame/minute-lived candidate cache exists.
	for mutation in ["remove","pickup","expire","capacity","inbound","building","profession","workplace","position","navigation","create","cancel"]:
		f=fixture()
		var mutation_drop=drop(f,&"original")
		check(f.service.has_available_job(f.worker.id),mutation+": initial probe")
		match mutation:
			"remove": f.ground.remove_drop(mutation_drop)
			"pickup":
				mutation_drop.amount=1
				mutation_drop.reserve(&"other_worker")
				f.ground.take_reserved(mutation_drop,&"other_worker")
			"expire": f.ground._on_minute(mutation_drop.created_at+mutation_drop.lifetime)
			"capacity": f.base.resources.set_capacity(R.LOG,0)
			"inbound": f.base.resources.reserve_in(R.LOG,500)
			"building": f.service.remove_building(f.base.id)
			"profession": f.worker.profession=P.GATHERER
			"workplace": f.worker.work_location_id=&"missing"
			"position": f.service.position_provider=func(_id): return Vector2(NAN,0)
			"navigation": f.service.sources.route_available=func(_a,_b): return false
			"create":
				f.ground.remove_drop(mutation_drop)
				check(not f.service.has_available_job(f.worker.id),"Empty probe before newly created source")
				drop(f,&"new",R.STONE)
			"cancel":
				job=f.service.claim_best_job(f.worker.id)
				check(not f.service.has_available_job(f.worker.id),"Active job blocks new work")
				f.service.cancel_job(job)
		job=f.service.claim_best_job(f.worker.id)
		check((job!=null)==(mutation in ["create","cancel"]),mutation+": no stale result at claim")
		if job!=null: f.service.cancel_job(job)
		check(f.service._inbound.is_empty() and f.service.jobs.is_empty(),mutation+": no leaked jobs/promises")
		f.ground.free()
	f=fixture(RejectFirst.new())
	drop(f,&"first")
	drop(f,&"second",R.LOG,Vector2(30,0))
	check(f.service.has_available_job(f.worker.id),"Probe before rejected claim")
	job=f.service.claim_best_job(f.worker.id)
	check(job!=null and job.source_ref.id==&"second","Failed claim retains normal fresh retry")
	f.service.cancel_job(job)
	f.ground.free()
	# Synchronous reserve callbacks may delete a source and try to claim again.
	f=fixture()
	var loose=drop(f,&"reentrant")
	var callback_state := {"ran":false,"nested":null}
	var reservation_callback := func(_resource):
		if callback_state.ran: return
		callback_state.ran=true
		f.ground.remove_drop(loose)
		callback_state.nested=f.service.claim_best_job(f.worker.id)
	f.base.resources.reservations_changed.connect(reservation_callback)
	check(f.service.has_available_job(f.worker.id),"Reentrant initial probe")
	check(f.service.claim_best_job(f.worker.id)==null and callback_state.ran and callback_state.nested==null,"Transaction revalidation rejects missing source/nested claim")
	check(f.service._inbound.is_empty() and f.base.resources.get_reserved_in(R.LOG)==0 and f.service.jobs.is_empty(),"Reentrant rollback preserves ledgers")
	f.base.resources.reservations_changed.disconnect(reservation_callback)
	f.ground.free()
	# Random mixed import/export/ground states: test probe AND actual claimed job.
	var rng := RandomNumberGenerator.new()
	rng.seed=741923
	for iteration in 250:
		f=fixture()
		f.base.position=Vector2(rng.randf_range(-500,500),rng.randf_range(-500,500))
		f.base.logistics_weight=rng.randi_range(0,250)
		for resource in R.values():
			var capacity:=rng.randi_range(1,30)
			f.base.resources.set_capacity(resource,capacity)
			f.base.resources.add(resource,rng.randi_range(0,capacity))
			f.base.resources.reserve_out(resource,rng.randi_range(0,f.base.resources.get_amount(resource)))
			f.base.resources.reserve_in(resource,rng.randi_range(0,f.base.resources.get_available_free_capacity(resource)))
		for index in 8:
			var building=Building.new(StringName("b%d"%index),"Building",[BT.FOOD,BT.GATHERER_HUT,BT.SAWMILL,BT.QUARRY][index%4])
			building.position=Vector2(rng.randf_range(-900,900),rng.randf_range(-900,900))
			building.logistics_weight=rng.randi_range(0,250)
			for resource in R.values(): building.resources.add(resource,rng.randi_range(0,building.resources.get_capacity(resource)))
			f.service.register_building(building)
			drop(f,StringName("g%d"%index),R.values()[rng.randi_range(0,R.size()-1)],Vector2(rng.randf_range(-900,900),rng.randf_range(-900,900)))
		var cutoff:=rng.randf_range(-800,800)
		f.service.sources.route_available=func(a,b): return a.x>cutoff and b.x>cutoff
		verify_claim(f,"random production %d"%iteration)
	await integration()
	print("Porter availability: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func integration() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	world.logistics=Counted.new()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for quiet_actor in world.resident_runtimes:
		quiet_actor.decision._deciding=true
		quiet_actor.view.set_physics_process(false)
		quiet_actor.intents.abort_current(quiet_actor.intents.current_intent)
		for need in quiet_actor.data.needs.values():
			need.value=0
			need.base_weight=0
	var actor=world.resident_runtimes[0]
	world.ground_resources.create_drop(R.LOG,3,C.to_sim(Vector3(10,0,17)))
	var f={"service":world.logistics,"base":world.warehouse_data,"worker":actor.data,"ground":world.ground_resources}
	var old=reference(f)
	var expected=old._best(old.collect_candidates(actor.data.id))
	check(expected!=null,"Canonical world has exhaustive work")
	var pools: int=world.logistics.pools
	actor.decision._deciding=false
	world.game_time.total_minutes=419
	world.game_time.advance(1.0)
	check(world.logistics.get_job(actor.data.id)==null,"WORK request is queued before claim")
	for frame in 3: await process_frame
	var job=world.logistics.get_job(actor.data.id)
	check(job!=null and job.state==Job.State.GOING_TO_SOURCE,"Normal 07:00 WORK decision starts real haul")
	check(world.logistics.pools-pools==1,"Real decision builds full pool only for claim")
	if job!=null and expected!=null:
		check(job.source_ref.stable_key()==expected.source_ref.stable_key() and job.destination_location_id==expected.destination.id and job.priority==expected.porter_score,"Canonical decision claims exact exhaustive winner")
		actor.decision._deciding=true
		await physics_frame
		walk(actor)
		world.game_time.advance(10.0)
		check(actor.data.inventory.amount==1,"Real physical pickup/handling")
		walk(actor)
		world.game_time.advance(10.0)
		check(job.state==Job.State.COMPLETED and actor.data.inventory.amount==0,"Real delivery and empty cargo")
		check(world.logistics.get_job(actor.data.id)==null,"Delivery releases active ownership")
		check(world.logistics.has_available_job(actor.data.id),"Work probe before real PlayerCommand")
		check(world.player_control.move_to(actor.data.id,C.to_sim(Vector3(10,0,17))),"PlayerCommand accepted between probe and claim")
		check(not world.logistics.has_available_job(actor.data.id) and world.logistics.claim_best_job(actor.data.id)==null,"Player-controlled resident cannot claim stale work")
		actor.commands.cancel_current()
		check(world.logistics.has_available_job(actor.data.id),"Availability restored after command cleanup")
	world.free()
func walk(actor: Node) -> void:
	for step in 4000:
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
