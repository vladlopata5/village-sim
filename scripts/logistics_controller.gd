extends RefCounted
## One fixed FOOD route and one physical delivery at a time.
const HaulJob = preload("res://scripts/haul_job.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const FOOD = ResourceType.Type.FOOD
const TARGET_STOCK := 3
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const HAUL_PRIORITY := 80
signal cargo_dropped(resource: ResourceType.Type, amount: int)
var before_work: Callable
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

func setup(source: BuildingData, destination: BuildingData, resident: ResidentData) -> void:
	_source = source
	_destination = destination
	_resident = resident

func recalculate() -> void:
	if current_job != null and current_job.is_active():
		_assign_if_possible()
		_start_if_possible()
		changed.emit()
		return
	if _source == null or _destination == null:
		return
	if _source.id != &"warehouse_01" or _destination.id != &"communal_kitchen_01":
		return
	if _source.type != BuildingType.Type.STORAGE or _destination.type != BuildingType.Type.FOOD:
		return
	var source = _source.resources
	var destination = _destination.resources
	if destination.get_amount(FOOD) + destination.get_reserved_in(FOOD) >= TARGET_STOCK:
		return
	if source.get_available_amount(FOOD) < 1 or destination.get_available_free_capacity(FOOD) < 1:
		return
	if not source.reserve_out(FOOD, 1):
		return
	if not destination.reserve_in(FOOD, 1):
		# Roll back only the reservation made by this attempt.
		source.release_out(FOOD, 1)
		return
	current_job = HaulJob.new(StringName("haul_%04d" % _next_id), _source.id, _destination.id, FOOD, 1)
	_next_id += 1
	_assign_if_possible()
	_start_if_possible()
	changed.emit()

func _assign_if_possible() -> void:
	if current_job.state != HaulJob.State.RESERVED or _resident == null:
		return
	if _resident.profession == Profession.Type.PORTER and _resident.work_location_id == _source.id:
		current_job.assigned_resident_id = _resident.id
		current_job.state = HaulJob.State.ASSIGNED

func cancel_job(job: HaulJob) -> bool:
	if job == null or job != current_job or not job.is_active() or job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]:
		return false
	_source.resources.release_out(job.resource_type, job.amount)
	_destination.resources.release_in(job.resource_type, job.amount)
	job.state = HaulJob.State.CANCELLED
	var old := _haul_intent
	_haul_intent = null
	if _intents != null and old != null and _intents.current_intent == old:
		_intents.clear_reason(old.reason_id)
	changed.emit()
	return true

func bind_execution(clock: Node, locations: RefCounted, intents: Node, schedule: Node) -> void:
	_clock = clock
	_locations = locations
	_intents = intents
	_schedule = schedule
	_clock.phase_changed.connect(_on_phase_changed)
	_intents.forced_interrupt.connect(_on_forced_interrupt)
	_intents.intent_arrived.connect(_on_arrival)
	_intents.intent_changed.connect(_on_intent_changed)
	_intents.intent_completed.connect(_on_action_completed)
	recalculate()

func unbind_execution() -> void:
	# Also used by isolated subsystem tests that do not execute deliveries.
	if _clock == null:
		return
	_clock.phase_changed.disconnect(_on_phase_changed)
	_intents.forced_interrupt.disconnect(_on_forced_interrupt)
	_intents.intent_arrived.disconnect(_on_arrival)
	_intents.intent_changed.disconnect(_on_intent_changed)
	_intents.intent_completed.disconnect(_on_action_completed)
	_clock = null

func _start_if_possible() -> void:
	if _clock == null or _finishing or _clock.get_phase() != "День" or current_job.state != HaulJob.State.ASSIGNED:
		return
	if _resident.inventory.amount != 0 or _resident.activity == Activity.Type.EATING:
		return
	if before_work.is_valid() and not before_work.call():
		return
	var target: Variant = _locations.get_position(current_job.source_location_id)
	if not target is Vector2:
		return
	# No deferred source route: start only when it can become current immediately.
	if _intents.current_intent.type != Intent.Type.NONE and (not _intents.current_intent.interruptible or _intents.current_intent.priority >= HAUL_PRIORITY):
		return
	current_job.state = HaulJob.State.GOING_TO_SOURCE
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_source", target, HAUL_PRIORITY, true)
	_intents.submit(_haul_intent)

func _on_intent_changed(intent: Intent) -> void:
	if current_job != null and current_job.state == HaulJob.State.GOING_TO_SOURCE and intent != _haul_intent:
		cancel_job(current_job)

func _on_phase_changed(phase: String) -> void:
	if phase == "Ночь" and current_job != null and current_job.state in [HaulJob.State.RESERVED, HaulJob.State.ASSIGNED, HaulJob.State.GOING_TO_SOURCE]:
		cancel_job(current_job)
	elif phase == "День":
		recalculate()

func _on_action_completed(_intent: Intent) -> void:
	if not _finishing and _clock != null and _clock.get_phase() == "День":
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
		if not _source.resources.take_reserved(FOOD, 1):
			intent.interruptible = true
			cancel_job(current_job)
			return
		_resident.inventory.put(FOOD, 1)
		current_job.state = HaulJob.State.CARRYING
		_resident.activity = Activity.Type.HAULING
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
	if _resident.inventory.amount != 1 or _destination.resources.get_reserved_in(FOOD) < 1:
		return # Keep cargo and the locked goal if a promised destination is invalid.
	_finishing = true
	# Remove carried FOOD before container.changed can trigger a new decision.
	_resident.inventory.clear()
	if not _destination.resources.add_reserved(FOOD, 1):
		_resident.inventory.put(FOOD, 1)
		_finishing = false
		return
	current_job.state = HaulJob.State.COMPLETED
	_haul_intent = null
	_intents.clear_completed(intent) # Promotes pending night_home without losing it.
	delivered.emit()
	_finishing = false
	if _intents.current_intent.type == Intent.Type.NONE and _resident.activity == Activity.Type.IDLE:
		_schedule.resume_current_phase()
	if _clock.get_phase() == "День":
		recalculate()
	changed.emit()

func _on_forced_interrupt(_previous: Intent) -> void:
	if current_job == null or not current_job.is_active():
		return
	if current_job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]:
		# Source reserve was consumed at pickup. Only destination remains promised.
		_destination.resources.release_in(current_job.resource_type, current_job.amount)
		var amount: int = _resident.inventory.amount
		var resource = _resident.inventory.resource_type
		current_job.state = HaulJob.State.CANCELLED
		_haul_intent = null
		_resident.inventory.clear()
		if amount > 0:
			cargo_dropped.emit(resource, amount)
		changed.emit()
	else:
		cancel_job(current_job)
