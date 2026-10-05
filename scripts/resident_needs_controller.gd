extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Concrete ways to satisfy needs. Selection/comparison lives in DecisionController.
const Balance = preload("res://scripts/balance_config.gd")
const Data = preload("res://scripts/resident_data.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const FOOD = ResourceType.Type.FOOD
const MEAL_MINUTES := 30
const REST_MINUTES := 10
const SLEEP_RECOVERY_TARGET := 20
signal action_unavailable
signal food_available
signal developer_message(message: String)
var decision: Node
var _data: Data
var _clock: Node
var _buildings: Array
var _locations: RefCounted
var _intents: Node
var _food_building: RefCounted
var _active_intent: Intent
var _reserved_food := false
var _meal_active := false
var _started_at := 0
var _minutes_left := 0
var _food_unavailable := false
var _available_food_amount := 0
var food_search_count := 0
var _exiting := false

func setup(clock: Node, data: Data, buildings: Array, locations: RefCounted, intents: Node, _schedule: Node) -> void:
	_clock = clock
	_data = data
	_buildings = buildings
	_locations = locations
	_intents = intents
	clock.minute_changed.connect(_on_minute_changed)
	intents.intent_changed.connect(_on_intent_changed)
	intents.intent_arrived.connect(_on_arrival)
	for building in buildings:
		if building.type == BuildingType.Type.FOOD:
			building.resources.availability_changed.connect(_on_food_availability_changed)
	_available_food_amount = _count_available_food()

func try_eat(priority: int, critical_priority: int = 0) -> bool:
	if critical_priority == 0 and _data.hunger < Balance.EAT_MIN_HUNGER: return false
	if _intents.forced_priority > critical_priority:
		return false
	if _active_intent != null and _active_intent.reason_id == &"eat":
		if critical_priority > _intents.forced_priority:
			_intents.force_set_intent(_active_intent, critical_priority)
			if _meal_active: _data.activity = Activity.Type.EATING
		return true
	if _food_unavailable:
		if critical_priority > 0:
			_cancel_own_action()
			_intents.force_set_intent(Intent.new(), critical_priority)
		return false
	food_search_count += 1
	for building in _buildings:
		if building.type != BuildingType.Type.FOOD:
			continue
		var target: Variant = _locations.get_position(building.id)
		if not target is Vector2 or not building.resources.reserve_out(FOOD, 1):
			continue
		_cancel_own_action()
		_food_building = building
		_reserved_food = true
		_active_intent = Intent.new(Intent.Type.MOVE_TO, &"eat", target, priority, true)
		var accepted: bool = _intents.force_set_intent(_active_intent, critical_priority) if critical_priority > 0 else _intents.submit(_active_intent)
		if not accepted: _cancel_own_action()
		if logger != null: logger.sync_activity(_data)
		return accepted
	_food_unavailable = true
	var message := "%s не удалось поесть: нет доступной еды." % _data.resident_name
	developer_message.emit(message)
	if logger != null: logger.info(EventLog.NEED, message + " Не удалось зарезервировать 1 FOOD.")
	if critical_priority > 0:
		_cancel_own_action()
		_intents.force_set_intent(Intent.new(), critical_priority)
		if logger != null: logger.sync_activity(_data)
	return false

func try_rest(priority: int, critical_priority: int = 0) -> bool:
	if _intents.forced_priority > critical_priority:
		return false
	_cancel_own_action()
	var reason: StringName = &"critical_sleep" if critical_priority > 0 else &"rest"
	_active_intent = Intent.new(Intent.Type.NONE, reason, Vector2.ZERO, priority, true)
	var accepted: bool = _intents.force_set_intent(_active_intent, critical_priority) if critical_priority > 0 else _intents.submit(_active_intent)
	if not accepted:
		_cancel_own_action()
		return false
	_started_at = _clock.total_minutes
	_minutes_left = REST_MINUTES
	_data.activity = Activity.Type.SLEEPING if critical_priority > 0 else Activity.Type.RESTING
	if logger != null: logger.sync_activity(_data)
	return true

func _on_arrival(intent: Intent) -> void:
	if intent != _active_intent or intent.reason_id != &"eat" or _meal_active:
		return
	# Consume once at the beginning: gradual benefit can never be free.
	if not _reserved_food or not _food_target_valid():
		_abort_unavailable()
		return
	intent.interruptible = false
	_meal_active = true # Guard synchronous container/critical signals.
	_reserved_food = false
	if not _food_building.resources.take_reserved(FOOD, 1):
		_abort_unavailable()
		return
	if _active_intent != intent or _intents.current_intent != intent:
		return # A critical event during consumption already replaced this action.
	_started_at = _clock.total_minutes
	_minutes_left = MEAL_MINUTES
	_data.activity = Activity.Type.EATING
	if logger != null:
		logger.sync_activity(_data)
		logger.info(EventLog.NEED, "%s: начал есть (HUNGER=%d, priority=%d)" % [_data.resident_name, _data.hunger, _data.get_need(preload("res://scripts/need_type.gd").Type.HUNGER).get_priority()])

func _on_minute_changed(minute: int) -> void:
	if _active_intent == null:
		return
	if _active_intent.reason_id == &"eat" and not _meal_active:
		if not _food_target_valid() or _food_building.resources.get_reserved_out(FOOD) < 1:
			_abort_unavailable()
		return
	if minute <= _started_at:
		return
	if _active_intent.reason_id == &"critical_sleep":
		if _data.fatigue <= SLEEP_RECOVERY_TARGET: _finish()
	else:
		_minutes_left -= 1
		if _minutes_left <= 0: _finish()

func _finish() -> void:
	var completed := _active_intent
	if _meal_active and logger != null: logger.info(EventLog.NEED, "%s: закончил есть" % _data.resident_name)
	_active_intent = null
	_meal_active = false
	_minutes_left = 0
	_intents.clear_completed(completed)
	if logger != null: logger.sync_activity(_data)

func _on_intent_changed(intent: Intent) -> void:
	if _active_intent != null and intent != _active_intent:
		_cancel_own_action()

func _cancel_own_action() -> void:
	if _meal_active and logger != null: logger.info(EventLog.NEED, "%s: приём пищи прерван" % _data.resident_name)
	var release_food := _reserved_food
	var previous_building := _food_building
	# Clear owned state before release emits availability and can wake another resident.
	_reserved_food = false
	_active_intent = null
	_meal_active = false
	_minutes_left = 0
	if release_food: previous_building.resources.release_out(FOOD, 1)

func _abort_unavailable() -> void:
	if logger != null: logger.info(EventLog.NEED, "%s: действие еды стало недоступно — новая decision point" % _data.resident_name)
	var old := _active_intent
	_cancel_own_action()
	_intents.cancel_current(old)
	action_unavailable.emit()

func _count_available_food() -> int:
	var total := 0
	for building in _buildings:
		if building.type == BuildingType.Type.FOOD and _locations.get_position(building.id) is Vector2:
			total += building.resources.get_available_amount(FOOD)
	return total

func can_try_eat() -> bool:
	return _data.hunger >= Balance.EAT_MIN_HUNGER and not _food_unavailable

func has_food_action() -> bool:
	return can_try_eat() and _count_available_food() > 0

func _on_food_availability_changed(resource: ResourceType.Type, _amount: int) -> void:
	if resource != FOOD or _exiting: return
	var previous := _available_food_amount
	_available_food_amount = _count_available_food()
	if logger != null: logger.debug(EventLog.RESOURCE, "%s: FOOD availability %d → %d" % [_data.resident_name, previous, _available_food_amount])
	if _available_food_amount > previous:
		_food_unavailable = false
		food_available.emit()

func evaluate(at_action_boundary: bool = false) -> void:
	if is_instance_valid(decision):
		if at_action_boundary: decision.request_decision("action_boundary")
		else: decision.check_critical()

func prepare_for_work() -> bool:
	return decision.prepare_for_work() if is_instance_valid(decision) else true

func _exit_tree() -> void:
	_exiting = true
	_cancel_own_action()

func _food_target_valid() -> bool:
	var target: Variant = _locations.get_position(_food_building.id)
	return target is Vector2 and target.is_equal_approx(_active_intent.target_position)

func has_location(location_id: StringName) -> bool:
	return _locations.get_position(location_id) is Vector2
