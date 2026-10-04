extends Node
## One phase-based schedule source; intents and presentation stay separate.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const HOME_PRIORITY := 100
const WORK_PRIORITY := 50
const MANUAL_PRIORITY := 10
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
	if _phase not in ["Утро", "Вечер"]:
		return false
	return _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", world_target, MANUAL_PRIORITY))

func _on_phase_changed(phase: String) -> void:
	_phase = phase
	# A route belonging to the previous phase must not finish in the new phase.
	_intents.clear_reason(&"day_work")
	_intents.clear_reason(&"night_home")
	var data = _intents.resident_data
	if data == null:
		return
	if data.activity in [Activity.Type.WORKING, Activity.Type.SLEEPING]:
		data.activity = Activity.Type.IDLE
	match phase:
		"День": _move_to_location(data.work_location_id, &"day_work", WORK_PRIORITY)
		"Ночь": _move_to_location(data.home_location_id, &"night_home", HOME_PRIORITY)

func _move_to_location(location_id: StringName, reason: StringName, priority: int) -> void:
	var target: Variant = _locations.get_position(location_id)
	# An absent place must not silently become a goal at world origin.
	if target is Vector2:
		_intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, reason, target, priority))

func _on_intent_completed(intent: ResidentIntent) -> void:
	# Controller only reports accepted arrivals, never cancellations/stale goals.
	var data = _intents.resident_data
	if data == null:
		return
	if _phase == "День" and intent.reason_id == &"day_work":
		data.activity = Activity.Type.WORKING
	elif is_night and intent.reason_id == &"night_home":
		data.activity = Activity.Type.SLEEPING
