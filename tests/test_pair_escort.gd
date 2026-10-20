extends SceneTree
const F=preload("res://tests/pair_escort_fixture.gd")
const Pair=preload("res://scripts/world_3d/pair_escort_3d.gd")
const Animal=preload("res://scripts/animal_data.gd")
const Balance=preload("res://scripts/balance_config.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func basic() -> void:
	for speed in [1,2,4,10,20]:
		for delta in [1.0/60,0.7]:
			var f=F.make(self)
			f.clock.set_speed(speed)
			var notifications: Array=[]
			var joins: Array=[]
			f.pair.state_changed.connect(func(state):
				if state==Pair.State.FOLLOWING:joins.append([f.front.position,f.back.position]))
			f.pair.finished.connect(func(id,result):notifications.append([id,result]))
			check(f.pair.start(f.front,f.back,f.clock) and f.pair.state==Pair.State.JOINING,"Starts by physical joining")
			check(f.back.behavior.suspended and f.back.data.status==Animal.Status.WILD,"Wild autonomous behavior suspended")
			var front_start: Vector3=f.front.position
			while f.pair.state==Pair.State.JOINING:F.tick(f,delta)
			check(not joins.is_empty() and joins[0][0]==front_start and joins[0][0].distance_to(joins[0][1])>1.0,"Leader waits; join never requires coincident coordinates")
			var join_calls: int=f.nav.raw_calls
			var reached_early:=false
			var safe:=true
			for step in 20000:
				if not f.pair.is_active():break
				var old_front: Vector3=f.front.position;var old_back: Vector3=f.back.position
				F.tick(f,delta)
				if old_front.distance_to(f.front.position)>0.6*speed*delta+0.0001 or old_back.distance_to(f.back.position)>0.6*speed*delta+0.0001:safe=false
				if f.pair.state==Pair.State.ARRIVING:
					reached_early=true
					if f.intents.current_intent!=f.intent:safe=false
			check(f.pair.state==Pair.State.COMPLETED and notifications.size()==1,"Both arrive, one completion, x%d delta%f" % [speed,delta])
			check(safe and f.pair.peak_gap<=3.0001 and f.pair.peak_points<Balance.ESCORT_MAX_POINTS,"Distance/speed budgets hold inside big steps")
			check(f.front.position.distance_to(f.goal)<0.001 and f.back.position.distance_to(f.goal)<=0.8001,"Actual pair arrival area")
			check(f.nav.raw_calls<=join_calls+1 and f.nav.raw_calls==2,"Only join and leader raw searches")
			check(not f.back.behavior.suspended and f.back.movement_owner==null and f.front.movement_owner==null,"Completion restores ordinary owners")
			check(f.back.data.wool_growth==0 and not f.front.movement.trace_enabled,"No free wool or permanent tracing")
			if speed==1 and delta<0.1:check(reached_early,"Leader arrival precedes follower completion")
			f.pair.cancel();f.pair._leader_arrived(f.pair.operation_id-1)
			check(notifications.size()==1,"Late callback and duplicate cancel cannot complete again")
			F.dispose(f)
func wait_and_cancel() -> void:
	var f=F.make(self)
	f.pair.start(f.front,f.back,f.clock)
	while f.pair.state==Pair.State.JOINING:F.tick(f,0.05)
	# Leader on a faster surface, follower remains on ordinary slow terrain.
	f.front.movement.surface_speed=func(_cell,_planned):return 1.25
	f.back.movement.surface_speed=func(_cell,_planned):return 0.2
	for step in 400:F.tick(f,0.05)
	check(f.pair.waits>0 and f.pair.peak_gap<=3.0001,"Different terrain triggers bounded leader wait")
	var queries: int=f.nav.raw_calls
	var route: PackedVector3Array=f.front.movement.current_path()
	f.front.movement.set_paused(true)
	var before: Vector3=f.front.position
	for step in 80:F.tick(f,0.2)
	check(f.front.position==before and f.front.movement.current_path()==route and f.nav.raw_calls==queries and f.pair.is_active(),"Intentional long pause keeps route and performs no A*")
	f.front.movement.set_paused(false)
	f.back.movement.surface_speed=func(_cell,planned):return minf(planned,1.0)
	F.finish(f)
	check(f.pair.state==Pair.State.COMPLETED,"Wait resumes without lost route")
	F.dispose(f)
	for stage in ["joining","following","arriving"]:
		var c=F.make(self)
		c.back.behavior._begin_graze(c.clock.total_minutes)
		var choice_count: int=c.back.behavior.choices
		c.pair.start(c.front,c.back,c.clock)
		if stage!="joining":
			while c.pair.state==Pair.State.JOINING:F.tick(c,0.05)
		if stage=="arriving":
			while c.pair.state==Pair.State.FOLLOWING:F.tick(c,0.05)
		var front_pos: Vector3=c.front.position;var back_pos: Vector3=c.back.position
		var id: int=c.pair.operation_id
		c.pair.cancel();c.pair.cancel();c.pair._follower_arrived(id)
		check(c.pair.state==Pair.State.CANCELLED and c.front.position==front_pos and c.back.position==back_pos,"Cancel preserves physical positions at "+stage)
		check(c.back.behavior.choices==choice_count+1 and c.back.data.wool_growth==0 and not c.back.behavior.suspended,"Resume current-time wild choice, cancelled graze earns no wool")
		F.dispose(c)
func ownership() -> void:
	var f=F.make(self)
	f.pair.start(f.front,f.back,f.clock)
	var other=Pair.new();root.add_child(other);other.set_physics_process(false)
	check(not other.start(f.front,f.back,f.clock),"No double pair ownership")
	other.free()
	var critical=F.Intent.new(F.Intent.Type.MOVE_TO,&"critical_test",Vector2(200,50),100,false)
	check(f.intents.force_set_intent(critical,100),"Critical forced intent accepted during escort")
	check(f.pair.state==Pair.State.CANCELLED and f.intents.current_intent==critical and f.front.movement_owner==null,"Forced cleanup cannot overwrite new critical action")
	var before: Vector3=f.front.position
	await physics_frame
	await process_frame
	f.front._physics_process(0.1)
	check(f.front.position!=before and f.front.movement.speed>0.6,"Ordinary resident speed restored")
	F.dispose(f)
	for removed in ["front","back"]:
		var d=F.make(self);d.pair.start(d.front,d.back,d.clock)
		d[removed].free()
		check(not d.pair.is_active(),"Removal cancels pair: "+removed)
		var survivor=d.back if removed=="front" else d.front
		check(survivor.movement_owner==null,"Survivor has no dangling movement owner")
		F.dispose(d)
func replacement_and_callbacks() -> void:
	var f=F.make(self)
	f.pair.start(f.front,f.back,f.clock)
	f.back.interrupt_movement()
	check(f.pair.state==Pair.State.CANCELLED and not f.back.behavior.suspended,"Follower forced replacement releases both participants")
	var old_id: int=f.pair.operation_id
	f.front.move_to(Vector2(200,25))
	check(f.pair.start(f.front,f.back,f.clock),"A released pair can start a fresh operation")
	f.pair._leader_arrived(old_id)
	check(f.pair.state==Pair.State.JOINING and f.pair.operation_id>old_id,"Old generation callback cannot affect a new pair operation")
	F.dispose(f)
	var cancelled=F.make(self)
	cancelled.pair.state_changed.connect(func(state):
		if state==Pair.State.JOINING:cancelled.pair.cancel())
	check(not cancelled.pair.start(cancelled.front,cancelled.back,cancelled.clock) and cancelled.front.movement_owner==null and cancelled.back.movement_owner==null,"Reentrant start cancellation cannot claim actors afterward")
	F.dispose(cancelled)
	var beyond=F.make(self,Vector3(.25,0,.25),Vector3(-4.25,0,.25),Vector3(20.25,0,.25))
	beyond.pair.start(beyond.front,beyond.back,beyond.clock);F.finish(beyond)
	check(beyond.pair.state==Pair.State.COMPLETED and not beyond.back.data.contains(beyond.back.position),"Escort may finish outside original wild disk without domestication")
	var actual: Vector3=beyond.back.position
	var random:=RandomNumberGenerator.new();random.seed=7
	var offer: Dictionary=beyond.back._wander_offer(random)
	check(not offer.is_empty() and beyond.back.data.contains(offer.target) and beyond.back.position==actual,"Subsequent normal wild walk can return physically, never teleport")
	F.dispose(beyond)
	var night=F.make(self)
	night.clock.total_minutes=1300
	night.pair.start(night.front,night.back,night.clock);night.pair.cancel()
	check(night.back.data.behavior==Animal.Behavior.SLEEP and night.back.data.wake_at>=1740 and night.back.data.wake_at<=1860,"Cancellation resumes wild behavior using current night, no habitat teleport")
	F.dispose(night)
func run() -> void:
	basic();wait_and_cancel();await ownership();replacement_and_callbacks()
	print("Pair escort: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
