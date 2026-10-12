extends RefCounted
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
## Physical execution of one already-claimed delivery for one resident.
const Job = preload("res://scripts/haul_job.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Skill = preload("res://scripts/skill_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const HAUL_PRIORITY := Job.DEFAULT_EXECUTION_PRIORITY
var _owner: WeakRef
var service: RefCounted:
	get: return _owner.get_ref()
var resident: RefCounted
var clock: Node
var locations: RefCounted
var intents: Node
var destination: RefCounted
var job: Job:
	set(value):
		job = value
		if value != null:
			destination = service._buildings.get(value.destination_location_id)
			_source_reserved = true
			_destination_reserved = true
var _haul_intent: Intent
var _source_reserved := false
var _destination_reserved := false
var _mutating := false
var _exiting := false
var _interrupt_pending := false
var handling = preload("res://scripts/resource_handling.gd").new()
const Balance = preload("res://scripts/balance_config.gd")

func setup(owner: RefCounted, data: RefCounted, game_time: Node, world_locations: RefCounted, controller: Node) -> void:
	_owner = weakref(owner)
	resident = data
	clock = game_time
	locations = world_locations
	intents = controller
	clock.minute_changed.connect(_on_minute)
	intents.forced_interrupt.connect(_on_forced_interrupt)
	intents.intent_arrived.connect(_on_arrival)
	intents.intent_changed.connect(_on_intent_changed)

func unbind() -> void:
	if job != null: cancel("исполнитель отключён")
	if is_instance_valid(clock) and clock.minute_changed.is_connected(_on_minute): clock.minute_changed.disconnect(_on_minute)
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
	var target: Variant = service.sources.point(claimed.source_ref)
	if not target is Vector2: return false
	claimed.state = Job.State.GOING_TO_SOURCE
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_source", target, claimed.execution_priority, false)
	if claimed.source_ref.kind==preload("res://scripts/resource_source_ref.gd").Kind.CONTAINER and locations.has_method("configure_intent"): locations.configure_intent(_haul_intent,claimed.source_ref.id,Purpose.COURIER,resident.id)
	if not intents.submit(_haul_intent):
		_haul_intent = null
		claimed.state = Job.State.ASSIGNED
		return false
	if service.logger != null: service.logger.sync_activity(resident)
	return true

func validate_job() -> bool:
	if job == null: return false
	if _mutating: return true
	if job.validation.is_valid() and not job.validation.call():
		cancel("workflow недоступен")
		return false
	if not service.inbound_valid(job) or destination == null or not destination.is_built() or not service.delivery_allowed(job) or not service._point(destination) is Vector2:
		cancel("цель доставки недоступна")
		return false
	if job.source_ref.kind==preload("res://scripts/resource_source_ref.gd").Kind.CONTAINER and not service.sources.export_allowed(job.source_ref,job.resource_type):
		cancel("external source policy недоступна")
		return false
	if _source_reserved and not service.sources.reserved(job.source_ref,job.resource_type,job.id):
		cancel("источник или reservation недоступны")
		return false
	return true

func _on_intent_changed(intent: Intent) -> void:
	if job != null and _haul_intent != null and intent != _haul_intent: cancel("действие сменилось")
func _on_forced_interrupt(_previous: Intent) -> void:
	if _mutating:
		_interrupt_pending = true
	elif job != null:
		cancel("forced interrupt")

func _on_arrival(intent: Intent) -> void:
	if intent != _haul_intent or job == null or handling.is_active() or not validate_job(): return
	var loading := job.state == Job.State.GOING_TO_SOURCE
	intent.interruptible = false
	intent.resource_handling = &"loading" if loading else &"unloading"
	handling.start(intent.resource_handling,clock.total_minutes,Balance.RESOURCE_LOADING_MINUTES if loading else Balance.RESOURCE_UNLOADING_MINUTES)
	resident.activity = Activity.Type.HAULING
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: %s (%d игровых минут)" % [resident.resident_name,"погрузка" if intent.resource_handling==&"loading" else "разгрузка",Balance.RESOURCE_LOADING_MINUTES if loading else Balance.RESOURCE_UNLOADING_MINUTES])

func _on_minute(now: int) -> void:
	if job == null or not validate_job() or not handling.is_active(): return
	if handling.advance(now):
		var arrived := _haul_intent
		_complete_arrival(arrived)
		arrived.resource_handling = &""

func _complete_arrival(intent: Intent) -> void:
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
	var taken: bool = service.sources.pickup(job.source_ref,job.resource_type,job.id)
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
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: забрал 1 %s — %s" % [resident.resident_name,preload("res://scripts/resource_type.gd").Type.keys()[job.resource_type], service.sources.label(job.source_ref)])
	service.changed.emit()
	if job == null or intents.current_intent != intent: return
	job.state = Job.State.GOING_TO_DESTINATION
	_haul_intent = Intent.new(Intent.Type.MOVE_TO, &"haul_destination", service._point(destination), job.execution_priority, false)
	if locations.has_method("configure_intent"): locations.configure_intent(_haul_intent,destination.id,Purpose.COURIER,resident.id)
	intents.continue_intent(intent, _haul_intent)
	service.changed.emit()

func _deliver(intent: Intent) -> void:
	if resident.inventory.amount != job.amount or destination.resources.get_reserved_in(job.resource_type) < job.amount:
		cancel("доставка невозможна")
		return
	_mutating = true
	resident.inventory.clear()
	var delivered: bool = service.deliver_inbound(job)
	if delivered: _destination_reserved = false
	else: resident.inventory.put(job.resource_type, job.amount)
	_mutating = false
	if not delivered:
		_interrupt_pending = false
		cancel("доставка невозможна")
		return
	var completed := job
	completed.state = Job.State.COMPLETED
	if service.logger != null: service.logger.info(EventLog.LOGISTICS, "%s: доставил 1 %s — %s" % [resident.resident_name,preload("res://scripts/resource_type.gd").Type.keys()[job.resource_type], destination.display_name])
	job = null
	_haul_intent = null
	_interrupt_pending = false
	service.finish_job(completed)
	if completed.award_logistics_xp: resident.add_skill_xp(Skill.Type.LOGISTICS, 1)
	intents.clear_completed(intent)
	service.notify_delivery()
	service.changed.emit()

func cancel(reason: String) -> bool:
	if job == null or _exiting: return false
	if _mutating:
		_interrupt_pending = true
		return true
	_exiting = true
	handling.cancel()
	if _haul_intent != null: _haul_intent.resource_handling = &""
	var cancelled := job
	var old := _haul_intent
	cancelled.state = Job.State.CANCELLED
	job = null
	_haul_intent = null
	if _source_reserved: service.sources.release(cancelled.source_ref,cancelled.resource_type,cancelled.id)
	if _destination_reserved: service.release_inbound(cancelled)
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
