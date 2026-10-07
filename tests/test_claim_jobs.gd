extends SceneTree
const Seed = preload("res://tests/utility_test_seed.gd")
const Logistics = preload("res://scripts/logistics_controller.gd")
const Job = preload("res://scripts/haul_job.gd")
const Data = preload("res://scripts/resident_data.gd")
const Building = preload("res://scripts/building_data.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const NeedType = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func porter(id: String):
	var data = Data.new(id, id, 30, Profession.PORTER)
	data.work_location_id = &"warehouse_01"
	return data
func _run():
	var source = Building.new(&"warehouse_01", "Warehouse", BT.STORAGE)
	var destination = Building.new(&"communal_kitchen_01", "Kitchen", BT.FOOD)
	source.resources.set_capacity(FOOD, 20)
	source.resources.add(FOOD, 10)
	destination.resources.set_capacity(FOOD, 5)
	var worker = porter("a")
	var logistics = Logistics.new()
	logistics.setup(source, destination, worker)
	logistics.position_provider = func(_id): return Vector2.ZERO
	logistics.recalculate()
	check(logistics.jobs.is_empty() and source.resources.get_reserved_out(FOOD) == 0, "No free jobs or reservations before work decision")
	var unqualified = Data.new("none", "None", 30)
	logistics.register_resident(unqualified)
	check(logistics.claim_best_job(unqualified.id) == null and logistics.claim_best_job("missing") == null, "Only registered eligible porters claim")
	worker.work_location_id = &"elsewhere"
	check(logistics.claim_best_job(worker.id) == null, "Wrong workplace is ineligible")
	worker.work_location_id = source.id
	var first = logistics.claim_best_job(worker.id)
	check(first.state == Job.State.ASSIGNED and first.assigned_resident_id == worker.id and is_equal_approx(first.priority, 11000), "Claim creates owned job using preclaim current urgency")
	var competing = porter("b")
	logistics.register_resident(competing)
	var second = logistics.claim_best_job(competing.id)
	check(second != first and second.assigned_resident_id == competing.id and is_equal_approx(second.priority, 8800), "Second porter sees first promise and owns another delivery")
	check(source.resources.get_reserved_out(FOOD) == 2 and destination.resources.get_reserved_in(FOOD) == 2, "Each successful claim reserves once")
	check(logistics.claim_best_job(worker.id) == null, "Busy worker cannot claim another job")
	for active in logistics.jobs.duplicate(): logistics.cancel_job(active)
	destination.resources.add(FOOD, 2)
	check(is_equal_approx(logistics.collect_candidates(worker.id)[0].world_urgency, 6600), "Smaller current deficit reduces urgency")
	# Real game: job execution happens only through the decision point.
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	var r = scene.resident_runtimes[0]
	r.view.set_process(false)
	for need in r.data.needs.values(): need.value = 0
	check(scene.logistics.current_job == null, "Morning has no free offer")
	scene.game_time.debug_next_phase()
	var offered = scene.logistics.current_job
	check(offered.state == Job.State.GOING_TO_SOURCE and offered.assigned_resident_id == r.data.id, "At daytime decision porter claims and executes")
	r.data.hunger = 90
	check(r.intents.current_intent.reason_id == &"haul_source" and offered.state == Job.State.GOING_TO_SOURCE, "Ordinary hunger 90 does not interrupt already-started source route")
	r.view._process(20)
	check(offered.state == Job.State.GOING_TO_DESTINATION, "Pickup continues same job")
	r.decision.rng.seed = Seed.for_action([{"id": "WORK", "priority": 7000}, {"id": "EAT", "priority": preload("res://scripts/action_utility.gd").eat(90)}], "EAT")
	r.view._process(20)
	check(offered.state == Job.State.COMPLETED and r.data.activity == Activity.EATING, "At delivery boundary seeded selector chooses hunger before next work")
	check(scene.logistics.jobs.is_empty() and offered.state == Job.State.COMPLETED, "Next delivery remains unclaimed while eating")
	print("Decision proof: ordinary hunger preserves current haul; after delivery hunger >7000 wins before next claim")
	scene.game_time.debug_skip_minutes(30)
	check(r.intents.current_intent.reason_id == &"haul_source", "After eating a new decision claims next job")
	# No task means personal need below 7000 or an idle segment, never fake work.
	r.view._process(20)
	r.view._process(20)
	r.view._process(20)
	r.view._process(20)
	for need in r.data.needs.values(): need.value = 0
	r.intents.cancel_current(r.intents.current_intent)
	var availability = r.decision.work_available
	r.decision.work_available = func(): return false
	for job in scene.logistics.jobs.duplicate(): scene.logistics.cancel_job(job)
	while scene.kitchen_data.resources.get_amount(FOOD) < 20: scene.kitchen_data.resources.add(FOOD, 1)
	r.decision.work_available = availability
	r.decision.request_decision()
	check(r.data.activity == Activity.IDLE and not r.intents.has_current_action(), "No job and no need: idle, no placeholder work")
	var count: int = r.decision.decision_count
	scene.game_time.debug_skip_minutes(10)
	check(r.decision.decision_count > count, "Idle retries at next ten-minute point")
	r.data.get_need(NeedType.LEISURE).value = 50
	r.decision.request_decision()
	check(r.data.activity == Activity.RELAXING, "No job permits a personal need below 7000")
	scene.free()
	# Cancellation releases promises before the worker receives a new decision.
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	r = scene.resident_runtimes[0]
	r.view.set_process(false)
	for need in r.data.needs.values(): need.value = 0
	scene.game_time.debug_next_phase()
	var cancelled = scene.logistics.current_job
	count = r.decision.decision_count
	check(scene.logistics.cancel_job(cancelled) and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0, "Cancellation releases both promises before redecision")
	await process_frame
	check(r.decision.decision_count > count and scene.logistics.current_job != cancelled and scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE, "Cancelled job gives worker a fresh decision before another claim")
	scene.free()
	# A critical change inside a synchronous claim callback must win after cleanup.
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	r = scene.resident_runtimes[0]
	r.view.set_process(false)
	for need in r.data.needs.values(): need.value = 0
	var original_request = r.decision.work_request
	var worker_runtime = r
	var claimed_job = [null]
	var released_at_cancel = [false]
	scene.logistics.job_cancelled.connect(func(_id): released_at_cancel[0] = scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0)
	r.decision.work_request = func():
		var started = original_request.call()
		claimed_job[0] = scene.logistics.current_job
		worker_runtime.data.fatigue = 100
		return started
	scene.game_time.debug_next_phase()
	check(r.data.activity == Activity.SLEEPING and claimed_job[0].state == Job.State.CANCELLED and released_at_cancel[0] and scene.logistics.jobs.is_empty(), "Critical during work callback stops claim execution without lost cleanup or idle overwrite")
	scene.free()
	print("Claim jobs checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
