extends Node
## Follows prepared cell segments; surface execution never changes route planning.
signal cell_entered(cell: Vector2i)
var surface_speed: Callable
signal arrived
signal failed
signal path_changed(points: PackedVector3Array)
signal traversed(start: Vector3, end: Vector3, segment_finished: bool)
var trace_enabled := false
var paused := false
var _external := false
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
var _prepared_path: Dictionary = {}
var _generation := 0
var _tracked := false
var _last_cell := Vector2i.ZERO
var _last_position := Vector3.ZERO
func reset_physical_origin() -> void:
	if navigation == null or not is_instance_valid(body): return
	_last_cell = navigation.world_to_cell(body.global_position)
	_last_position = body.global_position
	_tracked = true
func set_target(world_position: Vector3, prepared: Dictionary = {}) -> void:
	_external = false
	_generation += 1
	_prepared_path = prepared
	_target = world_position
	_moving = true
	_pending = true # Plan on advance, after intent ownership is established.
	raw_path.clear()
	_path.clear()
	_segments.clear()
	_spent = 0.0
	path_changed.emit(_path)
func stop() -> void:
	_external = false
	_generation += 1
	_prepared_path = {}
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
func set_paused(value: bool) -> void:
	if paused == value: return
	paused = value
	_generation += 1 # A traversal callback may hold this very physics step.
## External geometry uses the same cell integrator, without A* or smoothing.
func set_polyline(points: PackedVector3Array) -> bool:
	if not is_instance_valid(body) or navigation == null or points.is_empty() or not points[0].is_equal_approx(body.global_position) or not navigation.is_raw_path_walkable(points): return false
	var generation := _generation+1
	stop()
	if _generation != generation: return false
	_external = true
	reset_physical_origin()
	_index = 0
	_path = points.duplicate()
	_target = points[-1]
	_revision = navigation.revision
	_moving = true
	for index in range(1,points.size()): _segments.append_array(navigation.traversal_segments(points[index-1],points[index]))
	path_changed.emit(_path)
	return _external and _generation == generation
func append_polyline(points: PackedVector3Array) -> bool:
	if not _moving: return set_polyline(points)
	if not _external or _revision != navigation.revision or points.is_empty() or not points[0].is_equal_approx(_target) or not navigation.is_raw_path_walkable(points): return false
	# Keep partial first-segment cost/progress; discard only consumed segments.
	if _index > 0:
		_segments = _segments.slice(_index)
		_index = 0
	for index in range(1,points.size()): _segments.append_array(navigation.traversal_segments(points[index-1],points[index]))
	_target = points[-1]
	_path = PackedVector3Array([body.global_position])
	for segment in _segments: _path.append(segment.end)
	return true
func advance(delta: float, distance_budget: float = INF) -> void:
	if not _moving or paused: return
	if not is_instance_valid(body) or navigation == null or not _target.is_finite():
		_fail()
		return
	if not _tracked or body.global_position != _last_position:
		reset_physical_origin() # Spawn, portal, debug relocation: never trace the jump.
		_pending = true
	var generation := _generation
	if _external and _revision != navigation.revision:
		_fail() # The external geometry's owner must validate/recover, never chase a stale endpoint.
		return
	if _pending or _revision != navigation.revision:
		var hint := _prepared_path
		var prepared_raw: PackedVector3Array = hint.get("raw",PackedVector3Array())
		_prepared_path = {} # Consume once; replans always use the current world.
		if hint.get("navigation_id",-1) == navigation.get_instance_id() and hint.get("revision",-1) == navigation.revision and hint.get("start") == body.global_position and hint.get("target") == _target and not prepared_raw.is_empty() and prepared_raw[0] == body.global_position and prepared_raw[-1] == _target:
			raw_path = prepared_raw
		else:
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
		if generation != _generation: return
	var remaining := maxf(delta,0.0) * maxf(speed,0.0)
	# Budget is elapsed time * base speed. Crossing slow cells consumes more of
	# that budget; consume all boundaries so large x20 steps remain FPS independent.
	while _index < _segments.size():
		if remaining <= 0.0000000001 or distance_budget <= 0.0000000001: return
		var segment := _segments[_index]
		var cost: float = segment.cost
		var cell: Vector2i = navigation.world_to_cell(segment.start.lerp(segment.end,0.5))
		if cell != _last_cell:
			_last_cell = cell
			cell_entered.emit(cell)
			if generation != _generation: return # A callback may stop/replace this action.
		var ratio := 1.0
		if surface_speed.is_valid() and cost > 0.0:
			var planned_speed: float = segment.start.distance_to(segment.end) / cost
			ratio = surface_speed.call(cell,planned_speed) / planned_speed
		# _spent stays in original segment-cost units. A live bonus changes only
		# the remaining time; geometric progress never jumps when the level changes.
		var left := maxf(cost-_spent,0.0) / ratio
		var allowed := remaining
		if is_finite(distance_budget):
			var length: float = segment.start.distance_to(segment.end)
			if length>0.0: allowed = minf(allowed,distance_budget*cost/length/ratio)
		var previous := body.global_position
		if left > allowed+0.0000000001:
			_spent += allowed * ratio
			body.global_position = segment.start.lerp(segment.end,_spent/cost)
			_last_position = body.global_position
			if trace_enabled: traversed.emit(previous,body.global_position,false)
			return
		body.global_position = segment.end
		_last_position = body.global_position
		if is_finite(distance_budget): distance_budget = maxf(distance_budget-previous.distance_to(body.global_position),0.0)
		remaining = maxf(remaining-left,0.0)
		_spent = 0.0
		_index += 1
		if trace_enabled:
			traversed.emit(previous,body.global_position,true)
			if generation != _generation: return
	stop()
	arrived.emit()
func _fail() -> void:
	stop()
	failed.emit()
