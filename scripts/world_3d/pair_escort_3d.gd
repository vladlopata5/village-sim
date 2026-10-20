extends Node
## Geometry/ownership of one pair. No professions, inventory, housing or animal rules.
const Balance = preload("res://scripts/balance_config.gd")
enum State { INACTIVE, JOINING, FOLLOWING, RECOVERING, ARRIVING, COMPLETED, CANCELLED, FAILED }
signal finished(operation_id: int, result: StringName)
signal state_changed(state: State)
var state: State = State.INACTIVE
var operation_id := 0
var last_error: StringName
var leader: Node3D
var follower: Node3D
var gap := 0.0
var peak_gap := 0.0
var peak_points := 0
var waits := 0
var recoveries := 0
var waiting := false
var _clock: Node
var _navigation: RefCounted
var _destination := Vector3.ZERO
var _trail := PackedVector3Array()
var _join_tail := PackedVector3Array()
var _stream_end := Vector3.ZERO
var _pending_vertex := false
var _revision := -1
var _connections: Array = []
var _ending := false
var _buffer_wait := false
var _last_minute := 0
var _stalled := 0
var _leader_position := Vector3.ZERO
var _follower_position := Vector3.ZERO
var _front_trace_before := false
var _back_trace_before := false
func is_active() -> bool: return state in [State.JOINING,State.FOLLOWING,State.RECOVERING,State.ARRIVING]
func trail_points() -> PackedVector3Array: return _trail.duplicate()
func _state(next: State) -> void:
	state = next
	state_changed.emit(state)
func _connect(signal_value: Signal, callback: Callable) -> void:
	signal_value.connect(callback)
	_connections.append([signal_value,callback])
func start(front: Node3D, back: Node3D, clock: Node) -> bool:
	last_error = &""
	if is_active() or _ending or not is_instance_valid(front) or not is_instance_valid(back) or front == back or not is_instance_valid(clock):
		last_error = &"invalid_pair"
		return false
	if front.movement_owner != null or back.movement_owner != null or front.navigation != back.navigation or not front.movement.is_moving():
		last_error = &"movement_unavailable"
		return false
	leader = front
	follower = back
	_clock = clock
	_navigation = front.navigation
	_destination = front.movement.target_position()
	operation_id += 1
	gap = 0.0; peak_gap = 0.0; peak_points = 0; waits = 0; recoveries = 0
	waiting = false; _buffer_wait = false; _stalled = 0
	_state(State.JOINING)
	if state!=State.JOINING: return false
	if not front.claim_movement(self):
		_state(State.FAILED)
		last_error = &"leader_unavailable"
		return false
	if not back.claim_movement(self):
		_fail(&"follower_unavailable")
		return false
	_connect(front.movement.traversed,_leader_trace.bind(operation_id))
	_connect(back.movement.traversed,_follower_trace.bind(operation_id))
	_connect(front.movement.arrived,_leader_arrived.bind(operation_id))
	_connect(back.movement.arrived,_follower_arrived.bind(operation_id))
	_connect(front.movement.failed,_route_failed.bind(operation_id))
	_connect(back.movement.failed,_route_failed.bind(operation_id))
	_connect(front.movement.path_changed,_leader_path_changed.bind(operation_id))
	_connect(front.tree_exiting,_removed.bind(&"leader_removed",operation_id))
	_connect(back.tree_exiting,_removed.bind(&"follower_removed",operation_id))
	_front_trace_before=front.movement.trace_enabled
	_back_trace_before=back.movement.trace_enabled
	front.movement.trace_enabled = true
	back.movement.trace_enabled = true
	_leader_position = front.global_position
	_follower_position = back.global_position
	_last_minute = clock.total_minutes
	return _join()
func _join() -> bool:
	# One existing point-to-point search, including obstacle-safe smoothing.
	var route: PackedVector3Array = _navigation.find_path(follower.global_position,leader.global_position)
	if route.is_empty():
		_fail(&"join_unreachable")
		return false
	var length := _length(route)
	var cut := maxf(length-Balance.ESCORT_GAP,0.0)
	var prefix := PackedVector3Array([route[0]])
	_join_tail = PackedVector3Array()
	var consumed := 0.0
	for index in range(1,route.size()):
		var distance := route[index-1].distance_to(route[index])
		if _join_tail.is_empty() and consumed+distance >= cut:
			var point := route[index-1].lerp(route[index],(cut-consumed)/distance) if distance>0.0 else route[index]
			_append(prefix,point)
			_join_tail.append(point)
		if _join_tail.is_empty(): _append(prefix,route[index])
		else: _append(_join_tail,route[index])
		consumed += distance
	if _join_tail.is_empty(): _join_tail = route.duplicate()
	_revision = _navigation.revision
	if not follower.movement.set_polyline(prefix):
		_fail(&"join_invalid")
		return false
	if prefix.size()==1: _joined()
	return is_active()
