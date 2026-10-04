extends Node
## Fixed decision source: creates intents, never commands a visual object.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const HOME_PRIORITY := 100
const MANUAL_PRIORITY := 10
var _locations: RefCounted
var is_night: bool = false
var _intents: IntentController

func setup(game_time: Node, locations: RefCounted, intents: IntentController) -> void:
	_locations = locations
	_intents = intents
	_intents.intent_completed.connect(_on_intent_completed)
	game_time.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(game_time.get_phase())

func request_manual_move(world_target: Vector2) -> bool:
	# This rule also keeps the resident at home after the night intent completes.
	if is_night:
		return false
	return _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", world_target, MANUAL_PRIORITY))

func _on_phase_changed(phase: String) -> void:
	is_night = phase == "Ночь"
	if is_night:
		if _intents.resident_data == null:
			return
		var target: Variant = _locations.get_position(_intents.resident_data.home_location_id)
		# Missing home must not silently send the resident to world origin.
		if target is Vector2:
			_intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"night_home", target, HOME_PRIORITY))
	elif phase == "Утро":
		_intents.clear_reason(&"night_home")
		if _intents.resident_data != null and _intents.resident_data.activity == Activity.Type.SLEEPING:
			_intents.resident_data.activity = Activity.Type.IDLE

func _on_intent_completed(intent: ResidentIntent) -> void:
	# Only an accepted arrival, never cancellation or a stale view notification.
	if is_night and intent.reason_id == &"night_home" and _intents.resident_data != null:
		_intents.resident_data.activity = Activity.Type.SLEEPING
