extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## One phase-based schedule source; intents and presentation stay separate.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const HOME_PRIORITY := 10000
const WORK_PRIORITY := preload("res://scripts/balance_config.gd").WORK_PRIORITY
const MANUAL_PRIORITY := 10
const Balance = preload("res://scripts/balance_config.gd")
var before_work: Callable
var work_decision: Callable
var _locations: RefCounted
var _phase: String = ""
const Building = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
var _buildings: Array = []
var _night_intent: ResidentIntent
var _night_started := false
var _sleep_home_id: StringName = &""
var is_night: bool:
	get: return _phase == "Ночь"
var _intents: IntentController

func setup(game_time: Node, locations: RefCounted, intents: IntentController, buildings: Array = []) -> void:
	_locations = locations
	_intents = intents
	_buildings = buildings
	_intents.intent_changed.connect(_on_intent_changed)
	_intents.forced_interrupt.connect(_on_forced_interrupt)
	_intents.intent_completed.connect(_on_intent_completed)
	game_time.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(game_time.get_phase())

func request_manual_move(world_target: Vector2) -> bool:
	# Keep work/sleep protected even after their movement intent has completed.
	if _phase not in ["Утро", "Вечер"] or _intents.resident_data.activity in [Activity.Type.EATING, Activity.Type.RESTING, Activity.Type.SLEEPING, Activity.Type.TALKING, Activity.Type.RELAXING]:
		return false
	if _intents.current_intent.reason_id == &"wander": _intents.cancel_current(_intents.current_intent)
	return _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", world_target, MANUAL_PRIORITY, true))

func _on_phase_changed(phase: String) -> void:
	var changed_phase := phase != _phase
	_phase = phase
	if _intents.player_controlled: return # Track phase, defer AI until command completion.
	# A route belonging to the previous phase must not finish in the new phase.
	_intents.clear_reason(&"day_work")
	_intents.clear_reason(&"night_home")
	_intents.clear_reason(&"night_outdoor")
	if _intents.current_intent == _night_intent:
		_intents.cancel_current(_night_intent)
	_night_intent = null
	_night_started = false
	var data = _intents.resident_data
	if data == null:
		return
	# Eating retains its current intent until the meal is completed.
	if data.activity == Activity.Type.EATING and phase != "Ночь":
		return
	if data.activity in [Activity.Type.WORKING, Activity.Type.SLEEPING] and _intents.current_intent.reason_id != &"critical_sleep":
		data.activity = Activity.Type.IDLE
	if changed_phase and logger != null: logger.sync_activity(data)
	match phase:
		"День":
			if _intents.current_intent.reason_id == &"wander": _intents.cancel_current(_intents.current_intent)
			if work_decision.is_valid():
				_intents.clear_reason(&"manual_move")
				work_decision.call()
				return
			if data.work_location_id.is_empty() or data.profession == preload("res://scripts/resident_profession.gd").Type.NONE:
				_intents.clear_reason(&"manual_move")
			else:
				_move_to_location(data.work_location_id, &"day_work", WORK_PRIORITY)
		"Ночь": _request_night_sleep()

func _move_to_location(location_id: StringName, reason: StringName, priority: int) -> void:
	if reason == &"day_work" and before_work.is_valid() and not before_work.call():
		return
	var target: Variant = _locations.get_position(location_id)
	# An absent place must not silently become a goal at world origin.
	if target is Vector2:
		var accepted := _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, reason, target, priority, true))
		if accepted and logger != null:
			logger.sync_activity(_intents.resident_data)

