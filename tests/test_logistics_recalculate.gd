extends SceneTree
## Component fixtures use real claims/executors, with explicit test capacity for 100 jobs.
const Building = preload("res://scripts/building_data.gd")
const Data = preload("res://scripts/resident_data.gd")
const Clock = preload("res://scripts/game_time.gd")
const Intents = preload("res://scripts/resident_intent_controller.gd")
const Ground = preload("res://scripts/ground_resources.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const Job = preload("res://scripts/haul_job.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
class Counted extends "res://scripts/logistics_controller.gd":
	var depth := 0
	var max_depth := 0
	var passes := 0
	var repeated_requests := 0
	var notifications := 0
	func recalculate() -> void:
		depth += 1
		max_depth=maxi(max_depth,depth)
		if _recalculating: repeated_requests += 1
		super.recalculate()
		depth -= 1
	func _validate_active_jobs() -> void:
		passes += 1
		super._validate_active_jobs()
	func reset_counts() -> void:
		max_depth=0
		passes=0
		repeated_requests=0
		notifications=0
class Locations extends RefCounted:
	var buildings: Dictionary
	func get_position(id: StringName) -> Variant:
		var building=buildings.get(id)
		return building.position if building!=null else null
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(quantity: int) -> Dictionary:
	var service:=Counted.new()
	var base=Building.new(&"base","Base",BT.STORAGE)
	base.resources.set_capacity(R.LOG,quantity+5)
	var clock:=Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	clock.total_minutes=420
	var ground:=Ground.new()
	ground.setup(clock)
	service.setup(base,null,null)
	service.sources.bind_ground(ground)
	service.position_provider=func(_id): return Vector2(-50,0)
	var locations:=Locations.new()
	locations.buildings=service._buildings
	service.bind_world(clock,locations)
	var controllers: Array=[]
	var workers: Array=[]
	for index in quantity:
		var worker=Data.new("p%03d"%index,"Porter",30,P.PORTER)
		worker.work_location_id=base.id
		service.register_resident(worker)
		var intents:=Intents.new()
		intents.setup(worker)
		root.add_child(intents)
		service.use_executor(worker,clock,locations,intents,null)
		controllers.append(intents)
		workers.append(worker)
		ground.create_drop(R.LOG,3,Vector2(25+index,0))
	# Avoid a captured strong service reference cycle in the test-only observer.
	service.changed.connect(count_notification.bind(weakref(service)))
	return {"service":service,"base":base,"clock":clock,"ground":ground,"workers":workers,"controllers":controllers}
func count_notification(owner: WeakRef) -> void:
	var service=owner.get_ref()
	if service!=null: service.notifications+=1
func claim_all(f: Dictionary) -> Array:
	var result: Array=[]
	for worker in f.workers:
		var job=f.service.claim_best_job(worker.id)
		check(job!=null,"Real component claim succeeds")
		result.append(job)
	return result
func dispose(f: Dictionary) -> void:
	f.service.unbind_execution()
	for controller in f.controllers: controller.free()
	f.ground.free()
	f.clock.free()
func assert_cleanup(f: Dictionary, expected_amount: int) -> void:
	check(f.service.jobs.is_empty() and f.service._inbound.is_empty() and f.base.resources.get_reserved_in(R.LOG)==0,"No active jobs or inbound promises")
	check(f.ground.drops.all(func(drop): return drop.reservation_owner_id.is_empty()),"All surviving Ground claims released")
	var amount:=0
	for drop in f.ground.drops: amount+=drop.amount
	check(amount+f.base.resources.get_amount(R.LOG)==expected_amount,"Real resource quantities conserved")
	check(not f.service._recalculating and not f.service._recalculate_pending,"Synchronous drain has finished")
func run() -> void:
	var f:=fixture(0)
	f.service.reset_counts()
	f.service.recalculate()
	check(f.service.passes==1 and f.service.notifications==1,"Empty explicit refresh is synchronous")
	f.service.recalculate()
	check(f.service.passes==2 and f.service.notifications==2,"Separate explicit refresh retains notification contract")
	# Pure notification feedback must terminate without a pass-count cutoff.
	var echo: Callable=f.service.recalculate
	f.service.changed.connect(echo)
	f.service.availability_changed.connect(echo)
	f.service.reset_counts()
	f.service.recalculate()
	check(f.service.passes==2 and f.service.notifications==1 and f.service.max_depth==2,"No-change notification feedback is validated once without echoing forever")
	f.service.changed.disconnect(echo)
	f.service.availability_changed.disconnect(echo)
	dispose(f)
	for count in [1,2,10,30,100]:
		var bulk:=fixture(count)
		var committed:=claim_all(bulk)
		bulk.service.reset_counts()
		bulk.service.recalculate()
		check(bulk.service.jobs.size()==count and bulk.service.passes==1,"Valid jobs stay valid")
		var order: Array=[]
		var intermediate: Array=[]
		var cancelled_callback:=func(id):
			order.append(id)
			intermediate.append(bulk.service._inbound.size())
			check(bulk.service.get_job(id)==null,"Cancelled owner's own job already cleaned before notification")
			bulk.service.recalculate()
		bulk.service.job_cancelled.connect(cancelled_callback)
		for drop in bulk.ground.drops.duplicate(): bulk.ground.remove_drop(drop)
		bulk.service.reset_counts()
		bulk.service.recalculate()
		check(order==bulk.workers.map(func(worker): return worker.id),"Approved insertion-order cancellation replaces recursive unwinding")
		check(intermediate[0]==count-1 and intermediate[-1]==0,"Callback may see foreign inbound; outer call drains all")
		check(committed.all(func(job): return job.state==Job.State.CANCELLED),"Every invalid job cancelled exactly once")
		check(bulk.service.max_depth<=2 and bulk.service.passes==2,"Cancellation full passes bounded independent of job count")
		assert_cleanup(bulk,0)
		bulk.service.job_cancelled.disconnect(cancelled_callback)
		dispose(bulk)
	# Callback removes a future job and creates a new job/executor during the pass.
	f=fixture(3)
	var jobs:=claim_all(f)
	var callback_state:={"ran":false,"new_job":null}
	var replacing_callback:=func(_id):
		if callback_state.ran: return
		callback_state.ran=true
		f.service.cancel_job(jobs[1])
		var added=Data.new("late","Late",30,P.PORTER)
		added.work_location_id=f.base.id
		f.service.register_resident(added)
		var intents:=Intents.new()
		intents.setup(added)
		root.add_child(intents)
		f.controllers.append(intents)
		f.service.use_executor(added,f.clock,f.service._locations,intents,null)
		f.ground.create_drop(R.LOG,3,Vector2(100,0))
		callback_state.new_job=f.service.claim_best_job(added.id)
		check(callback_state.new_job!=null,"Callback creates real distinct claimed job")
		# Invalidate that new job too; the next pass must see the new executor.
		f.ground.remove_drop(f.service.sources.resolve(callback_state.new_job.source_ref))
		f.service.recalculate()
	f.service.job_cancelled.connect(replacing_callback)
	f.ground.remove_drop(f.service.sources.resolve(jobs[0].source_ref))
	f.service.reset_counts()
	f.service.recalculate()
	check(jobs[0].state==Job.State.CANCELLED and jobs[1].state==Job.State.CANCELLED and jobs[2].is_active(),"Current/future removal does not skip surviving job")
	check(callback_state.new_job.state==Job.State.CANCELLED and f.service.jobs.size()==1,"New executor is revalidated on pending pass")
	check(f.service.max_depth<=2,"Callback claims/removal never nest full recalculation")
	f.service.job_cancelled.disconnect(replacing_callback)
	f.service.cancel_job(jobs[2])
	assert_cleanup(f,6)
	dispose(f)
	# A notification callback changes actual state after initial validation.
	f=fixture(1)
	jobs=claim_all(f)
	var invalidate_after_validation:=func(): f.ground.remove_drop(f.service.sources.resolve(jobs[0].source_ref)); f.service.recalculate()
	f.service.changed.connect(invalidate_after_validation,CONNECT_ONE_SHOT)
	f.service.recalculate()
	check(jobs[0].state==Job.State.CANCELLED,"Listener mutation is not lost even without immediate source service notification")
	assert_cleanup(f,0)
	dispose(f)
	# Recalculate during a reserve transaction cannot validate half-owned promises.
	f=fixture(1)
	var transaction:={"ran":false,"nested":null}
	var reserve_callback:=func(_resource):
		if transaction.ran: return
		transaction.ran=true
		f.service.recalculate()
		transaction.nested=f.service.claim_best_job(f.workers[0].id)
		f.ground.remove_drop(f.ground.drops[0])
	f.base.resources.reservations_changed.connect(reserve_callback)
	check(f.service.claim_best_job(f.workers[0].id)==null and transaction.nested==null,"Source disappearance and nested claim roll back under claiming guard")
	f.base.resources.reservations_changed.disconnect(reserve_callback)
	assert_cleanup(f,0)
	f.ground.create_drop(R.LOG,3,Vector2(25,0))
	var recovered=f.service.claim_best_job(f.workers[0].id)
	check(recovered!=null,"Next correct transaction works after rollback")
	f.service.cancel_job(recovered)
	assert_cleanup(f,3)
	dispose(f)
	for mutation in ["destination","inbound"]:
		var edge:=fixture(1)
		var state:={"ran":false,"passes_before":edge.service.passes}
		var transaction_callback:=func(_resource):
			if state.ran: return
			state.ran=true
			check(edge.service.passes==state.passes_before,"Claim guard shields intermediate reservation state")
			edge.service.recalculate()
			if mutation=="destination": edge.service.remove_building(edge.base.id)
			else: edge.base.resources.release_in(R.LOG,1)
		edge.base.resources.reservations_changed.connect(transaction_callback)
		check(edge.service.claim_best_job(edge.workers[0].id)==null,"Callback invalidates destination/inbound during real claim")
		edge.base.resources.reservations_changed.disconnect(transaction_callback)
		assert_cleanup(edge,3)
		if mutation=="destination": edge.service.register_building(edge.base)
		var next_job=edge.service.claim_best_job(edge.workers[0].id)
		check(next_job!=null,"Valid claim succeeds after destination/inbound rollback")
		edge.service.cancel_job(next_job)
		dispose(edge)
	# Container source: outbound and inbound are still owned by the same transaction.
	f=fixture(2)
	var kitchen=Building.new(&"kitchen","Kitchen",BT.FOOD)
	kitchen.resources.set_capacity(R.FOOD,1)
	f.service.register_building(kitchen)
	f.base.resources.set_capacity(R.FOOD,3)
	f.base.resources.add(R.FOOD,1)
	var ref:=Source.new(Source.Kind.CONTAINER,f.base.id)
	var container_job=f.service.claim_transport(f.workers[0].id,ref,kitchen,R.FOOD,f.service._can_claim.bind(f.workers[0]),false)
	check(container_job!=null and f.base.resources.get_reserved_out(R.FOOD)==1 and kitchen.resources.get_reserved_in(R.FOOD)==1,"Container import claims reserve exactly one out/in")
	check(f.service.claim_transport(f.workers[1].id,ref,kitchen,R.FOOD,f.service._can_claim.bind(f.workers[1]),false)==null,"Container competition cannot exceed quantity or capacity")
	f.base.definition.logistics_flow[R.FOOD]["export"]=false
	f.service.recalculate()
	check(container_job.state==Job.State.CANCELLED and f.base.resources.get_reserved_out(R.FOOD)==0 and kitchen.resources.get_reserved_in(R.FOOD)==0 and f.base.resources.get_amount(R.FOOD)==1,"Policy invalidation cancels and preserves real Container quantities")
	dispose(f)
	await integration()
	print("Logistics recalculate: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func integration() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate()
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
	var actors: Array=[world.resident_runtimes[0],world.resident_runtimes[3]]
	check(world.player_control.assign_profession(actors[1].data.id,P.PORTER),"Normal PlayerControl assigns second Porter")
	world.ground_resources.create_drop(R.LOG,3,Coordinates.to_sim(Vector3(10,0,22)))
	world.ground_resources.create_drop(R.LOG,3,Coordinates.to_sim(Vector3(11,0,22)))
	world.game_time.total_minutes=419
	for actor in actors: actor.decision._deciding=false
	world.game_time.advance(1.0)
	for frame in 4: await process_frame # Two normal Porter decisions now spend separate frame budgets.
	var committed: Array=[]
	for actor in actors:
		actor.decision._deciding=true
		committed.append(world.logistics.get_job(actor.data.id))
	check(committed.all(func(job): return job!=null and job.state==Job.State.GOING_TO_SOURCE),"Real WORK starts both distinct hauls")
	await physics_frame
	for actor in actors: walk(actor)
	world.game_time.advance(10.0)
	check(actors.all(func(actor): return actor.data.inventory.amount==1),"Both pick up real cargo after normal loading")
	for actor in actors: walk(actor)
	check(actors.any(func(actor): return actor.view._marker!=null) and actors.any(func(actor): return actor.view._waiting),"Existing one-Courier competition: occupied unloading plus waiting Porter")
	var notifications: Array=[]
	var cancel_observer:=func(id):
		var actor=world.get_resident_runtime(world.find_resident(id))
		check(world.logistics.get_job(id)==null and actor.data.inventory.amount==0,"Own cleanup precedes job_cancelled subscriber")
		notifications.append(id)
	world.logistics.job_cancelled.connect(cancel_observer)
	var before: int=actors[0].decision.decision_count+actors[1].decision.decision_count
	world.buildings.erase(world.warehouse_data)
	world.building_uses.unregister(world.warehouse_data.id)
	world.logistics.remove_building(world.warehouse_data.id)
	check(committed.all(func(job): return job.state==Job.State.CANCELLED) and notifications.size()==2,"Occupied/waiting/handling jobs cancelled once")
	check(actors[0].decision.decision_count+actors[1].decision.decision_count==before,"Main job_cancelled subscriber defers decisions until outer operation returns")
	check(world.logistics.jobs.is_empty() and world.logistics._inbound.is_empty() and world.warehouse_data.resources.get_reserved_in(R.LOG)==0,"World removal synchronously drains all inbound/jobs")
	check(actors.all(func(actor): return actor.view._marker==null and not actor.view._waiting and not world.logistics._executors[actor.data.id].handling.is_active()),"Portal/handling/wait cleanup unchanged")
	var total:=0
	for drop in world.ground_resources.drops:
		if drop.resource_type==R.LOG: total+=drop.amount
		check(world.ground_resources.get_by_id(drop.id)==drop and drop.reservation_owner_id.is_empty(),"Cargo drops registered in existing owner index")
	check(total==6,"Pickup and cancellation preserve total LOG without duplication")
	check((world.logistics.current_job==null or not world.logistics.current_job.is_active()),"Canonical presentation has no removed telemetry; domain reports no final job")
	await process_frame
	check(world.logistics.jobs.is_empty(),"Deferred AI callbacks do not resurrect invalid destination jobs")
	world.logistics.job_cancelled.disconnect(cancel_observer)
	world.free()
func walk(actor: Node) -> void:
	for step in 4000:
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
