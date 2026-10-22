extends Node
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
## Physical worker for building-owned batches; no resource or progress ledger here.
const Intent = preload("res://scripts/resident_intent.gd")
const Batch = preload("res://scripts/production_batch.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Balance = preload("res://scripts/balance_config.gd")
const EventLog = preload("res://scripts/game_logger.gd")
enum Phase { NONE, GOING_TO_WORK, WORKING }
signal work_cycle_started(building_id: StringName)
var logger: EventLog
var position_provider: Callable
var phase := Phase.NONE
var building: RefCounted
var batch: Batch
var _runtime: Node
var _clock: Node
var _locations: RefCounted
var _buildings: Array
var _intent: Intent
var _mutating := false
var _interrupted := false
var _exiting := false
var _last_minute := 0
var _assignment_revision := 0
var _availability_queued := false

func setup(runtime: Node, clock: Node, locations: RefCounted, buildings: Array) -> void:
	_runtime = runtime
	_clock = clock
	_locations = locations
	_buildings = buildings
	runtime.intents.forced_interrupt.connect(_on_forced)
	runtime.intents.intent_changed.connect(_on_intent_changed)
	runtime.intents.intent_arrived.connect(_on_arrival)
	clock.minute_changed.connect(_on_minute)
	for target in buildings: register_building(target)

func register_building(target: RefCounted) -> void:
	if target.definition.production_recipe == null: return
	if not target.resources.availability_changed.is_connected(_on_resource):
		target.resources.availability_changed.connect(_on_resource)
		target.resources.reservations_changed.connect(_on_reservation)
		target.construction_changed.connect(_queue_availability)

func _eligible(target: RefCounted) -> bool:
	return target != null and target.is_built() and not target.production_removed and target.definition.production_recipe != null and target.definition.worker_profession != Profession.Type.NONE and _runtime.data.profession == target.definition.worker_profession and _runtime.data.work_location_id == target.id and _runtime.data.inventory.amount == 0


func _workplace() -> RefCounted:
	# Canonical location registry already indexes the assigned building presentation.
	var presentation: Node = _locations.get_view(_runtime.data.work_location_id)
	var target: RefCounted = presentation.building_data if presentation!=null else null
	return target if _eligible(target) and _locations.get_position(target.id) is Vector2 else null

func has_work() -> bool:
	if phase!=Phase.NONE: return false
	var target := _workplace()
	return target!=null and not target.select_production_work(_runtime.data.id).is_empty()

func request_work() -> bool:
	if _clock.get_phase() != "День" or _runtime.intents.player_controlled or _runtime.intents.forced_priority>0 or _runtime.intents.has_current_action() or not has_work(): return false
	building = _workplace()
	building.production_changed.connect(_on_production_changed)
	_assignment_revision = _runtime.data.work_assignment_revision
	phase = Phase.GOING_TO_WORK
	_mutating = true
	batch = building.claim_production_work(_runtime.data.id)
	_mutating = false
	if batch == null or _interrupted or not _valid() or _clock.get_phase() != "День" or _runtime.intents.has_current_action():
		abort()
		return false
	_intent = Intent.new(Intent.Type.MOVE_TO,&"recipe_work",_locations.get_position(building.id),Balance.WORK_PRIORITY,false)
	if _locations.has_method("configure_intent"): _locations.configure_intent(_intent,building.id,Purpose.WORKER,_runtime.data.id)
	if not _runtime.intents.submit(_intent):
		abort()
		return false
	if phase==Phase.NONE: return false
	building.accept_production_batch(batch)
	return true

func _valid() -> bool:
	return _eligible(building) and building in _buildings and batch != null and building.owns_production_batch(batch) and batch.worker_id == _runtime.data.id and batch.reserves_valid() and _runtime.data.work_assignment_revision == _assignment_revision and _locations.get_position(building.id) is Vector2

func keeps_shift_action() -> bool:
	return phase in [Phase.GOING_TO_WORK,Phase.WORKING] and _intent != null and _intent == _runtime.intents.current_intent and _valid()

func _at_workplace() -> bool:
	var point: Variant = position_provider.call(_runtime.data.id) if position_provider.is_valid() else null
	if not point is Vector2 or building == null: return false
	return _locations.at_action(_runtime.data.id,building.id,Purpose.WORKER,point,8.0) if _locations.has_method("at_action") else point.distance_to(_locations.get_position(building.id))<=8.0

func _on_arrival(intent: Intent) -> void:
	if _mutating or intent != _intent or phase != Phase.GOING_TO_WORK: return
	if not _valid() or not building.validate_production_batch(batch) or not _valid() or not _at_workplace():
		abort()
		return
	_mutating = true
	var started := batch.begin(_runtime.data.id)
	_mutating = false
	if not started or _interrupted or not _valid():
		abort()
		return
	phase = Phase.WORKING
	_last_minute = _clock.total_minutes
	_runtime.data.activity = Activity.Type.WORKING
	if phase != Phase.WORKING: return
	work_cycle_started.emit(building.id)
	if phase == Phase.WORKING and logger != null: logger.info(EventLog.PRODUCTION,"%s: начал партию %s — %s (%d/%d мин)" % [_runtime.data.resident_name,batch.id,building.display_name,batch.progress,batch.work_required])

func _accrue() -> void:
	if phase != Phase.WORKING or not _valid(): return
	if _at_workplace() and _runtime.data.activity == Activity.Type.WORKING:
		batch.advance(_runtime.data.id,maxi(_clock.total_minutes-_last_minute,0))
	_last_minute = _clock.total_minutes

func _on_minute(_minute: int) -> void:
	if phase == Phase.NONE or _mutating or _exiting: return
	if not _valid():
		abort()
		return
	_accrue()
	if phase != Phase.WORKING or batch.progress < batch.work_required: return
	_mutating = true
	var done := batch.finish(_runtime.data.id)
	_mutating = false
	var interrupted := _interrupted
	if done and logger != null: logger.info(EventLog.PRODUCTION,"%s: партия %s завершена — %s" % [_runtime.data.resident_name,batch.id,building.display_name])
	var previous := _cleanup()
	if previous != null and _runtime.intents.current_intent == previous:
		if done and not interrupted: _runtime.intents.clear_completed(previous)
		else: _runtime.intents.cancel_current(previous)
	if not done: _runtime.decision.call_deferred("request_decision","recipe_unavailable")

func _cleanup() -> Intent:
	_exiting = true
	_accrue()
	var previous := _intent
	var place := building
	var previous_batch := batch
	_intent = null
	building = null
	batch = null
	phase = Phase.NONE
	if place != null:
		if place.production_changed.is_connected(_on_production_changed): place.production_changed.disconnect(_on_production_changed)
		if place not in _buildings: place.dispose_production()
		if previous_batch != null:
			previous_batch.release_worker(_runtime.data.id)
			place.retire_production_batch(previous_batch)
	_interrupted = false
	_exiting = false
	_queue_availability()
	return previous

func abort() -> void:
	if _exiting: return
	if _mutating:
		_interrupted = true
		return
	if building == null: return
	var previous := _cleanup()
	if previous != null and _runtime.intents.current_intent == previous: _runtime.intents.cancel_current(previous)

func _on_forced(_previous: Intent) -> void: abort()
func _on_intent_changed(intent: Intent) -> void:
	if not _exiting and _intent != null and intent != _intent: abort()
func on_assignment_changed(id: String) -> void:
	if id == _runtime.data.id and building != null and not _eligible(building): abort()
func _on_production_changed() -> void:
	if not _mutating and building!=null and not _valid(): abort() # Own preparation publishes the batch after reservation callbacks.
func _on_resource(_resource: int, _amount: int) -> void: _queue_availability()
func _on_reservation(_resource: int) -> void: _queue_availability()
func _queue_availability() -> void:
	if _availability_queued: return
	_availability_queued = true
	call_deferred("_refresh_availability")
func _refresh_availability() -> void:
	_availability_queued = false
	if _clock.get_phase() == "День" and has_work() and not _runtime.intents.has_current_action() and _runtime.data.activity == Activity.Type.IDLE:
		_runtime.decision.request_decision("recipe_available")
func _exit_tree() -> void:
	if building != null: _cleanup()

func unregister_building(target: RefCounted) -> void:
	for pair in [[target.resources.availability_changed,_on_resource],[target.resources.reservations_changed,_on_reservation],[target.construction_changed,_queue_availability]]:
		if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
