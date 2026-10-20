extends SceneTree
const F=preload("res://tests/pair_escort_fixture.gd")
const Pair=preload("res://scripts/world_3d/pair_escort_3d.gd")
const Balance=preload("res://scripts/balance_config.gd")
class StalledAnimal:
	extends "res://scripts/world_3d/animal_executor_3d.gd"
	func advance_owned(_owner: Node, _delta: float, _cap: float, _distance_limit: float) -> void: pass
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func on_line(point: Vector3, points: PackedVector3Array) -> bool:
	for index in range(1,points.size()):
		var edge:=points[index]-points[index-1]
		var fraction:=clampf((point-points[index-1]).dot(edge)/edge.length_squared(),0.0,1.0)
		if point.distance_to(points[index-1]+edge*fraction)<0.0001:return true
	return false
func prescribed_paths() -> void:
	var cases: Array = [
		PackedVector3Array([Vector3(.25,0,.25),Vector3(5.25,0,.25),Vector3(5.25,0,5.25),Vector3(12.25,0,5.25)]),
		PackedVector3Array([Vector3(.25,0,.25),Vector3(12.25,0,8.25)]),
		PackedVector3Array([Vector3(.25,0,.25),Vector3(6.25,0,.25),Vector3(6.25,0,6.25),Vector3(.25,0,6.25),Vector3(.25,0,.25),Vector3(6.25,0,.25),Vector3(12.25,0,.25)]),
		PackedVector3Array([Vector3(.25,0,.25),Vector3(25.25,0,.25),Vector3(25.25,0,15.25),Vector3(-20.25,0,15.25),Vector3(-20.25,0,-15.25),Vector3(20.25,0,-15.25)])]
	for route in cases:
		var f=F.make(self)
		check(f.front.movement.set_polyline(route),"Existing mover accepts validated test polyline")
		f.goal=route[-1];f.clock.set_speed(20)
		var safe: Array=[true,0]
		var corridor:=PackedVector3Array([Vector3(-.95,0,.25)])
		corridor.append_array(route)
		f.back.movement.traversed.connect(func(a,b,_last):
			if f.pair.state not in [Pair.State.FOLLOWING,Pair.State.ARRIVING]:return
			safe[1]+=1
			if not on_line(a,corridor) or not on_line(b,corridor) or not f.nav.has_line_of_sight(a,b):safe[0]=false)
		f.pair.start(f.front,f.back,f.clock)
		var max_segments:=0
		for step in 20000:
			if not f.pair.is_active():break
			F.tick(f,0.7)
			max_segments=maxi(max_segments,f.back.movement._segments.size())
		check(f.pair.state==Pair.State.COMPLETED and safe[0] and safe[1]>10,"Actual follower follows full turns/diagonal/self-crossing route")
		check(f.pair.peak_points<Balance.ESCORT_MAX_POINTS and f.pair.peak_gap<=3.0001 and max_segments<100,"Long route bounds history and executor segments without dropping tail")
		check(f.nav.raw_calls==1 and f.nav.smooth_calls==1,"Prescribed leader path adds only the initial join search")
		F.dispose(f)
	# Deliberately dense turns exercise point backpressure, not a realistic route.
	var dense=F.make(self)
	var points:=PackedVector3Array([Vector3(.25,0,.25)])
	for index in range(1,1200):points.append(Vector3(.25+(.01 if index%2 else 0.0),0,.25+index*.0001))
	points.append(Vector3(4.25,0,2.25))
	dense.front.movement.set_polyline(points);dense.goal=points[-1]
	dense.pair.start(dense.front,dense.back,dense.clock);dense.clock.set_speed(20)
	F.finish(dense,.1)
	check(dense.pair.state==Pair.State.COMPLETED and dense.pair.peak_points<Balance.ESCORT_MAX_POINTS,"Dense turns use bounded backpressure without throwing away unconsumed history")
	F.dispose(dense)
