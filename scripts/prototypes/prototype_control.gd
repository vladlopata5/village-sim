extends Node
## Domain side of the slice. No meshes, transforms or navigation implementation.
const Data = preload("res://scripts/resident_data.gd")
const Command = preload("res://scripts/player_command.gd")
const Activity = preload("res://scripts/resident_activity.gd")
signal movement_requested(destination: Vector2)
signal stop_requested
var resident: Data
var selection: Node
var current_command: Command
var _next_command_id := 1
func move_to(destination: Vector2) -> bool:
	if resident == null or selection.selected_resident != resident or not destination.is_finite(): return false
	cancel_move()
	current_command = Command.new(StringName("prototype_move_%04d" % _next_command_id), resident.id, destination)
	_next_command_id += 1
	resident.activity = Activity.Type.MOVING
	movement_requested.emit(destination)
	return true
func arrived() -> void:
	if current_command == null or current_command.state != Command.State.ACTIVE: return
	current_command.state = Command.State.COMPLETED
	resident.activity = Activity.Type.IDLE
func cancel_move() -> void:
	if current_command == null or current_command.state != Command.State.ACTIVE: return
	current_command.state = Command.State.CANCELLED
	resident.activity = Activity.Type.IDLE
	stop_requested.emit()
