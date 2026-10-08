extends Node
## Navigation executor; commands and selection do not know how the path is built.
signal arrived
signal failed
signal path_changed(points: PackedVector3Array)
@export var surface_tolerance: float = 0.25
const MAP_WAIT_FRAMES: int = 30
@export var speed: float = 3.0
var body: Node3D
var agent: NavigationAgent3D
var _target := Vector3.ZERO
var _moving := false
var _pending := false
var _wait_frames := 0
func set_target(world_position: Vector3) -> void:
	_target = world_position
	_moving = true
	_pending = true
	_wait_frames = 0
	path_changed.emit(PackedVector3Array())
func stop() -> void:
	_moving = false
	_pending = false
	path_changed.emit(PackedVector3Array())
func is_moving() -> bool: return _moving
func target_position() -> Vector3: return _target
func _physics_process(delta: float) -> void:
	advance(delta)
func advance(delta: float) -> void:
	if not _moving: return
	if not is_instance_valid(body) or not is_instance_valid(agent) or not _target.is_finite():
		_fail()
		return
	var map := agent.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0 or not NavigationServer3D.map_get_closest_point_owner(map, _target).is_valid():
		_wait_frames += 1
		if _wait_frames >= MAP_WAIT_FRAMES: _fail()
		return
	if _pending:
		if NavigationServer3D.map_get_regions(map).is_empty():
			_fail()
			return
		var projected := NavigationServer3D.map_get_closest_point(map, _target)
		if projected.distance_to(_target) > surface_tolerance:
			_fail()
			return
		_target = projected
		body.global_position.y = NavigationServer3D.map_get_closest_point(map, body.global_position).y
		agent.target_position = _target
		_pending = false
	var waypoint := agent.get_next_path_position()
	if agent.is_navigation_finished():
		if agent.is_target_reachable() and body.global_position.distance_to(agent.get_final_position()) <= agent.target_desired_distance:
			stop()
			arrived.emit()
		else: _fail()
		return
	body.global_position = body.global_position.move_toward(waypoint, speed * maxf(delta, 0.0))
func refresh_debug_path() -> void:
	path_changed.emit(agent.get_current_navigation_path())
func _fail() -> void:
	stop()
	failed.emit()
