extends Node
## One fixed time reaction, independent of resident data, rendering and UI.
signal movement_requested(world_target: Vector2)
var home_position: Vector2 = Vector2.ZERO
var is_night: bool = false

func setup(game_time: Node, home_point: Vector2) -> void:
	home_position = home_point
	game_time.phase_changed.connect(_on_phase_changed)
	# Also apply the rule if this controller is created during the night.
	_on_phase_changed(game_time.get_phase())

func request_manual_move(world_target: Vector2) -> bool:
	if is_night:
		return false
	movement_requested.emit(world_target)
	return true

func _on_phase_changed(phase: String) -> void:
	is_night = phase == "Ночь"
	if is_night:
		movement_requested.emit(home_position)
