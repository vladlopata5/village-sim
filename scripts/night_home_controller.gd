extends Node
## Fixed decision source: creates intents, never commands a visual object.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const HOME_PRIORITY := 100
const MANUAL_PRIORITY := 10
var home_position: Vector2 = Vector2.ZERO
var is_night: bool = false
var _intents: IntentController

func setup(game_time: Node, home_point: Vector2, intents: IntentController) -> void:
	home_position = home_point
	_intents = intents
	game_time.phase_changed.connect(_on_phase_changed)
	_on_phase_changed(game_time.get_phase())

func request_manual_move(world_target: Vector2) -> bool:
	# This rule also keeps the resident at home after the night intent completes.
	if is_night:
		return false
	return _intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", world_target, MANUAL_PRIORITY))

func _on_phase_changed(phase: String) -> void:
	var was_night := is_night
	is_night = phase == "Ночь"
	if is_night:
		_intents.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"night_home", home_position, HOME_PRIORITY))
	elif was_night:
		_intents.release_priority(&"night_home")