func _joined() -> void:
	_trail = _join_tail.duplicate()
	_stream_end = _trail[-1]
	_pending_vertex = false
	gap = _length(_trail)
	peak_gap = maxf(peak_gap,gap)
	peak_points = maxi(peak_points,_trail.size())
	if not follower.movement.set_polyline(_trail):
		_fail(&"trail_invalid")
		return
	_state(State.FOLLOWING)
func _append(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or not points[-1].is_equal_approx(point): points.append(point)
func _length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1,points.size()): total += points[index-1].distance_to(points[index])
	return total
func _flush_pending() -> bool:
	if not _pending_vertex: return true
	var end := _trail[-1]
	_pending_vertex = false
	if not follower.movement.append_polyline(PackedVector3Array([_stream_end,end])):
		_fail(&"stream_invalid")
		return false
	_stream_end = end
	return true
func _leader_trace(from_position: Vector3, end: Vector3, segment_finished: bool, expected: int) -> void:
	if expected!=operation_id or not is_active(): return
	_leader_position = end
	if state not in [State.FOLLOWING,State.ARRIVING]: return
	if _trail.is_empty() or not _trail[-1].is_equal_approx(from_position):
		_fail(&"leader_discontinuity")
		return
	if _pending_vertex: _trail[-1] = end
	else: _append(_trail,end)
	_pending_vertex = true
	gap += from_position.distance_to(end)
	peak_gap = maxf(peak_gap,gap)
	peak_points = maxi(peak_points,_trail.size())
	if segment_finished and not _flush_pending(): return
	# Partial head updates do not allocate one history point per frame.
	if _trail.size() >= Balance.ESCORT_MAX_POINTS-1:
		_buffer_wait = true
		leader.movement.set_paused(true)
		_flush_pending()
func _follower_trace(from_position: Vector3, end: Vector3, _segment_finished: bool, expected: int) -> void:
	if expected!=operation_id or not is_active(): return
	_follower_position = end
	if state not in [State.FOLLOWING,State.ARRIVING]: return
	var remaining := from_position.distance_to(end)
	gap = maxf(gap-remaining,0.0)
	while _trail.size()>1:
		var distance := _trail[0].distance_to(_trail[1])
		if distance>remaining+0.000001: break
		remaining = maxf(remaining-distance,0.0)
		_trail.remove_at(0)
	_trail[0] = end
func _leader_path_changed(_points: PackedVector3Array, expected: int) -> void:
	if expected==operation_id and state in [State.FOLLOWING,State.ARRIVING]: _flush_pending()
func _leader_arrived(expected: int) -> void:
	if expected!=operation_id or not is_active(): return
	if _flush_pending(): _state(State.ARRIVING)
func _follower_arrived(expected: int) -> void:
	if expected!=operation_id or not is_active(): return
	if state in [State.JOINING,State.RECOVERING]: _joined()
func _route_failed(expected: int) -> void:
	if expected==operation_id and is_active(): _fail(&"route_failed")
func _removed(reason: StringName, expected: int) -> void:
	if expected==operation_id: cancel(reason)
func retarget(target: Vector3) -> bool:
	if not is_active() or not target.is_finite(): return false
	if not _flush_pending(): return false
	_destination = target
	leader.movement.set_target(target)
	if state==State.ARRIVING: _state(State.FOLLOWING)
	return true
func _validate_revision() -> bool:
	if _navigation.revision==_revision: return true
	if state in [State.JOINING,State.RECOVERING]:
		return _join()
	if _navigation.is_raw_path_walkable(_trail):
		_pending_vertex = false
		_stream_end = _trail[-1]
		_revision = _navigation.revision
		var accepted: bool = follower.movement.set_polyline(_trail)
		if not is_active(): return false
		if accepted: return true
	recoveries += 1
	_state(State.RECOVERING)
	return _join()
