extends SceneTree
const Activity=preload("res://scripts/resident_activity.gd").Type
const Profession=preload("res://scripts/resident_profession.gd").Type
const ResourceType=preload("res://scripts/resource_type.gd").Type
const Intent=preload("res://scripts/resident_intent.gd")
const Fixture=preload("res://tests/ai_queue_fixture.gd")
var failures:=0
var checks:=0
var world: Node
var actor: Node
var queue: Node
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func setup() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_logger.console_enabled=false;world.social_events.enabled=false
	world.game_time.total_minutes=600
	for candidate in world.resident_runtimes:
		candidate.decision._deciding=true
		candidate.intents.abort_current(candidate.intents.current_intent)
		world.player_control.assign_profession(candidate.data.id,Profession.NONE)
		candidate.view.set_physics_process(false)
		world.game_time.minute_changed.disconnect(candidate.need_dynamics._on_minute_changed)
		for need in candidate.data.needs.values():need.value=0;need.base_weight=0
		candidate.decision.social=null;candidate.decision.wander=null;candidate.decision.assignments=null
		candidate.schedule._phase="День"
	queue=Fixture.one_per_slice(world);queue.clear()
	actor=world.resident_runtimes[0];actor.decision._deciding=false
func period(seed_value: int) -> int:
	actor.decision.rng.seed=seed_value
	actor.decision.request_decision("fixture")
	await Fixture.drain(world)
	return actor.decision._next_decision_at-world.game_time.total_minutes
func endpoint_seed(value: int) -> int:
	var model:=RandomNumberGenerator.new()
	for candidate in 10000:
		model.seed=candidate
		if model.randi_range(10,30)==value:return candidate
	assert(false,"Endpoint seed exists");return -1
