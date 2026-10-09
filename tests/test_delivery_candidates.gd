extends SceneTree
const Logistics = preload("res://scripts/logistics_controller.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Job = preload("res://scripts/haul_job.gd")
const Building = preload("res://scripts/building_data.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const RT = preload("res://scripts/resource_type.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const EventLog = preload("res://scripts/game_logger.gd")
class RejectIncoming extends "res://scripts/resource_container.gd":
	func reserve_in(_resource: int, _amount: int) -> bool: return false
class StaleOnce extends "res://scripts/logistics_controller.gd":
	var stale := false
	func _claim_candidate(worker: ResidentData, candidate: Candidate) -> HaulJob:
		if not stale:
			stale = true
			candidate.destination.resources.reserve_in(FOOD, candidate.destination.resources.get_available_free_capacity(FOOD))
		return super._claim_candidate(worker, candidate)
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func building(id: StringName, type: int, position: Vector2, stock: int = 0, capacity: int = 20):
	var result = Building.new(id, String(id), type)
	result.position = position
	result.resources.set_capacity(RT.FOOD, capacity)
	if stock > 0: result.resources.add(RT.FOOD, stock)
	return result
func fixture(service: RefCounted = Logistics.new()) -> Dictionary:
	var source = building(&"warehouse", BT.STORAGE, Vector2.ZERO, 10)
	var target = building(&"kitchen", BT.FOOD, Vector2(300, 0))
	var worker = Data.new("porter", "Степан", 30, Profession.PORTER)
	worker.work_location_id = source.id
	service.setup(source, target, worker)
	service.position_provider = func(_id): return Vector2(-300, 0)
	return {"service": service, "source": source, "target": target, "worker": worker}
func simulation():
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_logger.console_enabled = false
	scene.game_time.set_process(false)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.wander.target_provider = Callable()
		for need in runtime.data.needs.values():
			need.value = 0
			need.base_weight = 0
	return scene
func _run() -> void:
	var f = fixture()
	for _repeat in range(10): f.service.recalculate()
	check(f.service.jobs.is_empty() and f.service.current_job == null, "World refresh never creates free jobs")
	check(f.source.resources.get_reserved_out(RT.FOOD) == 0 and f.target.resources.get_reserved_in(RT.FOOD) == 0, "No speculative reservations")
	check(f.service.has_available_job(f.worker.id) and f.service.jobs.is_empty(), "Availability probe does not create candidates/jobs")
	var candidates = f.service.collect_candidates(f.worker.id)
	var candidate = candidates[0]
	check(candidates.size() == 1 and candidate is Candidate and not candidate is Job, "Delivery candidate is transient data")
	check(candidate.source == f.source and candidate.destination == f.target and candidate.resource_type == RT.FOOD and candidate.amount == 1, "Concrete pair and one unit")
	check(is_equal_approx(candidate.route_distance, 600) and is_equal_approx(candidate.distance_penalty, 1000), "Full route and quadratic penalty")
	check(is_equal_approx(candidate.world_urgency, 11000) and is_equal_approx(candidate.porter_score, 10000), "Current import urgency minus penalty")
	check(f.service._get_personal_delivery_modifier(f.worker, candidate) == 0, "Personal extension hook currently zero")
	check(f.service._pairs().all(func(pair): return pair.source != pair.destination), "No same-building delivery")
	f.source.resources.reserve_out(RT.FOOD, 10)
	check(f.service.collect_candidates(f.worker.id).is_empty(), "All source stock reserved: unavailable")
	f.source.resources.release_out(RT.FOOD, 10)
	f.target.resources.reserve_in(RT.FOOD, 10)
	check(is_equal_approx(f.service.collect_candidates(f.worker.id)[0].world_urgency, 5500), "Incoming reservations reduce projected urgency")
	f.target.resources.reserve_in(RT.FOOD, 10)
	check(f.service.collect_candidates(f.worker.id).is_empty(), "No uncovered destination capacity")
	f.target.resources.release_in(RT.FOOD, 20)
	f.target.resources.set_allowed_resource_types([RT.PLANK])
	check(f.service.collect_candidates(f.worker.id).is_empty(), "Resource not accepted: no candidate")
	f.target.resources.set_allowed_resource_types([RT.FOOD])
	f.target.resources.add(RT.FOOD, 20)
	check(f.service.collect_candidates(f.worker.id).is_empty(), "Full destination: no import")
	f.target.resources.try_take(RT.FOOD, 20)
	var site = Instance.new(&"site", Definition.for_type(BT.FOOD), Vector2.ZERO, Instance.State.UNDER_CONSTRUCTION)
	site.resources.set_capacity(RT.FOOD, 20)
	f.service.add_kitchen(site)
	check(f.service.collect_candidates(f.worker.id).size() == 1, "Construction destination excluded")
	var source_site = Instance.new(&"source_site", Definition.for_type(BT.STORAGE), Vector2.ZERO, Instance.State.UNDER_CONSTRUCTION)
	source_site.resources.set_capacity(RT.FOOD, 20)
	source_site.resources.add(RT.FOOD, 10)
	f.service.add_warehouse(source_site)
	check(f.service.collect_candidates(f.worker.id).size() == 1, "Construction source excluded")
	f.source.resources.set_capacity(RT.PLANK, 50)
	f.source.resources.add(RT.PLANK, 50)
	check(f.service.collect_candidates(f.worker.id).all(func(c): return c.resource_type == RT.FOOD), "Builder PLANK not offered to porters")
	# Calibration is independent from the normal WORK/Need comparison.
	for row in [[7000.0, 300.0, 6750.0], [7000.0, 600.0, 6000.0], [4000.0, 600.0, 3000.0], [8000.0, 600.0, 7000.0], [10000.0, 1200.0, 6000.0], [6000.0, 300.0, 5750.0]]:
		var score: float = row[0] - f.service.distance_penalty(row[1])
		check(is_equal_approx(score, row[2]), "Calibration urgency=%s distance=%s score=%s" % row)
		print("Calibration: urgency=%.0f distance=%.0f score=%.0f" % [row[0], row[1], score])
	check(is_equal_approx(f.service.distance_penalty(1200), 4 * f.service.distance_penalty(600)), "Distance penalty quadratic")
	check(Balance.WORK_PRIORITY == 7000, "Site/delivery score does not replace WORK utility")
	# Own storage restriction precedes scoring; stable route tie-break remains unchanged.
	f = fixture()
	f.service.position_provider = func(_id): return Vector2.ZERO
	var nearer = building(&"warehouse_z", BT.STORAGE, Vector2(150, 0), 10)
	f.source.position = Vector2(-100, 0)
	f.service.add_warehouse(nearer)
	var selected = f.service.claim_best_job(f.worker.id)
	check(selected.source_location_id == f.source.id, "Other storage cannot beat own base regardless of route score")
	check(selected.assigned_resident_id == f.worker.id and selected.state == Job.State.ASSIGNED, "Job born already assigned after successful claim")
	check(f.service.jobs.size() == 1 and f.source.resources.get_reserved_out(RT.FOOD) == 1 and f.target.resources.get_reserved_in(RT.FOOD) == 1, "Claim owns both reservations once")
	check(f.service.claim_best_job(f.worker.id) == null, "One active job per porter")
	f.service.cancel_job(selected)
	f.source.position = nearer.position
	selected = f.service.claim_best_job(f.worker.id)
	check(selected.source_location_id == f.source.id, "Equal score chooses stable source id")
	f.service.cancel_job(selected)
	var urgent = building(&"urgent", BT.FOOD, Vector2(900, 0), 0)
	f.target.resources.add(RT.FOOD, 10)
	f.service.add_kitchen(urgent)
	selected = f.service.claim_best_job(f.worker.id)
	check(selected.destination_location_id == urgent.id, "High urgency can justify longer route")
	var frozen_score: float = selected.priority
	urgent.resources.add(RT.FOOD, 5)
	f.service.recalculate()
	check(selected.priority == frozen_score and selected.destination_location_id == urgent.id, "Committed delivery score/route never refreshed")
	f.service.cancel_job(selected)
	# Another porter sees the first porter's already-committed projected fill.
	f = fixture()
	var second = Data.new("second", "Анна", 30, Profession.PORTER)
	second.work_location_id = f.source.id
	f.service.register_resident(second)
	var first = f.service.claim_best_job(f.worker.id)
	var next = f.service.claim_best_job(second.id)
	check(first != next and next.assigned_resident_id == second.id and f.service.jobs.size() == 2, "Two different owned jobs, no unassigned job")
	check(is_equal_approx(first.priority - next.priority, 550), "Second porter re-evaluates world urgency after first promise")
	check(f.source.resources.get_reserved_out(RT.FOOD) == 2 and f.target.resources.get_reserved_in(RT.FOOD) == 2, "Multi-porter reservations exact")
	for active in f.service.jobs.duplicate(): f.service.cancel_job(active)
	f.target.resources.reserve_in(RT.FOOD, 19)
	first = f.service.claim_best_job(f.worker.id)
	check(first != null and f.service.claim_best_job(second.id) == null and f.target.resources.get_reserved_in(RT.FOOD) == 20, "Last free unit cannot be over-reserved")
	f.service.cancel_job(first)
	f.target.resources.release_in(RT.FOOD, 19)
	var recursive = [false]
	f.source.resources.availability_changed.connect(func(_resource, _amount): recursive[0] = f.service.claim_best_job(second.id) == null, CONNECT_ONE_SHOT)
	first = f.service.claim_best_job(f.worker.id)
	check(recursive[0] and f.service.jobs.size() == 1, "Half-completed claim cannot be claimed recursively")
	f.service.cancel_job(first)
	# Stale candidate => bounded fresh re-evaluation, no stale job.
	f = fixture(StaleOnce.new())
	var alternative = building(&"alternative", BT.FOOD, Vector2(600, 0))
	f.service.add_kitchen(alternative)
	selected = f.service.claim_best_job(f.worker.id)
	check(selected != null and selected.destination_location_id == alternative.id and f.service.jobs.size() == 1, "Stale best candidate re-evaluates current alternatives")
	check(f.source.resources.get_reserved_out(RT.FOOD) == 1 and f.target.resources.get_reserved_in(RT.FOOD) == 20, "Stale failed claim creates no own source reservation")
	f.service.cancel_job(selected)
	f = fixture()
	f.target.resources = RejectIncoming.new(f.target.id)
	f.target.resources.set_capacity(RT.FOOD, 20)
	f.source.resources.reserve_out(RT.FOOD, 2)
	check(f.service.claim_best_job(f.worker.id) == null and f.service.jobs.is_empty() and f.source.resources.get_reserved_out(RT.FOOD) == 2, "Failed second reservation rolls back only owned promise")
	# DEBUG is opt-in; INFO only reports selected delivery.
	f = fixture()
	f.service.logger = EventLog.new()
	f.service.logger.console_enabled = false
	var lines: Array[String] = []
	f.service.logger.line_logged.connect(func(line, _level): lines.append(line))
	selected = f.service.claim_best_job(f.worker.id)
	check(lines.size() == 1 and lines[0].contains("выбрал доставку 1 FOOD"), "INFO reports selection only")
	f.service.cancel_job(selected)
	lines.clear()
	f.service.logger.debug_enabled = true
	selected = f.service.claim_best_job(f.worker.id)
	check(lines[0].contains("[DEBUG]") and lines[0].contains("urgency=11000.0 distance=600.0 penalty=1000.0 personal=0.0 score=10000.0"), "DEBUG exposes complete scoring")
	for line in lines: print(line)
	f.service.cancel_job(selected)
	# Real simultaneous physical execution with two independent intent controllers.
	var scene = simulation()
	scene.player_control.assign_profession(scene.residents[1].id, Profession.PORTER)
	scene.game_time.debug_next_phase()
	var a = scene.resident_runtimes[0]
	var b = scene.resident_runtimes[1]
	var aj = scene.logistics.get_job(a.data.id)
	var bj = scene.logistics.get_job(b.data.id)
	check(aj != null and bj != null and aj != bj and scene.logistics.jobs.size() == 2, "Both porters start independently at normal WORK decisions")
	var decision_before: int = a.decision.decision_count
	a.view._process(20)
	b.view._process(20)
	check(a.data.inventory.amount == 1 and b.data.inventory.amount == 1 and scene.warehouse_data.resources.get_amount(RT.FOOD) == 8, "Both residents physically picked up distinct units")
	check(scene.warehouse_data.resources.get_reserved_out(RT.FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(RT.FOOD) == 2, "Only incoming reservations remain while carrying")
	scene.player_control.assign_profession(a.data.id, Profession.NONE)
	scene.player_control.assign_profession(b.data.id, Profession.NONE)
	a.view._process(20)
	b.view._process(20)
	check(aj.state == Job.State.COMPLETED and bj.state == Job.State.COMPLETED and scene.logistics.jobs.is_empty(), "Both committed jobs complete after profession changes")
	check(scene.kitchen_data.resources.get_amount(RT.FOOD) == 2 and scene.kitchen_data.resources.get_reserved_in(RT.FOOD) == 0 and a.data.inventory.amount == 0 and b.data.inventory.amount == 0, "Delivery conservation and cleanup")
	check(a.decision.decision_count > decision_before, "Completion creates a new ordinary decision point")
	scene.free()
	# Interrupting one resident never cancels another resident's committed delivery.
	for forced_kind in ["player", "critical"]:
		for picked_up in [false, true]:
			scene = simulation()
			scene.player_control.assign_profession(scene.residents[1].id, Profession.PORTER)
			scene.game_time.debug_next_phase()
			a = scene.resident_runtimes[0]
			b = scene.resident_runtimes[1]
			aj = scene.logistics.get_job(a.data.id)
			bj = scene.logistics.get_job(b.data.id)
			if picked_up: b.view._process(20)
			var drop_position: Vector2 = b.view.global_position
			if forced_kind == "player": scene.player_control.move_to(b.data.id, Vector2(700, 400))
			else: b.data.fatigue = 100
			check(bj.state == Job.State.CANCELLED and aj.is_active() and scene.logistics.get_job(a.data.id) == aj, "%s interrupt affects only owning porter" % forced_kind)
			check(scene.warehouse_data.resources.get_reserved_out(RT.FOOD) == 1 and scene.kitchen_data.resources.get_reserved_in(RT.FOOD) == 1 and b.data.inventory.amount == 0, "Interrupted owner releases exactly its own promises")
			check(scene.warehouse_data.resources.get_amount(RT.FOOD) == (9 if picked_up else 10) and scene.ground_resources.drops.size() == (1 if picked_up else 0), "Before/after pickup preserves physical resource")
			if picked_up: check(scene.ground_resources.drops[0].world_position == drop_position, "Cargo drops at interrupted resident, not other executor")
			scene.free()
	# PlayerCommand during reserve callbacks invalidates claim before job creation.
	scene = simulation()
	a = scene.resident_runtimes[0]
	var controlled_id: String = a.data.id
	scene.warehouse_data.resources.availability_changed.connect(func(_resource, _amount): scene.player_control.move_to(controlled_id, Vector2(700, 400)), CONNECT_ONE_SHOT)
	scene.game_time.debug_next_phase()
	check(scene.logistics.jobs.is_empty() and scene.logistics.current_job == null and a.intents.player_controlled, "Player takeover inside claim prevents stale job creation")
	check(scene.warehouse_data.resources.get_reserved_out(RT.FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(RT.FOOD) == 0, "Invalidated claim rolls back both reservations")
	scene.free()
	# Event-driven resource availability wakes an idle porter without clock polling.
	scene = simulation()
	scene.warehouse_data.resources.try_take(RT.FOOD, 10)
	scene.game_time.debug_next_phase()
	a = scene.resident_runtimes[0]
	check(scene.logistics.jobs.is_empty() and not a.intents.has_current_action(), "No work leaves porter idle without speculative job")
	scene.warehouse_data.resources.add(RT.FOOD, 1)
	await process_frame
	check(scene.logistics.get_job(a.data.id) != null and a.intents.current_intent.reason_id == &"haul_source", "Local FOOD event supplies new normal decision without time tick")
	scene.free()
	print("Delivery candidates checks: %d, %s" % [checks, "PASS" if failures == 0 else "FAIL"])
	quit(0 if failures == 0 else 1)