func _physics_process(delta: float) -> void: advance(delta)
func advance(delta: float) -> void:
	if not is_active() or not is_finite(delta) or delta<=0.0: return
	var remaining := delta
	# Consume the elapsed interval in coordinated steps, not one leader burst followed
	# by one follower burst. Only active pairs pay for this integration.
	while remaining>0.00000001 and is_active():
		if not is_instance_valid(leader) or not is_instance_valid(follower) or not is_instance_valid(_clock):
			_fail(&"participant_removed")
			return
		var velocity: float = minf(leader.get_base_movement_speed(),follower.get_base_movement_speed())*_clock.speed_multiplier*1.25
		var step := minf(remaining,Balance.ESCORT_STEP_DISTANCE/velocity) if velocity>0.0 else remaining
		var front_before := leader.global_position
		var back_before := follower.global_position
		_advance_step(step)
		remaining-=step
		if is_active() and leader.global_position==front_before and follower.global_position==back_before: break
func _advance_step(delta: float) -> void:
	if not is_active() or delta<=0.0: return
	if not is_instance_valid(_clock):
		_fail(&"clock_removed")
		return
	if _clock.get_tree().paused: return
	if not is_instance_valid(leader) or not is_instance_valid(follower):
		_fail(&"participant_removed")
		return
	if not leader.global_position.is_equal_approx(_leader_position) or not follower.global_position.is_equal_approx(_follower_position):
		_fail(&"external_relocation")
		return
	if not _validate_revision() or not is_active(): return
	var cap: float = minf(leader.get_base_movement_speed(),follower.get_base_movement_speed())
	var before_leader := leader.global_position
	var before_follower := follower.global_position
	if state in [State.JOINING,State.RECOVERING]:
		follower.advance_owned(self,delta,cap,INF)
	else:
		if waiting and gap<=Balance.ESCORT_RESUME_GAP: waiting=false
		if not waiting and gap>=Balance.ESCORT_WAIT_GAP-0.000001:
			waiting=true
			waits+=1
		if _buffer_wait and _trail.size()<Balance.ESCORT_MAX_POINTS*0.75:
			_buffer_wait=false
			leader.movement.set_paused(false)
		if state==State.FOLLOWING and not waiting and not _buffer_wait:
			leader.advance_owned(self,delta,cap,maxf(minf(Balance.ESCORT_WAIT_GAP,Balance.ESCORT_MAX_TRAIL)-gap,0.0))
		if not is_active(): return
		if not waiting and gap>=Balance.ESCORT_WAIT_GAP-0.000001:
			waiting=true
			waits+=1
		var retain := Balance.ESCORT_ARRIVAL_RADIUS if state==State.ARRIVING else Balance.ESCORT_GAP
		follower.advance_owned(self,delta,cap,maxf(gap-retain,0.0))
	if not is_active(): return
	var now: int = _clock.total_minutes
	if leader.global_position!=before_leader or follower.global_position!=before_follower:
		_stalled=0
	elif not leader.movement.paused and not follower.movement.paused and cap>0.0:
		_stalled+=maxi(now-_last_minute,0)
	_last_minute=now
	if _stalled>=Balance.ESCORT_STALL_MINUTES:
		_fail(&"no_progress")
		return
	if _buffer_wait and gap<=Balance.ESCORT_GAP+0.00001:
		_fail(&"trail_density_limit") # Cannot discard geometry or force overlapping participants.
		return
	if state==State.ARRIVING and gap<=Balance.ESCORT_ARRIVAL_RADIUS+0.00001 and leader.global_position.distance_to(_destination)<0.0001 and follower.global_position.distance_to(_destination)<=Balance.ESCORT_ARRIVAL_RADIUS+0.00001:
		_finish(State.COMPLETED,&"completed")
func cancel(reason: StringName = &"cancelled") -> void:
	if is_active(): _finish(State.CANCELLED,reason)
func _fail(reason: StringName) -> void:
	if is_active(): _finish(State.FAILED,reason)
func _finish(next: State, result: StringName) -> void:
	if _ending or not is_active(): return
	_ending=true
	var old_leader := leader
	var old_follower := follower
	var completed_id := operation_id
	state=next
	last_error=result if next!=State.COMPLETED else &""
	for connection in _connections:
		if connection[0].is_connected(connection[1]): connection[0].disconnect(connection[1])
	_connections.clear()
	_trail.clear();_join_tail.clear();_pending_vertex=false
	leader=null;follower=null
	if is_instance_valid(old_leader):
		old_leader.movement.trace_enabled=_front_trace_before
		if _buffer_wait: old_leader.movement.set_paused(false)
		old_leader.release_movement(self,next==State.COMPLETED)
	if is_instance_valid(old_follower):
		old_follower.movement.trace_enabled=_back_trace_before
		old_follower.release_movement(self,next==State.COMPLETED)
	_buffer_wait=false;waiting=false
	_ending=false
	state_changed.emit(next)
	finished.emit(completed_id,result)
func _exit_tree() -> void: cancel(&"coordinator_removed")
