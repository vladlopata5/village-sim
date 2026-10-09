extends Node
## Generic input-consuming recipe execution. Work/progress use the existing building data.
const Intent = preload("res://scripts/resident_intent.gd")
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
var _runtime: Node
var _clock: Node
var _locations: RefCounted
var _buildings: Array
var _intent: Intent
var _inputs: Dictionary = {}
var _outputs: Dictionary = {}
var _mutating := false
var _interrupted := false
var _exiting := false
var _last_minute := 0
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
	clock.phase_changed.connect(_on_phase)
	for target in buildings: register_building(target)
func register_building(target: RefCounted) -> void:
	if target.definition.production_recipe == null: return
	if not target.resources.availability_changed.is_connected(_on_resource):
		target.resources.availability_changed.connect(_on_resource)
		target.resources.reservations_changed.connect(_on_reservation)
		target.construction_changed.connect(_queue_availability)
func _workplace() -> RefCounted:
	for target in _buildings:
		if target.id == _runtime.data.work_location_id and target.is_built() and target.definition.production_recipe != null and _locations.get_position(target.id) is Vector2: return target
	return null
func has_work() -> bool:
	if phase != Phase.NONE or _runtime.data.profession != Profession.Type.SAWYER or _runtime.data.inventory.amount != 0: return false
	var target := _workplace()
	if target == null or not target.production_worker_id.is_empty(): return false
	var recipe: RefCounted = target.definition.production_recipe
	for resource in recipe.inputs:
		if target.resources.get_available_amount(resource) < int(recipe.inputs[resource]): return false
	for resource in recipe.outputs:
		if target.resources.get_available_free_capacity(resource) < int(recipe.outputs[resource]): return false
	return true
func request_work() -> bool:
	if _clock.get_phase() != "День" or _runtime.intents.has_current_action() or not has_work(): return false
	building = _workplace()
	building.production_worker_id = _runtime.data.id
	_mutating = true
	var recipe: RefCounted = building.definition.production_recipe
	var reserved := true
	for resource in recipe.inputs:
		if not building.resources.reserve_out(resource,recipe.inputs[resource]):
			reserved = false
			break
		_inputs[resource] = recipe.inputs[resource]
	if reserved:
		for resource in recipe.outputs:
			if not building.resources.reserve_in(resource,recipe.outputs[resource]):
				reserved = false
				break
			_outputs[resource] = recipe.outputs[resource]
	_mutating = false
	if not reserved or _interrupted:
		abort()
		return false
	phase = Phase.GOING_TO_WORK
	_intent = Intent.new(Intent.Type.MOVE_TO,&"recipe_work",_locations.get_position(building.id),Balance.WORK_PRIORITY,false)
	if not _runtime.intents.submit(_intent):
		abort()
		return false
	return true
func _on_arrival(intent: Intent) -> void:
	if intent != _intent or phase != Phase.GOING_TO_WORK: return
	if not _valid():
		abort()
		return
	phase = Phase.WORKING
	_last_minute = _clock.total_minutes
	_runtime.data.activity = Activity.Type.WORKING
	work_cycle_started.emit(building.id)
	if logger != null: logger.info(EventLog.PRODUCTION,"%s: начал recipe cycle — %s (%d/%d мин)" % [_runtime.data.resident_name,building.display_name,building.production_progress,building.definition.production_recipe.work_required])
func _valid() -> bool:
	return building != null and building in _buildings and building.is_built() and building.production_worker_id == _runtime.data.id and _locations.get_position(building.id) is Vector2
func _accrue() -> void:
	if phase != Phase.WORKING or not _valid(): return
	var point: Variant = position_provider.call(_runtime.data.id) if position_provider.is_valid() else null
	var target: Vector2 = _locations.get_position(building.id)
	if point is Vector2 and point.distance_to(target) <= 8.0 and _runtime.data.activity == Activity.Type.WORKING:
		building.production_progress = mini(building.production_progress+maxi(_clock.total_minutes-_last_minute,0),building.definition.production_recipe.work_required)
	_last_minute = _clock.total_minutes
func _on_minute(_minute: int) -> void:
	if phase == Phase.NONE: return
	if not _valid():
		abort()
		return
	_accrue()
	if phase != Phase.WORKING or building.production_progress < building.definition.production_recipe.work_required: return
	_mutating = true
	var done: bool = building.resources.transform_reserved(_inputs,_outputs)
	if done:
		_inputs.clear()
		_outputs.clear()
		building.production_progress = 0
		if logger != null: logger.info(EventLog.PRODUCTION,"%s: recipe завершён — %s" % [_runtime.data.resident_name,building.display_name])
	_mutating = false
	var interrupted := _interrupted
	var previous := _cleanup()
	if previous != null and _runtime.intents.current_intent == previous:
		if done and not interrupted: _runtime.intents.clear_completed(previous)
		else: _runtime.intents.cancel_current(previous)
	if not done: _runtime.decision.call_deferred("request_decision","recipe_unavailable")
func _cleanup() -> Intent:
	_exiting = true
	_accrue()
	var previous: Intent = _intent
	_intent = null
	if building != null:
		for resource in _inputs: building.resources.release_out(resource,_inputs[resource])
		for resource in _outputs: building.resources.release_in(resource,_outputs[resource])
		if building.production_worker_id == _runtime.data.id: building.production_worker_id = ""
	_inputs.clear()
	_outputs.clear()
	building = null
	phase = Phase.NONE
	_interrupted = false
	_exiting = false
	_queue_availability()
	return previous
func abort() -> void:
	if building == null: return
	var previous := _cleanup()
	if previous != null and _runtime.intents.current_intent == previous: _runtime.intents.cancel_current(previous)
func _on_forced(_previous: Intent) -> void:
	if _mutating: _interrupted = true
	else: abort()
func _on_intent_changed(intent: Intent) -> void:
	if _exiting or _intent == null or intent == _intent: return
	if _mutating: _interrupted = true
	else: abort()
func _on_phase(phase_name: String) -> void:
	if phase_name != "День": abort()
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
