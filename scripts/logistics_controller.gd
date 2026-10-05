extends RefCounted
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Available reserved jobs; workers claim work explicitly. One prototype executor.
const HaulJob = preload("res://scripts/haul_job.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const FOOD = ResourceType.Type.FOOD
const Priority = preload("res://scripts/logistics_priority.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const HAUL_PRIORITY := 8000
signal cargo_dropped(resource: ResourceType.Type, amount: int)
signal job_cancelled(resident_id: String)
var jobs: Array[HaulJob] = []
var _residents: Dictionary = {}
signal delivered
var _clock: Node
var _locations: RefCounted
var _intents: Node
var _schedule: Node
var _haul_intent: Intent
var _finishing := false
signal changed
var current_job: HaulJob
var _source: BuildingData
var _destination: BuildingData
var _resident: ResidentData
var _next_id := 1
var _routes: Array = []
var _buildings: Dictionary = {}
var _recalculating := false

func setup(source: BuildingData, destination: BuildingData, resident: ResidentData) -> void:
	_source = source # Assigned porter's warehouse, not the source of every job.
	_destination = destination
	_resident = resident
	_buildings[source.id] = source
	_buildings[destination.id] = destination
	_routes = [{"source": source, "destination": destination, "export": false}]
	if resident != null: register_resident(resident)

func add_production_source(hut: BuildingData) -> void:
	_buildings[hut.id] = hut
	_routes.append({"source": hut, "destination": _source, "export": true})

func _route_has_job(route: Dictionary) -> bool:
	return jobs.any(func(job): return job.is_active() and job.source_location_id == route.source.id and job.destination_location_id == route.destination.id)

func _route_can_create(route: Dictionary) -> bool:
	return not _route_has_job(route) and route.source.resources.get_available_amount(FOOD) >= 1 and route.destination.resources.get_available_free_capacity(FOOD) >= 1

func recalculate() -> void:
	if _recalculating: return
	_recalculating = true
	jobs = jobs.filter(func(job): return job.is_active())
	for route in _routes:
		if not _route_can_create(route): continue
		if not route.source.resources.reserve_out(FOOD, 1): continue
		if not route.destination.resources.reserve_in(FOOD, 1):
			route.source.resources.release_out(FOOD, 1)
			continue
		var job = HaulJob.new(StringName("haul_%04d" % _next_id), route.source.id, route.destination.id, FOOD, 1)
		_next_id += 1
		jobs.append(job)
		if logger != null: logger.debug(EventLog.LOGISTICS, "%s: reserved_out=1 у %s; reserved_in=1 у %s" % [job.id, route.source.display_name, route.destination.display_name])
	_refresh_priorities()
	if current_job == null or not current_job.is_active():
		if not jobs.is_empty(): current_job = jobs[0]
	_recalculating = false
	changed.emit()

func _refresh_priorities() -> void:
	for job in jobs:
		var source: BuildingData = _buildings.get(job.source_location_id)
		var destination: BuildingData = _buildings.get(job.destination_location_id)
		if source == null or destination == null: continue
		if source.type == BuildingType.Type.GATHERER_HUT:
			job.priority = Priority.export_priority(source.resources, job.resource_type, source.logistics_weight)
		else:
			job.priority = Priority.import_priority(destination.resources, job.resource_type, destination.logistics_weight)

func _job_source(job: HaulJob) -> BuildingData:
	return _buildings.get(job.source_location_id)
func _job_destination(job: HaulJob) -> BuildingData:
	return _buildings.get(job.destination_location_id)

func register_resident(resident: ResidentData) -> void:
	_residents[resident.id] = resident

func _eligible(resident: ResidentData, job: HaulJob) -> bool:
	return resident != null and resident.profession == Profession.Type.PORTER and resident.work_location_id == _source.id and _buildings.has(job.source_location_id) and _buildings.has(job.destination_location_id)

func claim_best_job(resident_id: String) -> HaulJob:
	var resident: ResidentData = _residents.get(resident_id)
	if resident == null: return null
	for job in jobs:
		if job.is_active() and job.assigned_resident_id == resident_id: return null
	_refresh_priorities()
	var best: HaulJob = null
	for job in jobs:
		if job.state != HaulJob.State.RESERVED or not job.assigned_resident_id.is_empty() or not _eligible(resident, job): continue
		if best == null or job.priority > best.priority or (job.priority == best.priority and String(job.id) < String(best.id)):
			best = job
	if best != null:
		# No yield or signal between selection and ownership: subsequent claims see ASSIGNED.
		best.assigned_resident_id = resident_id
		best.state = HaulJob.State.ASSIGNED
		current_job = best
		if logger != null:
			logger.info(EventLog.LOGISTICS, "%s: принял HaulJob %s — %s → %s" % [resident.resident_name, best.id, _job_source(best).display_name, _job_destination(best).display_name])
			logger.debug(EventLog.LOGISTICS, "%s: HaulJob priority=%.1f" % [best.id, best.priority])
		changed.emit()
	return best

func has_available_job(resident_id: String) -> bool:
	var resident: ResidentData = _residents.get(resident_id)
	if resident == null: return false
	for job in jobs:
		if job.state == HaulJob.State.RESERVED and _eligible(resident, job): return true
	return resident.profession == Profession.Type.PORTER and _source != null and resident.work_location_id == _source.id and _can_create_job()

func executor_available() -> bool:
	return _haul_intent == null and not _finishing

func use_executor(resident: ResidentData, clock: Node, locations: RefCounted, intents: Node, schedule: Node) -> bool:
	if not executor_available(): return false
	_disconnect_resident()
	_resident = resident
	bind_execution(clock, locations, intents, schedule)
	return true

func executor_resident() -> ResidentData:
	return _resident

func start_claimed_job(job: HaulJob, resident_id: String) -> bool:
	if job == null or job != current_job or job.assigned_resident_id != resident_id or _resident == null or _resident.id != resident_id: return false
	return _start_if_possible()

func cancel_job(job: HaulJob) -> bool:
	if job == null or not jobs.has(job) or not job.is_active() or job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]:
		return false
	_job_source(job).resources.release_out(job.resource_type, job.amount)
	_job_destination(job).resources.release_in(job.resource_type, job.amount)
	job.state = HaulJob.State.CANCELLED
	if logger != null: logger.info(EventLog.LOGISTICS, "HaulJob %s отменён до подбора; обе брони освобождены" % job.id)
	var old: Intent = _haul_intent if job == current_job else null
	if old != null: _haul_intent = null
	if _intents != null and old != null and _intents.current_intent == old:
		_intents.clear_reason(old.reason_id)
	changed.emit()
	if not job.assigned_resident_id.is_empty(): job_cancelled.emit(job.assigned_resident_id)
	return true

func bind_world(clock: Node, locations: RefCounted) -> void:
	_clock = clock
	_locations = locations
	if not _clock.phase_changed.is_connected(_on_phase_changed): _clock.phase_changed.connect(_on_phase_changed)
	if not _clock.minute_changed.is_connected(_on_minute): _clock.minute_changed.connect(_on_minute)

func bind_execution(clock: Node, locations: RefCounted, intents: Node, schedule: Node) -> void:
	bind_world(clock, locations)
	_intents = intents
	_schedule = schedule
	_intents.forced_interrupt.connect(_on_forced_interrupt)
	_intents.intent_arrived.connect(_on_arrival)
	_intents.intent_changed.connect(_on_intent_changed)
	recalculate()

func unbind_execution() -> void:
	# Also used by isolated subsystem tests that do not execute deliveries.
	if _clock == null:
		return
	_clock.phase_changed.disconnect(_on_phase_changed)
	_clock.minute_changed.disconnect(_on_minute)
	_disconnect_resident()
	_clock = null

func _disconnect_resident() -> void:
	if not is_instance_valid(_intents): return
	for connection in [[_intents.forced_interrupt, _on_forced_interrupt], [_intents.intent_arrived, _on_arrival], [_intents.intent_changed, _on_intent_changed]]:
		if connection[0].is_connected(connection[1]): connection[0].disconnect(connection[1])
	_intents = null
	_schedule = null

func _start_if_possible() -> bool:
	if _clock == null or _finishing or _clock.get_phase() != "День" or current_job.state != HaulJob.State.ASSIGNED:
		return false
	if _resident.inventory.amount != 0 or (_intents.has_current_action() and _intents.current_intent.reason_id not in [&"day_work", &"manual_move"]):
		return false
	var target: Variant = _locations.get_position(current_job.source_location_id)
	if not target is Vector2:
		return false
	# No deferred source route: start only when it can become current immediately.
	if _intents.current_intent.type != Intent.Type.NONE and (not _intents.current_intent.interruptible or _intents.current_intent.priority >= HAUL_PRIORITY):
		return false
	current_job.state = HaulJob.State.GOING_TO_SOURCE
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_source", target, HAUL_PRIORITY, true)
	if not _intents.submit(_haul_intent):
		current_job.state = HaulJob.State.ASSIGNED
		_haul_intent = null
		return false
	if logger != null: logger.sync_activity(_resident)
	return true

func _on_intent_changed(intent: Intent) -> void:
	if current_job != null and current_job.state == HaulJob.State.GOING_TO_SOURCE and intent != _haul_intent:
		cancel_job(current_job)

func _on_minute(_minute: int) -> void:
	recalculate() # Offer/update work, never claim or start it.

func _on_phase_changed(phase: String) -> void:
	if phase == "Ночь" and current_job != null and current_job.state in [HaulJob.State.ASSIGNED, HaulJob.State.GOING_TO_SOURCE]:
		cancel_job(current_job)
	elif phase == "День":
		recalculate()

func _on_arrival(intent: Intent) -> void:
	if intent != _haul_intent or current_job == null:
		return
	if current_job.state == HaulJob.State.GOING_TO_SOURCE:
		var target: Variant = _locations.get_position(current_job.destination_location_id)
		if not target is Vector2 or _resident.inventory.amount != 0:
			cancel_job(current_job)
			return
		# Lock before signals from resource/inventory updates can create decisions.
		intent.interruptible = false
		if not _job_source(current_job).resources.take_reserved(FOOD, 1):
			intent.interruptible = true
			cancel_job(current_job)
			return
		_resident.inventory.put(FOOD, 1)
		current_job.state = HaulJob.State.CARRYING
		_resident.activity = Activity.Type.HAULING
		if logger != null: logger.info(EventLog.LOGISTICS, "%s: забрал 1 FOOD — %s" % [_resident.resident_name, _job_source(current_job).display_name])
		changed.emit()
		if current_job.state != HaulJob.State.CARRYING or _intents.current_intent != intent:
			return # A forced interrupt during the pickup notification already cancelled it.
		current_job.state = HaulJob.State.GOING_TO_DESTINATION
		_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_destination", target, HAUL_PRIORITY, false)
		_intents.continue_intent(intent, _haul_intent)
		changed.emit()
	elif current_job.state == HaulJob.State.GOING_TO_DESTINATION:
		_finish_delivery(intent)

func _finish_delivery(intent: Intent) -> void:
	if _resident.inventory.amount != 1 or _job_destination(current_job).resources.get_reserved_in(FOOD) < 1:
		return # Keep cargo and the locked goal if a promised destination is invalid.
	_finishing = true
	# Remove carried FOOD before container.changed can trigger a new decision.
	_resident.inventory.clear()
	if not _job_destination(current_job).resources.add_reserved(FOOD, 1):
		_resident.inventory.put(FOOD, 1)
		_finishing = false
		return
	current_job.state = HaulJob.State.COMPLETED
	if logger != null: logger.info(EventLog.LOGISTICS, "%s: доставил 1 FOOD — %s" % [_resident.resident_name, _job_destination(current_job).display_name])
	_haul_intent = null
	recalculate() # Make the next reserved offer visible before the next decision point.
	_finishing = false
	_intents.clear_completed(intent) # DecisionController chooses needs or claims work.
	delivered.emit()
	changed.emit()

func _on_forced_interrupt(_previous: Intent) -> void:
	if current_job == null or not current_job.is_active() or current_job.assigned_resident_id != _resident.id:
		return
	if current_job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]:
		# Source reserve was consumed at pickup. Only destination remains promised.
		_job_destination(current_job).resources.release_in(current_job.resource_type, current_job.amount)
		var amount: int = _resident.inventory.amount
		var resource = _resident.inventory.resource_type
		current_job.state = HaulJob.State.CANCELLED
		if logger != null: logger.info(EventLog.LOGISTICS, "HaulJob %s отменён принудительно после подбора; груз выгружен, reserved_in освобождён" % current_job.id)
		_haul_intent = null
		_resident.inventory.clear()
		if amount > 0:
			cargo_dropped.emit(resource, amount)
		changed.emit()
		job_cancelled.emit(current_job.assigned_resident_id)
	else:
		cancel_job(current_job)

func has_work() -> bool:
	return _resident != null and has_available_job(_resident.id)

func _can_create_job() -> bool:
	return _routes.any(func(route): return _route_can_create(route))