func obstacles_and_revision() -> void:
	var f=F.make(self)
	f.nav.add_blocker(&"join_wall",Rect2(-2,-2,.5,4))
	check(not f.nav.has_line_of_sight(f.front.position,f.back.position),"Join starts across actual obstacle")
	f.pair.start(f.front,f.back,f.clock)
	F.finish(f)
	check(f.pair.state==Pair.State.COMPLETED,"Initial join routes around obstacle instead of direct chord")
	F.dispose(f)
	f=F.make(self)
	f.nav.add_blocker(&"lower",Rect2(1,-3,9,2));f.nav.add_blocker(&"upper",Rect2(1,1.5,9,2))
	f.pair.start(f.front,f.back,f.clock);F.finish(f)
	check(f.pair.state==Pair.State.COMPLETED,"Both pass a narrow navigation corridor")
	F.dispose(f)
	f=F.make(self)
	f.nav.add_blocker(&"closed",Rect2(-2,-24,.5,48))
	var before_front: Vector3=f.front.position;var before_back: Vector3=f.back.position
	check(not f.pair.start(f.front,f.back,f.clock) and f.pair.last_error==&"join_unreachable","Impossible join returns explicit failure")
	check(f.front.position==before_front and f.back.position==before_back and f.front.movement_owner==null and f.back.movement_owner==null,"Failed join cleans ownership, preserves positions")
	F.dispose(f)
	for recoverable in [true,false]:
		var changed=F.make(self)
		changed.pair.start(changed.front,changed.back,changed.clock)
		while changed.pair.state==Pair.State.JOINING:F.tick(changed,.05)
		changed.back.movement.surface_speed=func(_cell,_planned):return .2
		while changed.pair.gap<2.9:F.tick(changed,.05)
		var middle: Vector3=changed.front.position.lerp(changed.back.position,.5)
		var block:=Rect2(middle.x-.05,middle.z-.05,.1,.1) if recoverable else Rect2(middle.x-.05,-24,.1,48)
		changed.nav.add_blocker(&"new_obstacle",block)
		changed.back.movement.surface_speed=func(_cell,planned):return minf(planned,1.0)
		var queries: int=changed.nav.raw_calls
		F.tick(changed,.05)
		if recoverable:
			check(changed.pair.state==Pair.State.RECOVERING and changed.pair.recoveries==1,"Invalid tail starts explicit bounded recovery")
			while changed.pair.state==Pair.State.RECOVERING:F.tick(changed,.05)
			var recovery_queries: int=changed.nav.raw_calls-queries
			check(recovery_queries<=2,"Recovery adds one join route plus ordinary leader replan")
			changed.nav.remove_blocker(&"new_obstacle")
			queries=changed.nav.raw_calls
			F.finish(changed)
			check(changed.pair.state==Pair.State.COMPLETED and changed.nav.raw_calls<=queries+1,"Removed blocker preserves safe trail, no follower A* fanout")
		else:
			check(changed.pair.state==Pair.State.FAILED and changed.pair.last_error==&"join_unreachable","Impossible recovery ends, never retries every frame")
		F.dispose(changed)
func retarget_and_multiple() -> void:
	var f=F.make(self)
	f.pair.start(f.front,f.back,f.clock)
	for step in 200:F.tick(f,.05)
	var goal:=Vector3(5.25,0,10.25)
	check(f.pair.retarget(goal),"Same operation accepts a new leader route")
	F.finish(f)
	check(f.pair.state==Pair.State.COMPLETED and f.front.position.distance_to(goal)<.001 and f.back.position.distance_to(goal)<=.8001,"Retarget preserves old physical tail through corner")
	F.dispose(f)
	var nav=F.CountedGrid.new(Rect2(-32,-24,64,48));var pairs: Array=[]
	for index in 6:
		var z: float=-12.75+index*4
		pairs.append(F.make(self,Vector3(.25,0,z),Vector3(-4.25,0,z),Vector3(12.25,0,z),nav))
	for pair in pairs:pair.pair.start(pair.front,pair.back,pair.clock);pair.clock.set_speed(20)
	for step in 500:
		for pair in pairs:
			if pair.pair.is_active():F.tick(pair,.1)
	check(pairs.all(func(pair):return pair.pair.state==Pair.State.COMPLETED) and nav.raw_calls==12,"Six independent simultaneous pairs use12 raw routes")
	for pair in pairs:F.dispose(pair)
	var stuck=F.make(self,Vector3(.25,0,.25),Vector3(-.95,0,.25),Vector3(12.25,0,.25),null,StalledAnimal)
	stuck.pair.start(stuck.front,stuck.back,stuck.clock)
	F.finish(stuck,.5,200)
	check(stuck.pair.state==Pair.State.FAILED and stuck.pair.last_error==&"no_progress","Actual unsuccessful attempts expire in game minutes")
	F.dispose(stuck)
func run() -> void:
	prescribed_paths();obstacles_and_revision();retarget_and_multiple()
	print("Pair geometry: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
