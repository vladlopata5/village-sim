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
var _segments: Array[Dictionary] = []
var _spent := 0.0
var _revision := -1
func set_target(world_position: Vector3) -> void:
	_target = world_position
	_moving = true
	_pending = true # Plan on advance, after intent ownership is established.
	raw_path.clear()
	_path.clear()
	_segments.clear()
	_spent = 0.0
	path_changed.emit(_path)
func stop() -> void:
	_moving = false
	_pending = false
	raw_path.clear()
	_path.clear()
	_segments.clear()
	_spent = 0.0
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
		_index = 0
		_spent = 0.0
		_segments.clear()
		if _path.is_empty():
			_fail()
			return
		for index in range(1,_path.size()):
			_segments.append_array(navigation.traversal_segments(_path[index-1],_path[index]))
		path_changed.emit(_path)
	var remaining := maxf(delta,0.0) * maxf(speed,0.0)
	# Budget is elapsed time * base speed. Crossing slow cells consumes more of
	# that budget; consume all boundaries so large x20 steps remain FPS independent.
	while _index < _segments.size():
		var segment := _segments[_index]
		var cost: float = segment.cost
		var left := maxf(cost-_spent,0.0)
		if left > remaining+0.0000000001: # Roundoff after many cell budgets is not remaining work.
			_spent += remaining
			# Interpolate from the fixed segment start instead of accumulating
			# float32 transform rounding on every rendered/physics frame.
			body.global_position = segment.start.lerp(segment.end,_spent/cost)
			return
		body.global_position = segment.end
		remaining = maxf(remaining-left,0.0)
		_spent = 0.0
		_index += 1
	stop()
	arrived.emit()
func _fail() -> void:
	stop()
	failed.emit()
