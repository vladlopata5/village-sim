extends SceneTree
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
	logistics.recalculate()
	var first = logistics.current_job
	check(first.state == Job.State.RESERVED and first.assigned_resident_id.is_empty(), "Creation never assigns or starts a job")
	check(is_equal_approx(first.priority, 8800.0), "Empty kitchen has higher internal urgency")
	var unqualified = Data.new("none", "None", 30)
	logistics.register_resident(unqualified)
	check(logistics.claim_best_job(unqualified.id) == null and logistics.claim_best_job("missing") == null, "Only registered eligible porters claim")
	worker.work_location_id = &"elsewhere"
	check(logistics.claim_best_job(worker.id) == null, "Wrong workplace is ineligible")
	worker.work_location_id = source.id
	# Simulate a competing caller in a test, without adding any game resident.
	var competing = porter("b")
	logistics.register_resident(competing)
	var competing_result = [null]
	logistics.changed.connect(func(): competing_result[0] = logistics.claim_best_job(competing.id), CONNECT_ONE_SHOT)
	check(logistics.claim_best_job(worker.id) == first, "Explicit claim returns the reserved job")
	check(competing_result[0] == null and first.assigned_resident_id == worker.id and first.state == Job.State.ASSIGNED, "Assignment is visible before callbacks; two callers cannot claim same job")
	check(source.resources.get_reserved_out(FOOD) == 1 and destination.resources.get_reserved_in(FOOD) == 1, "Claim does not reserve twice")
	check(logistics.claim_best_job(worker.id) == null, "Busy worker cannot claim another job")
	logistics.cancel_job(first)
	logistics.recalculate()
	# Three actual reserved promises exercise maximum priority and stable ID tie-break.
	for id in [&"aaa_z", &"aaa_a"]:
		check(source.resources.reserve_out(FOOD, 1) and destination.resources.reserve_in(FOOD, 1), "Test jobs own both promises")
		logistics.jobs.append(Job.new(id, source.id, destination.id, FOOD, 1, 900))
	var chosen = logistics.claim_best_job(worker.id)
	check(chosen.id == &"aaa_a" and is_equal_approx(chosen.priority, 4400.0), "Dynamic shared route urgency, lexical ID tie-break")
	check(source.resources.get_reserved_out(FOOD) == 3 and destination.resources.get_reserved_in(FOOD) == 3, "Priority selection leaves promises unchanged")
	for job in logistics.jobs.duplicate(): logistics.cancel_job(job)
	destination.resources.add(FOOD, 2)
	logistics.recalculate()
	check(is_equal_approx(logistics.current_job.priority, 4400.0), "Smaller deficit gives lower internal urgency")
	# Real game: job execution happens only through the decision point.
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	var r = scene.resident_runtimes[0]
	r.view.set_process(false)
	for need in r.data.needs.values(): need.value = 0
	var offered = scene.logistics.current_job
	check(offered.assigned_resident_id.is_empty(), "Morning offer is not assigned to Stepan")
	scene.game_time.debug_next_phase()
	check(offered.state == Job.State.GOING_TO_SOURCE and offered.assigned_resident_id == r.data.id, "At daytime decision porter claims and executes")
	r.data.hunger = 80
	check(r.intents.current_intent.reason_id == &"haul_source" and offered.state == Job.State.GOING_TO_SOURCE, "Ordinary hunger 8000 does not interrupt already-started source route")
	r.view._process(20)
	check(offered.state == Job.State.GOING_TO_DESTINATION, "Pickup continues same job")
	r.view._process(20)
	check(offered.state == Job.State.COMPLETED and r.data.activity == Activity.EATING, "At delivery boundary hunger 8000 beats work 7000")
	check(scene.logistics.current_job.state == Job.State.RESERVED and scene.logistics.current_job.assigned_resident_id.is_empty(), "Next delivery remains unclaimed while eating")
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
	check(r.data.activity == Activity.SLEEPING and claimed_job[0].state == Job.State.CANCELLED and released_at_cancel[0] and scene.logistics.current_job.assigned_resident_id.is_empty(), "Critical during work callback stops claim execution without lost cleanup or idle overwrite")
	scene.free()
	print("Claim jobs checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
