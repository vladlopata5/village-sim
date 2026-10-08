extends Node
## Presentation executor. It knows nothing about resident data, selection or commands.
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
signal arrived
@export var speed: float = 3.0
var body: Node3D
var _target := Vector3.ZERO
var _moving := false
func set_target(world_position: Vector3) -> void:
	_target = Coordinates.on_ground(world_position)
	_moving = true
	advance(0.0)
func stop() -> void:
	_moving = false
func is_moving() -> bool: return _moving
func target_position() -> Vector3: return _target
func _physics_process(delta: float) -> void:
	advance(delta)
func advance(delta: float) -> void:
	if not _moving or not is_instance_valid(body): return
	var point := Coordinates.on_ground(body.global_position)
	body.global_position = point.move_toward(_target, speed * maxf(delta, 0.0))
	if body.global_position.is_equal_approx(_target):
		body.global_position = _target
		_moving = false
		arrived.emit()