func _on_intent_completed(intent: ResidentIntent) -> void:
	# Controller only reports accepted arrivals, never cancellations/stale goals.
	var data = _intents.resident_data
	if data == null:
		return
	if _phase == "День" and intent.reason_id == &"day_work":
		data.activity = Activity.Type.WORKING
	elif is_night and intent == _night_intent and intent.reason_id == &"night_home":
		# Quality uses the committed destination, never the newly assigned home.
		var home_available := _get_home_target(_sleep_home_id) is Vector2
		if not home_available and logger != null:
			logger.debug(EventLog.SCHEDULE, "%s: дом стал недоступен, спит снаружи на месте" % data.resident_name)
		_start_sleep(Balance.HOME_SLEEP_QUALITY if home_available else Balance.OUTDOOR_SLEEP_QUALITY, "дома" if home_available else "снаружи")
	if logger != null: logger.sync_activity(data)

func request_work() -> bool:
	var data = _intents.resident_data
	if _phase != "День" or data.work_location_id.is_empty(): return false
	_move_to_location(data.work_location_id, &"day_work", WORK_PRIORITY)
	return _intents.current_intent.reason_id == &"day_work" or data.activity == Activity.Type.WORKING

func get_phase() -> String:
	return _phase

func resume_current_phase() -> void:
	if is_night:
		_request_night_sleep()
	else:
		_on_phase_changed(_phase)

func _get_home_target(home_id: StringName) -> Variant:
	for building in _buildings:
		if building is Building and building.id == home_id and building.is_built() and building.type == BuildingType.Type.HOME and building.definition.housing_capacity > 0:
			var target: Variant = _locations.get_position(home_id)
			return target if target is Vector2 else building.position
	return null

func _configure_night_intent(intent: ResidentIntent) -> void:
	var target: Variant = _get_home_target(_intents.resident_data.home_location_id)
	intent.type = ResidentIntent.Type.MOVE_TO if target is Vector2 else ResidentIntent.Type.NONE
	intent.reason_id = &"night_home" if target is Vector2 else &"night_outdoor"
	if target is Vector2: intent.target_position = target

func _request_night_sleep() -> void:
	if _intents.player_controlled or _intents.resident_data.activity == Activity.Type.SLEEPING: return
	if _night_intent != null and (_intents.current_intent == _night_intent or _intents.pending_intent == _night_intent): return
	_night_started = false
	_night_intent = ResidentIntent.new(ResidentIntent.Type.NONE, &"night_outdoor", Vector2.ZERO, HOME_PRIORITY, true)
	_configure_night_intent(_night_intent)
	if not _intents.submit(_night_intent): _night_intent = null

func _on_intent_changed(intent: ResidentIntent) -> void:
	if intent != _night_intent or _night_started: return
	# A queued schedule intent is not a committed trip yet. Resolve housing when
	# it actually activates, before the presentation executor receives it.
	_configure_night_intent(intent)
	_night_started = true
	var data = _intents.resident_data
	_sleep_home_id = data.home_location_id if intent.reason_id == &"night_home" else &""
	if intent.type == ResidentIntent.Type.NONE:
		_start_sleep(Balance.OUTDOOR_SLEEP_QUALITY, "снаружи")
	else:
		data.activity = Activity.Type.MOVING
	if logger != null:
		if intent.reason_id == &"night_home":
			logger.info(EventLog.SCHEDULE, "%s: идёт спать домой — %s" % [data.resident_name, data.home_location_id])
		else:
			logger.info(EventLog.SCHEDULE, "%s: спит снаружи — дома нет или он недоступен" % data.resident_name)
			if not data.home_location_id.is_empty(): logger.debug(EventLog.SCHEDULE, "%s: назначенный дом недоступен, используется outdoor sleep" % data.resident_name)
		logger.sync_activity(data)

func _on_forced_interrupt(_previous: ResidentIntent) -> void:
	_night_intent = null
	_night_started = false
	_sleep_home_id = &""

func _start_sleep(quality: float, context: String) -> void:
	_intents.resident_data.start_sleep(quality)
	if logger != null:
		logger.debug(EventLog.SCHEDULE, "%s: начал спать %s, quality=%.2f" % [_intents.resident_data.resident_name, context, quality])
