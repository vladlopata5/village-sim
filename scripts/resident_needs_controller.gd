extends Node
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Concrete ways to satisfy needs. Selection/comparison lives in DecisionController.
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Data = preload("res://scripts/resident_data.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const FoodAvailability = preload("res://scripts/food_availability.gd")
var food_availability: RefCounted
var _owns_food_availability := false
var sources: RefCounted
var position_provider: Callable
var ground_position_provider: Callable # Actual center, distinct from walkable portal route origin.
var exit_building_provider: Callable
enum MealMode { KITCHEN, OUTSIDE }
var _meal_mode := MealMode.KITCHEN
var _food_received := false # Paid action guard, not inventory/quantity.
var _food_source: Source
var _food_epoch := 0
var _probe_key: Array = []
var _probe_target: Source
var food_probe_count := 0
var food_route_checks := 0
var food_reservation_failures := 0
const FOOD = ResourceType.Type.FOOD
const MEAL_MINUTES := 30
const OUTSIDE_MEAL_MINUTES := 10
const REST_MINUTES := 10
const SLEEP_RECOVERY_TARGET := 20
signal meal_begun(building_id: StringName)
signal eat_started(intent: Intent)
signal eat_outcome(intent: Intent, outcome: StringName, target_id: StringName)
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
	if food_availability == null:
		food_availability = FoodAvailability.new()
		food_availability.setup(buildings, locations)
		_owns_food_availability = true
	for building in buildings: register_food_building(building)
	_available_food_amount = _count_available_food()

func try_eat(priority: int, critical_priority: int = 0) -> bool:
	if _intents.player_controlled: return false
	if critical_priority == 0 and _data.hunger < Modifiers.eat_threshold(_data): return false
	if _intents.forced_priority > critical_priority: return false
	if critical_priority > 0: return _try_critical_eat(priority, critical_priority)
	if _active_intent != null and _active_intent.reason_id == &"eat": return true
	if _food_unavailable and _search_key(false) == _probe_key: return false
	food_search_count += 1
	var target := _select_food_source(false)
	return _begin_food_source(target,priority,0) if target != null else _eat_unavailable(0)

func _try_critical_eat(priority: int, critical_priority: int) -> bool:
	# Paid meals survive disappearance of the consumed Ground object too.
	if _food_received and _active_intent == _intents.current_intent:
		return _merge_critical_eat(critical_priority)
	food_search_count += 1
	var target := _select_food_source(true)
	if target == null: return _eat_unavailable(critical_priority)
	if _same_food_source(target,_food_source) and _reserved_food and _food_target_valid():
		return _merge_critical_eat(critical_priority)
	return _begin_food_source(target,priority,critical_priority)

func _select_critical_eat_target() -> RefCounted:
	var target := _select_food_source(true)
	return get_food_target(target.id) if target != null and target.kind == Source.Kind.CONTAINER else null

func is_current_eat_compatible(building: RefCounted) -> bool:
	if building == null or _food_building != building or _active_intent == null: return false
	if _active_intent != _intents.current_intent or _active_intent.reason_id != &"eat": return false
	return _food_received or (_reserved_food and _food_target_valid())

func _merge_critical_eat(critical_priority: int) -> bool:
	if not _intents.retain_current_as_critical(_active_intent, critical_priority): return false
	if logger != null:
		logger.info(EventLog.NEED, "%s: critical hunger совпал с текущим EAT (%s) — действие продолжается" % [_data.resident_name, _source_label()])
	return true

func _eat_unavailable(critical_priority: int) -> bool:
	_food_unavailable = true
	var message := "%s не удалось поесть: нет доступной еды." % _data.resident_name
	developer_message.emit(message)
	if logger != null: logger.info(EventLog.NEED, message + " Не удалось зарезервировать 1 FOOD.")
	if critical_priority > 0:
		_cancel_own_action()
		_intents.force_set_intent(Intent.new(), critical_priority)
		if logger != null: logger.sync_activity(_data)
	return false

func has_target_food_action(target_id: StringName) -> bool:
	if _data.hunger < Balance.EAT_MIN_HUNGER: return false
	var building = get_food_target(target_id)
	return building != null and _building_food_access(building,true) and building.resources.get_available_amount(FOOD)>0 and _food_reachable(_locations.get_position(target_id))

func get_food_target(target_id: StringName):
	for building in _buildings:
		if building.id == target_id and building.is_built() and building.resources.allows_resource(FOOD) and building.resources.get_capacity(FOOD)>0: return building
	return null

func try_eat_at(target_id: StringName, priority: int) -> bool:
	if _intents.player_controlled or _intents.has_current_action() or not has_target_food_action(target_id): return false
	return _begin_food_source(Source.new(Source.Kind.CONTAINER,target_id),priority,0,true)

func _start_reserved_meal(building: RefCounted, target: Vector2, priority: int, critical_priority: int) -> bool:
	_cancel_own_action()
	_food_building = building
	_food_source = Source.new(Source.Kind.CONTAINER,building.id)
	return _start_food_intent(target,priority,critical_priority)

func cancel_eat(intent: Intent) -> bool:
	if intent == null or intent != _active_intent: return false
	_cancel_own_action()
	_intents.cancel_current(intent)
	action_unavailable.emit()
	return true

func try_rest(priority: int, critical_priority: int = 0) -> bool:
	if _intents.player_controlled: return false
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
	if critical_priority > 0:
		_data.start_sleep(Balance.OUTDOOR_SLEEP_QUALITY)
		if logger != null: logger.debug(EventLog.NEED, "%s: критическая усталость — уснул на месте, quality=%.2f" % [_data.resident_name, _data.current_sleep_quality])
	else:
		_data.activity = Activity.Type.RESTING
	if logger != null: logger.sync_activity(_data)
	return true

func _on_arrival(intent: Intent) -> void:
	if intent != _active_intent or intent.reason_id != &"eat" or _food_received:
		return
	# Consume once at the beginning: gradual benefit can never be free.
	if not _reserved_food or not _food_target_valid():
		_abort_unavailable()
		return
	intent.interruptible = false
	_food_received = true # Guard synchronous pickup/exit/critical signals.
	_reserved_food = false
	if not _consume_food():
		_abort_unavailable()
		return
	if _active_intent != intent or _intents.current_intent != intent:
		return # A critical event during consumption already replaced this action.
	if _meal_mode == MealMode.OUTSIDE and _food_building != null:
		# Existing world portal moves outside before releasing the original marker.
		var exited: bool = exit_building_provider.call(intent) if exit_building_provider.is_valid() else _locations.get("uses") == null
		if _active_intent != intent or _intents.current_intent != intent: return
		if not exited:
			_abort_unavailable()
			return
	_start_eating(intent)

func _start_eating(intent: Intent) -> void:
	if _meal_active or not _food_received or _active_intent != intent or _intents.current_intent != intent: return
	_meal_active = true
	_started_at = _clock.total_minutes
	_minutes_left = MEAL_MINUTES if _meal_mode == MealMode.KITCHEN else OUTSIDE_MEAL_MINUTES
	_data.activity = Activity.Type.EATING
	if _active_intent != intent or _intents.current_intent != intent: return
	meal_begun.emit(meal_location_id())
	if _active_intent != intent or _intents.current_intent != intent: return
	if logger != null:
		logger.sync_activity(_data)
		logger.info(EventLog.NEED, "%s: начал есть (HUNGER=%d, utility=%.0f)" % [_data.resident_name, _data.hunger, float(intent.priority)])

func _on_minute_changed(minute: int) -> void:
	if _active_intent == null:
		return
	if _active_intent.reason_id == &"eat" and not _meal_active:
		if not _food_received and not _food_target_valid():
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
	_food_received = false
	_minutes_left = 0
	if completed.reason_id == &"eat":
		var completed_source: StringName = _food_source.id
		_food_source = null
		_food_building = null
		eat_outcome.emit(completed, &"completed", completed_source)
	_intents.clear_completed(completed)
	if logger != null: logger.sync_activity(_data)

func _on_intent_changed(intent: Intent) -> void:
	if _active_intent != null and intent != _active_intent:
		_cancel_own_action()

func _cancel_own_action() -> void:
	if _meal_active and logger != null: logger.info(EventLog.NEED, "%s: приём пищи прерван" % _data.resident_name)
	var previous_intent := _active_intent
	var release_food := _reserved_food
	var previous_building := _food_building
	var previous_source := _food_source
	# Clear ownership before resource callbacks can wake another hungry resident.
	_reserved_food = false
	_active_intent = null
	_meal_active = false
	_food_received = false
	_minutes_left = 0
	_food_source = null
	_food_building = null
	if previous_intent != null and previous_intent.reason_id == &"eat": eat_outcome.emit(previous_intent, &"interrupted", previous_source.id)
	if release_food:
		if previous_source.kind == Source.Kind.GROUND: sources.release(previous_source,FOOD,_food_owner())
		elif previous_building != null: previous_building.resources.release_out(FOOD,1)

func _abort_unavailable() -> void:
	if logger != null: logger.info(EventLog.NEED, "%s: действие еды стало недоступно — новая decision point" % _data.resident_name)
	var old := _active_intent
	var id: StringName = _food_source.id
	var exists: bool = sources.resolve(_food_source) != null if _food_source.kind == Source.Kind.GROUND else _buildings.has(_food_building)
	eat_outcome.emit(old, &"unavailable" if exists else &"removed", id)
	_cancel_own_action()
	_intents.cancel_current(old)
	action_unavailable.emit()

func _count_available_food() -> int:
	return food_availability.total()

func can_try_eat() -> bool:
	return _data.hunger >= Modifiers.eat_threshold(_data) and (not _food_unavailable or _search_key(false) != _probe_key)

func has_food_action() -> bool:
	return _data.hunger >= Modifiers.eat_threshold(_data) and _select_food_source(false) != null

func _on_food_availability_changed(resource: ResourceType.Type, _amount: int) -> void:
	if resource != FOOD or _exiting: return
	var previous := _available_food_amount
	_available_food_amount = _count_available_food()
	if _available_food_amount != previous: _food_epoch += 1
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
	if sources != null: sources.changed.disconnect(_food_world_changed)
	if _owns_food_availability: food_availability.dispose()

func _food_target_valid() -> bool:
	if _food_source == null or _active_intent == null: return false
	var target: Variant
	if _food_source.kind == Source.Kind.GROUND:
		if sources == null or not sources.reserved(_food_source,FOOD,_food_owner()): return false
		target = sources.point(_food_source)
	else:
		if not _buildings.has(_food_building) or not _food_building.is_built() or _food_building.resources.get_reserved_out(FOOD)<1: return false
		target = _locations.get_position(_food_source.id)
	return target is Vector2 and target.is_equal_approx(_active_intent.target_position)

func has_location(location_id: StringName) -> bool:
	return _locations.get_position(location_id) is Vector2

func register_food_building(building: RefCounted) -> void:
	food_availability.register_building(building)
	if not building.resources.availability_changed.is_connected(_on_food_availability_changed): building.resources.availability_changed.connect(_on_food_availability_changed)
	_on_food_availability_changed(FOOD,building.resources.get_available_amount(FOOD))

func meal_location_id() -> StringName:
	# Only actual Kitchen meals have the existing indoor MEAL context.
	return _food_source.id if _meal_active and _meal_mode == MealMode.KITCHEN and _food_source != null else &""

func get_hunger_eating_rate() -> int:
	# NeedDynamics owns fixed-point rounding/clamping; this active action supplies its rate.
	if not _meal_active: return 0
	return -120 if _meal_mode == MealMode.KITCHEN else -360

func _has_visitor_room() -> bool:
	return _select_food_source(false) != null

func bind_sources(provider: RefCounted) -> void:
	if sources != null and sources != provider: sources.changed.disconnect(_food_world_changed)
	sources = provider
	food_availability.bind_sources(provider)
	if not sources.changed.is_connected(_food_world_changed): sources.changed.connect(_food_world_changed)
	var uses: RefCounted = _locations.get("uses")
	if uses != null:
		if not uses.slots_changed.is_connected(_food_slots_changed): uses.slots_changed.connect(_food_slots_changed)
		if not uses.removed.is_connected(_food_building_removed): uses.removed.connect(_food_building_removed)
	_food_world_changed()
func _food_slots_changed(_id: StringName, purpose: int) -> void:
	if purpose == Purpose.VISITOR: _food_epoch += 1
	# Availability at the next boundary reflects current marker occupancy.
func _food_world_changed() -> void:
	if _exiting: return
	# A deferred notification may describe changes already observed by a probe.
	# Do not invalidate it again solely because the notification arrived later.
	var previous := _available_food_amount
	_available_food_amount = _count_available_food()
	if _available_food_amount != previous: _food_epoch += 1
	if _available_food_amount > previous:
		_food_unavailable = false
		food_available.emit()
	if _active_intent != null and _active_intent.reason_id == &"eat" and not _meal_active and _reserved_food and not _food_target_valid(): _abort_unavailable()
func _food_owner() -> StringName: return StringName("meal:" + _data.id)
func _same_food_source(a: Source,b: Source) -> bool:
	return a != null and b != null and a.stable_key() == b.stable_key()
func _source_label() -> String:
	return _food_building.display_name if _food_building != null else "FOOD на земле"
func _food_origin() -> Variant:
	return position_provider.call(_data.id) if position_provider.is_valid() else null
func _ground_origin() -> Variant:
	return ground_position_provider.call(_data.id) if ground_position_provider.is_valid() else _food_origin()
func _search_key(critical: bool) -> Array:
	var navigation: RefCounted = _locations.get("navigation")
	return [_food_epoch,sources.revision if sources != null else 0,navigation.revision if navigation != null else 0,_food_origin() if _available_food_amount > 0 or _probe_target != null else null,_ground_origin(),critical]
func _food_reachable(target: Vector2) -> bool:
	if not target.is_finite(): return false
	var origin: Variant = _food_origin()
	if not origin is Vector2 or sources == null: return true # Isolated controller fixtures without a bound source registry.
	if not origin.is_finite(): return false
	food_route_checks += 1
	return sources.reachable(origin,target)
func _building_food_access(building: RefCounted, allow_busy_visitor: bool) -> bool:
	if not building.is_built() or not building.resources.allows_resource(FOOD) or building.resources.get_capacity(FOOD)<1 or not _locations.get_position(building.id) is Vector2: return false
	var uses: RefCounted = _locations.get("uses")
	if uses == null: return true
	if building.type == BuildingType.Type.FOOD:
		return allow_busy_visitor or not uses.choices(building.id,Purpose.VISITOR,Vector3.ZERO).is_empty()
	# Busy COURIER waits through the existing executor; no occupancy snapshot is cached.
	return uses.courier_position(building.id) is Vector3
func _source_available(ref: Source, critical: bool, explicit_target: bool = false) -> bool:
	if ref.kind == Source.Kind.GROUND:
		return sources != null and ((critical and _same_food_source(ref,_food_source) and sources.reserved(ref,FOOD,_food_owner())) or (sources.ground_allowed(ref,_ground_origin()) and sources.available(ref,FOOD)))
	var building = get_food_target(ref.id)
	var compatible: bool = building != null and critical and is_current_eat_compatible(building)
	return building != null and _building_food_access(building,compatible or explicit_target) and (building.resources.get_available_amount(FOOD)>0 or compatible)
func _select_food_source(critical: bool) -> Source:
	var key := _search_key(critical)
	if key == _probe_key and (_probe_target == null or _source_available(_probe_target,critical)):
		if _probe_target != null: _food_unavailable = false
		return _probe_target
	_probe_key = key
	_probe_target = null
	food_probe_count += 1
	for kitchen_tier in [true,false]:
		for building in _buildings:
			if (building.type == BuildingType.Type.FOOD) != kitchen_tier: continue
			var ref := Source.new(Source.Kind.CONTAINER,building.id)
			if _source_available(ref,critical) and _food_reachable(_locations.get_position(building.id)):
				_probe_target = ref
				_probe_key = _search_key(critical)
				_food_unavailable = false
				return ref
	if sources == null or not is_instance_valid(sources.ground): return null
	var candidates: Array = []
	# Retained emergency meal is committed; movement cannot invalidate it.
	if critical and _food_source != null and _food_source.kind == Source.Kind.GROUND and _source_available(_food_source,true): candidates.append(_food_source)
	candidates.append_array(sources.ground_candidates(FOOD,_ground_origin())) # Owned meal is excluded from free candidates.
	var origin: Variant = _food_origin()
	if origin is Vector2:
		candidates.sort_custom(func(a,b):
			var da: float = origin.distance_squared_to(sources.point(a))
			var db: float = origin.distance_squared_to(sources.point(b))
			return String(a.id)<String(b.id) if da==db else da<db)
	for ref in candidates:
		if _food_reachable(sources.point(ref)):
			_probe_target = ref
			_probe_key = _search_key(critical)
			_food_unavailable = false
			return ref
	return null
func _begin_food_source(ref: Source, priority: int, critical_priority: int, explicit_target: bool = false) -> bool:
	if ref == null or not _source_available(ref,critical_priority>0,explicit_target): return false
	var building = get_food_target(ref.id) if ref.kind == Source.Kind.CONTAINER else null
	var target: Vector2 = _locations.get_position(ref.id) if building != null else sources.point(ref)
	var reserved: bool = building.resources.reserve_out(FOOD,1) if building != null else sources.reserve(ref,FOOD,_food_owner())
	if not reserved:
		food_reservation_failures += 1
		return _eat_unavailable(critical_priority)
	# Resource callbacks can remove a source synchronously during reservation.
	var still_valid: bool = _buildings.has(building) and building.is_built() and _locations.get_position(building.id) is Vector2 if building != null else sources.reserved(ref,FOOD,_food_owner()) and sources.ground_allowed(ref,_ground_origin())
	if not still_valid:
		if building != null: building.resources.release_out(FOOD,1)
		else: sources.release(ref,FOOD,_food_owner())
		return _eat_unavailable(critical_priority)
	_cancel_own_action()
	_food_source = ref
	_food_building = building
	return _start_food_intent(target,priority,critical_priority)
func _start_food_intent(target: Vector2, priority: int, critical_priority: int) -> bool:
	_reserved_food = true
	_meal_mode = MealMode.KITCHEN if _food_building != null and _food_building.type == BuildingType.Type.FOOD else MealMode.OUTSIDE
	_active_intent = Intent.new(Intent.Type.MOVE_TO,&"eat",target,priority,true)
	if _food_building != null and _locations.has_method("configure_intent"):
		_locations.configure_intent(_active_intent,_food_source.id,Purpose.VISITOR if _food_building.type==BuildingType.Type.FOOD else Purpose.COURIER,_data.id)
	var started := _active_intent
	eat_started.emit(started)
	if _active_intent != started: return false
	if not _food_target_valid():
		_cancel_own_action()
		return false
	var accepted: bool = _intents.force_set_intent(started,critical_priority) if critical_priority>0 else _intents.submit(started)
	if not accepted and _active_intent == started: _cancel_own_action()
	if logger != null: logger.sync_activity(_data)
	return accepted
func _consume_food() -> bool:
	return _food_building.resources.take_reserved(FOOD,1) if _food_building != null else sources.pickup(_food_source,FOOD,_food_owner())

func _food_building_removed(_id: StringName) -> void:
	_food_world_changed()
