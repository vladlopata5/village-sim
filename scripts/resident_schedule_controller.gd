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
var before_work: Callable
var work_decision: Callable
var _locations: RefCounted
var _phase: String = ""
var is_night: bool:
	get: return _phase == "Ночь"
var _intents: IntentController

func setup(game_time: Node, locations: RefCounted, intents: IntentController) -> void:
	_locations = locations
	_intents = intents
	_intents.intent_completed.connect(_on_intent_completed)
	game_time.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(game_time.get_phase())

func request_manual_move(world_target: Vector2) -> bool:
	# Keep work/sleep protected even after their movement intent has completed.
	if _phase not in ["Утро", "Вечер"] or _intents.resident_data.activity in [Activity.Type.EATING, Activity.Type.RESTING, Activity.Type.SLEEPING, Activity.Type.TALKING, Activity.Type.RELAXING]:
		return false
	return _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", world_target, MANUAL_PRIORITY, true))

func _on_phase_changed(phase: String) -> void:
	var changed_phase := phase != _phase
	_phase = phase
	# A route belonging to the previous phase must not finish in the new phase.
	_intents.clear_reason(&"day_work")
	_intents.clear_reason(&"night_home")
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
			if work_decision.is_valid():
				_intents.clear_reason(&"manual_move")
				work_decision.call()
				return
			if data.work_location_id.is_empty() or data.profession == preload("res://scripts/resident_profession.gd").Type.NONE:
				_intents.clear_reason(&"manual_move")
			else:
				_move_to_location(data.work_location_id, &"day_work", WORK_PRIORITY)
		"Ночь": _move_to_location(data.home_location_id, &"night_home", HOME_PRIORITY)

func _move_to_location(location_id: StringName, reason: StringName, priority: int) -> void:
	if reason == &"day_work" and before_work.is_valid() and not before_work.call():
		return
	var target: Variant = _locations.get_position(location_id)
	# An absent place must not silently become a goal at world origin.
	if target is Vector2:
		var previously_working := logger != null and logger.was_working(_intents.resident_data)
		var accepted := _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, reason, target, priority, true))
		if accepted and logger != null:
			logger.sync_activity(_intents.resident_data)
			if reason == &"night_home": logger.info(EventLog.SCHEDULE, "%s: получил ночное намерение идти домой" % _intents.resident_data.resident_name)
			elif reason == &"day_work" and not previously_working: logger.info(EventLog.AI, "%s: выбрал работу (priority=%d)" % [_intents.resident_data.resident_name, WORK_PRIORITY])

func _on_intent_completed(intent: ResidentIntent) -> void:
	# Controller only reports accepted arrivals, never cancellations/stale goals.
	var data = _intents.resident_data
	if data == null:
		return
	if _phase == "День" and intent.reason_id == &"day_work":
		data.activity = Activity.Type.WORKING
	elif is_night and intent.reason_id == &"night_home":
		data.activity = Activity.Type.SLEEPING
	if logger != null: logger.sync_activity(data)

func resume_current_phase() -> void:
	_on_phase_changed(_phase)