func run() -> void:
	setup()
	for endpoint in [10,30]:
		var endpoint_duration: int=await period(endpoint_seed(endpoint))
		check(endpoint_duration==endpoint,"Inclusive idle endpoint %d"%endpoint)
	var model:=RandomNumberGenerator.new();model.seed=12345
	actor.decision.rng.seed=12345
	for sample in 100:
		var expected:=model.randi_range(10,30)
		actor.decision.request_decision("new_period")
		await Fixture.drain(world)
		var sampled_duration: int=actor.decision._next_decision_at-world.game_time.total_minutes
		check(sampled_duration>=10 and sampled_duration<=30 and sampled_duration==expected and actor.decision.rng.state==model.state,"One resident-owned uniform draw per new empty selection")
	var duration: int=await period(74)
	var deadline: int=actor.decision._next_decision_at
	var rng_state: int=actor.decision.rng.state
	var before: int=actor.decision.decision_count
	world.game_time.debug_skip_minutes(duration-1)
	check(actor.decision._next_decision_at==deadline and actor.decision.rng.state==rng_state and actor.decision.decision_count==before and queue.pending_count()==0,"Period is stable before its deadline")
	world.game_time.debug_skip_minutes(1)
	check(queue.pending_count()==1 and actor.decision.decision_count==before,"Expiry enqueues once before selection")
	var requests: int=queue.requests
	world.game_time.debug_skip_minutes(60)
	check(queue.requests==requests and queue.pending_count()==1 and actor.decision.rng.state==rng_state,"Waiting for service does not repeat timer requests or RNG draws")
	await Fixture.drain(world)
	check(actor.decision.decision_count==before+1 and actor.decision._next_decision_at>=world.game_time.total_minutes+10 and actor.decision._next_decision_at<=world.game_time.total_minutes+30,"One new period starts after empty queued decision")
	# Existing ordinary notifications merge without rerolling the current period.
	rng_state=actor.decision.rng.state;deadline=actor.decision._next_decision_at
	for repeat in 20:actor.decision.request_decision("logistics_available")
	check(queue.pending_count()==1 and actor.decision.rng.state==rng_state and actor.decision._next_decision_at==deadline,"Repeated availability does not reroll at enqueue")
	await Fixture.drain(world)
	check(actor.decision._next_decision_at==deadline and actor.decision.rng.state==rng_state,"Rejected no-work notification preserves the same idle period")
	world.free()
	for speed in [1,2,4,10,20]:
		setup();world.game_time.set_speed(speed)
		duration=await period(20+speed);before=actor.decision.decision_count
		world.game_time.advance(float(duration-1)/speed)
		check(queue.pending_count()==0 and actor.decision.decision_count==before,"No early retry x%d"%speed)
		world.game_time.advance(1.0/speed)
		check(queue.pending_count()==1,"Actual game-minute deadline works x%d"%speed)
		await Fixture.drain(world);world.free()
	# Critical needs cancel the old timer and retain synchronous ownership.
	for kind in ["hunger","fatigue"]:
		setup();duration=await period(8)
		if kind=="hunger":actor.data.hunger=100
		else:actor.data.fatigue=100
		check(actor.intents.forced_priority==200 if kind=="hunger" else actor.intents.forced_priority==100,"Critical %s bypasses idle/queue"%kind)
		check(actor.decision._next_decision_at<0,"Critical action cancels idle timer")
		requests=queue.requests;world.game_time.debug_skip_minutes(duration+1)
		check(queue.requests==requests,"No old idle completion during critical %s"%kind)
		if kind=="hunger":check(world.warehouse_data.resources.get_reserved_out(ResourceType.FOOD)==1,"Critical meal owns real FOOD, no early consumption")
		world.free()
	setup();duration=await period(3)
	check(world.player_control.move_to(actor.data.id,Vector2(300,100)),"Player command accepted during idle")
	check(actor.decision._next_decision_at<0 and actor.intents.player_controlled,"Player move cancels idle timer")
	requests=queue.requests;world.game_time.debug_skip_minutes(duration+1)
	check(queue.requests==requests,"Player action has no obsolete idle request")
	actor.commands.cancel_current();world.game_time.debug_skip_minutes(1)
	check(actor.decision._next_decision_at>=world.game_time.total_minutes+10 and queue.pending_count()==0,"Cancellation returns to a fresh idle period without old completion")
	world.free()
	setup();world.game_time.total_minutes=1019;duration=await period(32)
	world.game_time.debug_skip_minutes(1)
	check(actor.schedule.get_phase()=="Вечер" and queue.pending_count()==1 and actor.decision._next_decision_at<0,"Phase cancels old idle and requests current phase through queue")
	requests=queue.requests;world.game_time.debug_skip_minutes(31)
	check(queue.requests==requests,"Delayed phase service does not revive old idle deadline")
	await Fixture.drain(world);check(actor.decision._next_decision_at>=world.game_time.total_minutes+10,"Empty new phase starts its own period")
	world.free()
	setup();world.game_time.total_minutes=1379;actor.schedule._phase="Вечер";actor.data.fatigue=80;duration=await period(32)
	world.game_time.debug_skip_minutes(1);await Fixture.drain(world)
	check(actor.schedule.get_phase()=="Ночь" and actor.decision._next_decision_at<0 and (actor.intents.has_current_action() or actor.data.activity==Activity.SLEEPING),"Night sleep route is an action, not randomized idle")
	requests=queue.requests;world.game_time.debug_skip_minutes(31)
	check(queue.requests==requests,"Sleep route waiting does not expire an old idle period")
	world.free()
	setup();duration=await period(5)
	check(world.player_control.assign_profession(actor.data.id,Profession.BUILDER),"Real assignment accepted during idle")
	await Fixture.drain(world)
	check(actor.data.profession==Profession.BUILDER and actor.decision._next_decision_at>=world.game_time.total_minutes+10,"Assignment notification still causes a fresh valid empty selection")
	world.free()
	# Controlled provider: newly available work without emitting a notification.
	for endpoint in [10,30]:
		setup();actor.data.profession=Profession.BUILDER
		var available: Array=[false]
		actor.decision.work_available=func():return available[0]
		actor.decision.work_request=func():return actor.intents.submit(Intent.new(Intent.Type.NONE,&"fixture_work",Vector2.ZERO,7000,false))
		duration=await period(endpoint_seed(endpoint));available[0]=true
		world.game_time.debug_skip_minutes(duration-1)
		check(not actor.intents.has_current_action() and queue.pending_count()==0,"No new work wake-up is invented before idle deadline")
		world.game_time.debug_skip_minutes(1);await Fixture.drain(world)
		check(actor.intents.current_intent.reason_id==&"fixture_work" and actor.decision._next_decision_at<0,"Existing queued selection discovers work at chosen deadline")
		world.free()
	# Named stationary and move intents are accepted actions, not empty IDLE.
	for reason in ["handling","wait_slot","work"]:
		setup();duration=await period(2)
		actor.intents.submit(Intent.new(Intent.Type.NONE,StringName(reason),Vector2.ZERO,80,false))
		check(actor.decision._next_decision_at<0,"Accepted %s has no idle timer"%reason)
		requests=queue.requests;rng_state=actor.decision.rng.state
		world.game_time.debug_skip_minutes(31)
		check(queue.requests==requests and actor.decision.rng.state==rng_state,"Waiting action is not randomized idle")
		world.free()
	setup();duration=await period(2);actor.needs.try_rest(80)
	check(actor.decision._next_decision_at<0,"Rest has no idle timer")
	world.game_time.debug_skip_minutes(9);check(actor.data.activity==Activity.RESTING,"Rest keeps its own ten-minute lifecycle")
	world.game_time.debug_skip_minutes(1);check(actor.data.activity==Activity.IDLE and queue.pending_count()==1,"Rest completion still enqueues next decision immediately")
	await Fixture.drain(world);world.free()
	# Natural need growth remains active during prolonged no-work/queue waiting.
	setup();duration=await period(17)
	actor.data.hunger=95
	world.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	requests=queue.requests
	world.game_time.debug_skip_minutes(90)
	check(actor.data.hunger==100 and actor.intents.forced_priority==200 and actor.intents.current_intent.reason_id==&"eat","Natural hunger growth interrupts prolonged idle/queued retry synchronously")
	check(queue.requests<=requests+1 and queue.pending_count()==0 and world.warehouse_data.resources.get_reserved_out(ResourceType.FOOD)==1,"Critical reaction cancels pending idle and reserves FOOD once during natural simulation time")
	world.free()
	# Same seed/events, unrelated resident/global draws cannot perturb this RNG.
	var sequences:=[]
	for repeat in 2:
		setup();actor.decision.rng.seed=991
		var sequence:=[]
		var other=world.resident_runtimes[1];other.decision._deciding=false
		for sample in 40:
			if repeat==1:
				for draw in 5:randf()
				other.decision.request_decision("unrelated")
			actor.decision.request_decision("fixture")
			await Fixture.drain(world)
			sequence.append(actor.decision._next_decision_at-world.game_time.total_minutes)
		sequences.append(sequence);world.free()
	check(sequences[0]==sequences[1],"Owned RNG reproduces periods despite unrelated/global draws")
	await process_frame
	print("Random idle: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
