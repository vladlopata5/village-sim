extends Node
## Follows world-space paths. No gameplay state, cell IDs or AStar backend access.
signal arrived
signal failed
signal path_changed(points: PackedVector3Array)
var body: Node3D
var navigation: RefCounted
var speed: float = 1.0
var raw_path := PackedVector3Array()
var _path := PackedVector3Array()
var _target := Vector3.ZERO
var _moving := false
var _pending := false
var _index := 0
var _revision := -1
func set_target(world_position: Vector3) -> void:
	_target = world_position
	_moving = true
	_pending = true # Plan on advance, after intent ownership is established.
	raw_path.clear()
	_path.clear()
	path_changed.emit(_path)
func stop() -> void:
	_moving = false
	_pending = false
	raw_path.clear()
	_path.clear()
	path_changed.emit(_path)
func is_moving() -> bool: return _moving
func current_path() -> PackedVector3Array: return _path
func target_position() -> Vector3: return _target
func advance(delta: float) -> void:
	if not _moving: return
	if not is_instance_valid(body) or navigation == null or not _target.is_finite():
		_fail()
		return
	if _pending or _revision != navigation.revision:
		raw_path = navigation.find_raw_path(body.global_position,_target)
		_path = navigation.smooth_path(raw_path)
		_pending = false
		_revision = navigation.revision
		_index = 1
		if _path.is_empty():
			_fail()
			return
		path_changed.emit(_path)
	var remaining := maxf(delta,0.0) * maxf(speed,0.0)
	# Consume distance across waypoints, so x20 cannot lose time at cell edges.
	while _index < _path.size():
		var waypoint := _path[_index]
		var distance := body.global_position.distance_to(waypoint)
		if distance > remaining:
			body.global_position = body.global_position.move_toward(waypoint,remaining)
			return
		body.global_position = waypoint
		remaining -= distance
		_index += 1
	stop()
	arrived.emit()
func _fail() -> void:
	stop()
	failed.emit()
