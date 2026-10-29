extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const S = preload("res://scripts/skill_type.gd").Type
const Source = preload("res://scripts/resource_source_ref.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	for xp in [0,2500,10000]: await deliveries(xp)
	print("Work delivery skills: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func deliveries(xp: int) -> void:
	for point in [Vector3(-10, 0, 16), Vector3(20, 0, -20)]:
		var world := F.create(self)
		var target: RefCounted = F.building(world, T.FOOD, point)
		var actor: Node = world.resident_runtimes[0]
		actor.data.add_skill_xp(S.LOGISTICS,xp)
		world.player_control.assign_profession(actor.data.id, P.COOK)
		var source := Source.new(Source.Kind.CONTAINER, world.warehouse_data.id)
		var job: RefCounted = world.logistics.claim_transport(actor.data.id, source, target, R.FOOD, func(): return true)
		check(job != null and world.logistics.start_claimed_job(job, actor.data.id), "Accepted non-porter job uses existing transport rules")
		var executor: RefCounted = world.logistics._executors[actor.data.id]
		var reentrant := func(_skill, _amount, _previous):
			executor._finish_delivery(actor.intents.current_intent)
			executor.cancel("nested completed cleanup")
		actor.data.skill_changed.connect(reentrant, CONNECT_ONE_SHOT)
		for tick in 16000:
			if not job.is_active(): break
			if actor.view._resume_after_frame == Engine.get_physics_frames():
				await physics_frame; await process_frame
			actor.view._physics_process(0.05)
			if executor.handling.is_active():
				var state: int=job.state
				var duration:=ceili(10.0/executor.handling._rate)
				world.game_time.debug_skip_minutes(duration-1)
				check(job.state==state,"Real handling has no early transfer at the skill rate")
				world.game_time.debug_skip_minutes(1)
				check(not executor.handling.is_active(),"Final whole-minute tick consumes handling once")
		check(job.state == job.State.COMPLETED and target.resources.get_amount(R.FOOD) == 1, "Actual resource transfer commits once on either route")
		check(actor.data.get_skill_xp(S.LOGISTICS) == mini(10000,xp+3) and actor.data.get_skill_xp(S.COOKING) == 0, "Fixed three Logistics XP, independent of profession and distance")
		executor._finish_delivery(actor.intents.current_intent)
		executor.cancel("repeat")
		check(actor.data.get_skill_xp(S.LOGISTICS) == mini(10000,xp+3) and actor.data.inventory.amount == 0, "Nested/repeated completion cannot duplicate XP or cargo")
		if actor.data.skill_changed.is_connected(reentrant): actor.data.skill_changed.disconnect(reentrant)
		world.free()
		await process_frame
