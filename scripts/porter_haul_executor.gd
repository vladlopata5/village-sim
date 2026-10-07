extends RefCounted
## Physical execution of one already-claimed delivery for one resident.
const Job = preload("res://scripts/haul_job.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const HAUL_PRIORITY := 8000
var _owner: WeakRef
var service: RefCounted:
	get: return _owner.get_ref()
var resident: RefCounted
var clock: Node
var locations: RefCounted
var intents: Node
var source: RefCounted
var destination: RefCounted
var job: Job:
	set(value):
		job = value
		if value != null:
			source = service._buildings.get(value.source_location_id)
			destination = service._buildings.get(value.destination_location_id)
			_source_reserved = true
			_destination_reserved = true
var _haul_intent: Intent
var _source_reserved := false
var _destination_reserved := false
var _mutating := false
var _exiting := false
var _interrupt_pending := false

func setup(owner: RefCounted, data: RefCounted, game_time: Node, world_locations: RefCounted, controller: Node) -> void:
	_owner = weakref(owner)
	resident = data
	clock = game_time
	locations = world_locations
	intents = controller
	clock.phase_changed.connect(_on_phase_changed)
	intents.forced_interrupt.connect(_on_forced_interrupt)
	intents.intent_arrived.connect(_on_arrival)
	intents.intent_changed.connect(_on_intent_changed)

func unbind() -> void:
	if job != null: cancel("исполнитель отключён")
	if is_instance_valid(clock) and clock.phase_changed.is_connected(_on_phase_changed): clock.phase_changed.disconnect(_on_phase_changed)
	if not is_instance_valid(intents): return
	for connection in [[intents.forced_interrupt, _on_forced_interrupt], [intents.intent_arrived, _on_arrival], [intents.intent_changed, _on_intent_changed]]:
		if connection[0].is_connected(connection[1]): connection[0].disconnect(connection[1])

func can_start() -> bool:
	if job != null or _exiting or _mutating or intents.player_controlled or intents.forced_priority > 0: return false
	if clock.get_phase() != "День" or resident.inventory.amount != 0: return false
	return not intents.has_current_action() or (intents.current_intent.reason_id in [&"day_work", &"manual_move"] and intents.current_intent.interruptible and intents.current_intent.priority < HAUL_PRIORITY)

func start(claimed: Job) -> bool:
	if job != claimed or claimed.state != Job.State.ASSIGNED or intents.player_controlled or intents.forced_priority > 0: return false
	if not validate_job(): return false
	var target: Variant = locations.get_position(claimed.source_location_id)
	if not target is Vector2: return false
	claimed.state = Job.State.GOING_TO_SOURCE
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_source", target, HAUL_PRIORITY, true)
	if not intents.submit(_haul_intent):
		_haul_intent = null
		claimed.state = Job.State.ASSIGNED
		return false
	if service.logger != null: service.logger.sync_activity(resident)
	return true

func validate_job() -> bool:
	if job == null: return false
	var source_needed := job.state in [Job.State.ASSIGNED, Job.State.GOING_TO_SOURCE]
	if destination == null or service._buildings.get(destination.id) != destination or not destination.is_built() or not locations.get_position(destination.id) is Vector2:
		cancel("цель доставки недоступна")
		return false
	if source_needed and (source == null or service._buildings.get(source.id) != source or not source.is_built() or not locations.get_position(source.id) is Vector2):
		cancel("источник недоступен")
		return false
	return true

func _on_phase_changed(phase: String) -> void:
	if phase == "Ночь" and job != null and job.state in [Job.State.ASSIGNED, Job.State.GOING_TO_SOURCE]: cancel("началась ночь")
func _on_intent_changed(intent: Intent) -> void:
	if job != null and job.state == Job.State.GOING_TO_SOURCE and intent != _haul_intent: cancel("действие сменилось")
func _on_forced_interrupt(_previous: Intent) -> void:
	if _mutating:
		_interrupt_pending = true
	elif job != null:
		cancel("forced interrupt")

func _on_arrival(intent: Intent) -> void:
	if intent != _haul_intent or job == null or not validate_job(): return
	if job.state == Job.State.GOING_TO_SOURCE:
		_pickup(intent)
	elif job.state == Job.State.GOING_TO_DESTINATION:
		_deliver(intent)

func _pickup(intent: Intent) -> void:
	if resident.inventory.amount != 0:
		cancel("инвентарь занят")
		return
	intent.interruptible = false
	_mutating = true
	var taken: bool = source.resources.take_reserved(job.resource_type, job.amount)
	if taken:
		_source_reserved = false
		resident.inventory.put(job.resource_type, job.amount)
		job.state = Job.State.CARRYING
		resident.activity = Activity.Type.HAULING
	_mutating = false
	if not taken or _interrupt_pending:
		_interrupt_pending = false
		cancel("подбор прерван")
		return
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: забрал 1 FOOD — %s" % [resident.resident_name, source.display_name])
	service.changed.emit()
	if job == null or intents.current_intent != intent: return
	job.state = Job.State.GOING_TO_DESTINATION
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_destination", locations.get_position(destination.id), HAUL_PRIORITY, false)
	intents.continue_intent(intent, _haul_intent)
	service.changed.emit()

func _deliver(intent: Intent) -> void:
	if resident.inventory.amount != job.amount or destination.resources.get_reserved_in(job.resource_type) < job.amount:
		cancel("доставка невозможна")
		return
	_mutating = true
	resident.inventory.clear()
	var delivered: bool = destination.resources.add_reserved(job.resource_type, job.amount)
	if delivered: _destination_reserved = false
	else: resident.inventory.put(job.resource_type, job.amount)
	_mutating = false
	if not delivered:
		_interrupt_pending = false
		cancel("доставка невозможна")
		return
	var completed := job
	completed.state = Job.State.COMPLETED
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: доставил 1 FOOD — %s" % [resident.resident_name, destination.display_name])
	job = null
	_haul_intent = null
	_interrupt_pending = false
	service.finish_job(completed)
	intents.clear_completed(intent)
	service.notify_delivery()
	service.changed.emit()

func cancel(reason: String) -> bool:
	if job == null or _exiting: return false
	if _mutating:
		_interrupt_pending = true
		return true
	_exiting = true
	var cancelled := job
	var old := _haul_intent
	cancelled.state = Job.State.CANCELLED
	job = null
	_haul_intent = null
	if _source_reserved and source != null: source.resources.release_out(cancelled.resource_type, cancelled.amount)
	if _destination_reserved and destination != null: destination.resources.release_in(cancelled.resource_type, cancelled.amount)
	_source_reserved = false
	_destination_reserved = false
	var amount: int = resident.inventory.amount
	var resource = resident.inventory.resource_type
	resident.inventory.clear()
	if amount > 0: service.drop_cargo(resource, amount, resident.id)
	if old != null and intents.current_intent == old: intents.cancel_current(old)
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: HaulJob %s отменён — %s" % [resident.resident_name, cancelled.id, reason])
	service.finish_job(cancelled)
	_exiting = false
	service.job_cancelled.emit(resident.id)
	return true
