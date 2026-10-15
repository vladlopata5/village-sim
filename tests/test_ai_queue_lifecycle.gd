extends SceneTree
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const N=preload("res://scripts/need_type.gd").Type
const A=preload("res://scripts/resident_activity.gd").Type
const Fixture=preload("res://tests/ai_queue_fixture.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1;push_error(message)
func setup(count: int=4) -> Node:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false);world.game_logger.console_enabled=false
	world.social_events.enabled=false
	if count>4:world.debug_spawn.spawn_residents(Vector3(12,0,18),count-4,P.NONE)
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		world.player_control.assign_profession(actor.data.id,P.NONE)
		actor.view.set_physics_process(false)
		actor.wander.target_provider=Callable()
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	world.game_time.total_minutes=600
	for actor in world.resident_runtimes:actor.schedule._phase="День"
	Fixture.one_per_slice(world)
	world.decision_dispatcher.clear()
	return world
func tick(world: Node) -> void:
	await process_frame;world.decision_dispatcher._process(0)
func run() -> void:
	var world=setup();var actor=world.resident_runtimes[0];var queue=world.decision_dispatcher
	actor.decision._deciding=false
	var food:int=world.warehouse_data.resources.get_amount(R.FOOD)
	actor.decision.request_decision("completed")
	actor.decision.request_decision("phase_changed")
	check(queue.pending_count()==1 and actor.decision.decision_count==0,"Ordinary requests coalesce before selection")
	check(world.warehouse_data.resources.get_reserved_out(R.FOOD)==0 and world.warehouse_data.resources.get_amount(R.FOOD)==food,"Enqueue has no resource ownership")
	await tick(world)
	check(actor.decision.decision_count==1 and queue.pending_count()==0 and actor.data.activity==A.IDLE,"Fresh ordinary decision uses current state")
	actor.decision.request_decision("free")
	actor.data.profession=P.BUILDER # Simulate a changed context without a replacement notification.
	var before:int=actor.decision.decision_count
	var discarded:int=queue.discarded
	await tick(world)
	check(actor.decision.decision_count==before and queue.discarded==discarded+1 and queue.pending_count()==1,"Stale profession rejected and freshly scheduled")
	await tick(world);check(actor.decision.decision_count==before+1,"Fresh role eventually serviced")
	actor.decision.request_decision("free")
	world.game_time.total_minutes=1020;actor.schedule._phase="Вечер"
	before=actor.decision.decision_count;await tick(world)
	check(actor.decision.decision_count==before and queue.pending_count()==1,"Stale phase cannot launch old daytime work")
	await tick(world);check(actor.decision.decision_count==before+1,"Current phase gets new ordinary plan")
	actor.needs.try_rest(80)
	world.game_time.debug_skip_minutes(10)
	check(actor.data.activity==A.IDLE and not actor.intents.has_current_action() and queue.pending_count()==1,"Rest finishes synchronously, no fictional RESTING while queued")
	before=actor.decision.decision_count;await tick(world)
	check(actor.decision.decision_count==before+1,"Rest continuation serviced later")
	actor.decision.request_decision("free")
	world.player_control.unregister_resident(actor.data.id)
	check(queue.pending_count()==0,"Unregister cancels resident entry immediately")
	world.free()
	# Last ordinary FOOD is claimed only during service, never by both waiting residents.
	world=setup();queue=world.decision_dispatcher
	world.warehouse_data.resources.try_take(R.FOOD,19)
	for index in 2:
		actor=world.resident_runtimes[index]
		actor.data.get_need(N.HUNGER).base_weight=100
		actor.data.hunger=80;actor.decision._deciding=false
		actor.decision.request_decision("completed")
	check(queue.pending_count()==2 and world.warehouse_data.resources.get_reserved_out(R.FOOD)==0,"Two ordinary contenders carry no preclaims")
	await Fixture.drain(world)
	var eaters:=0
	for candidate in world.resident_runtimes:
		if candidate.intents.current_intent.reason_id==&"eat":eaters+=1
	check(eaters==1 and world.warehouse_data.resources.get_reserved_out(R.FOOD)==1 and world.warehouse_data.resources.get_amount(R.FOOD)==1,"Live service atomically reserves last FOOD once; no premature consumption")
	world.free()
	for speed in [1,2,4,10,20]:
		world=setup(34);queue=world.decision_dispatcher
		world.game_time.set_speed(speed)
		for candidate in world.resident_runtimes:
			candidate.decision._deciding=false
			candidate.decision.request_decision("idle_completed")
		actor=world.resident_runtimes[-1]
		var ordinary_before:int=queue.executed
		actor.data.hunger=100
		check(actor.intents.forced_priority==200 and actor.intents.current_intent.reason_id==&"eat" and queue.executed==ordinary_before,"Critical hunger immediate ahead of 33 ordinary residents x%d"%speed)
		check(queue.critical_reactions>=1 and queue.pending_count()==33,"Critical ownership removes its ordinary entry x%d"%speed)
		var tired=world.resident_runtimes[-2]
		tired.data.fatigue=100
		check(tired.intents.current_intent.reason_id==&"critical_sleep" and tired.data.activity==A.SLEEPING,"Critical fatigue retains synchronous forced action x%d"%speed)
		world.developer_panel.show();world.developer_panel._process(0)
		check(world.developer_panel.ai_queue_label.text.contains("AI Queue") and queue.statistics().pending==32,"F10 reads queue statistics without running decisions")
		world.developer_panel.hide()
		await Fixture.drain(world)
		check(queue.pending_count()==0 and world.resident_runtimes.all(func(candidate):return candidate.decision.decision_count>0 or candidate.intents.forced_priority>0),"Ordinary population drains without starving x%d"%speed)
		check(world.warehouse_data.resources.get_reserved_out(R.FOOD)==1,"Background service preserves critical FOOD reservation")
		world.free()
	await process_frame
	print("AI queue lifecycle: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
