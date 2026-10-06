extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Need = preload("res://scripts/need_type.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const Seed = preload("res://tests/utility_test_seed.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func task(scene: Node, actor: Node, target: Node, id: StringName):
	var assignment := Assignment.new(id, actor.data.id, Assignment.TALK_TO, StringName(target.data.id))
	check(scene.player_control.add_assignment(actor.data.id, assignment), "Enqueue TALK_TO")
	return assignment
func hold(actor: Node, target: Node) -> void:
	actor.data.get_need(Need.SOCIAL).value = 100
	target.data.get_need(Need.SOCIAL).value = 100
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	var target = scene.resident_runtimes[3]
	var options: Array = scene.interactions.get_interactions([actor.data.id], StringName(target.data.id))
	var talk = options.filter(func(row): return row.id == &"talk")[0]
	check(scene.interactions.execute([actor.data.id], talk), "Context interaction creates assignment through PlayerControl")
	var assignment = actor.data.assignments[0]
	check(assignment.type == Assignment.TALK_TO and assignment.target == StringName(target.data.id), "Concrete resident ID")
	check(not scene.interactions.get_interactions([actor.data.id], StringName(actor.data.id)).any(func(row): return row.id == &"talk"), "No self talk menu")
	check(not scene.player_control.add_assignment(actor.data.id, Assignment.new(&"self", actor.data.id, Assignment.TALK_TO, StringName(actor.data.id))), "Simulation rejects self assignment")
	hold(actor, target)
	var actions: Array = actor.decision.collect_actions(false)
	check(actions.any(func(row): return row.id == "ASSIGNMENT:%s" % assignment.id and row.priority == 8000 + Balance.ASSIGNMENT_BONUS), "Social base utility plus same bonus")
	actor.decision.rng.seed = Seed.for_action(actions, "ASSIGNMENT:%s" % assignment.id)
	actor.decision.request_decision("test")
	check(assignment.state == Assignment.State.ACTIVE and actor.social._option.target_id == target.data.id, "Normal UtilitySelector starts exact target")
	check(actor.data.activity == Activity.MOVING, "Uses shared social movement")
	actor.view._process(20)
	check(actor.data.activity == Activity.TALKING and scene.social_world.group_of(actor.data.id) == scene.social_world.group_of(target.data.id), "Existing ConversationGroup")
	check(assignment.state == Assignment.State.ACTIVE, "Starting conversation does not complete")
	scene.game_time.debug_skip_minutes(14)
	check(assignment.state == Assignment.State.ACTIVE, "14 shared minutes insufficient")
	scene.game_time.debug_skip_minutes(1)
	check(assignment.state == Assignment.State.COMPLETED and actor.data.activity == Activity.TALKING, "15 shared minutes completes while conversation continues")
	scene.player_control.move_to(actor.data.id, Vector2(-500, 200))
	check(assignment.state == Assignment.State.COMPLETED, "Command after completion never rolls back")
	scene.free()
	# Enqueue is management, not interrupt, even while a committed leisure action runs.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	actor.social.try_leisure(100)
	var old = actor.intents.current_intent
	assignment = task(scene, actor, target, &"later")
	check(actor.intents.current_intent == old and actor.data.activity == Activity.RELAXING and assignment.state == Assignment.State.QUEUED, "Adding does not interrupt committed action")
	target.data.activity = Activity.WORKING
	check(actor.assignments.collect_actions().is_empty() and assignment.state == Assignment.State.QUEUED, "Temporary target unavailable stays queued")
	scene.social_world.residents.erase(target.data.id)
	check(actor.assignments.collect_actions().is_empty() and assignment.state == Assignment.State.CANCELLED, "Deleted target cancels")
	scene.free()
	# Commands and both critical needs share cleanup, preserving the result request.
	for interrupt in ["command", "hunger", "fatigue"]:
		for arrived in [false, true]:
			scene = Setup.make_scene(self)
			actor = scene.resident_runtimes[1]
			target = scene.resident_runtimes[3]
			hold(actor, target)
			assignment = task(scene, actor, target, &"interrupted")
			actor.assignments.start(assignment.id)
			if arrived:
				actor.view._process(20)
				scene.game_time.debug_skip_minutes(5)
			match interrupt:
				"command": scene.player_control.move_to(actor.data.id, Vector2(-500, 200))
				"hunger":
					scene.kitchen_data.resources.add(0, 1)
					actor.data.hunger = 100
				"fatigue": actor.data.fatigue = 100
			check(assignment.state == Assignment.State.QUEUED, "Incomplete interrupted talk returns queued: " + interrupt)
			check(scene.social_world.group_of(actor.data.id) == null, "Shared group cleanup: " + interrupt)
			scene.free()
	# Target may depart while a third participant keeps the group alive.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	var third = scene.resident_runtimes[2]
	hold(actor, target)
	third.data.get_need(Need.SOCIAL).value = 100
	assignment = task(scene, actor, target, &"short_target")
	actor.assignments.start(assignment.id)
	actor.view._process(20)
	third.social.try_social_at(StringName(actor.data.id), 8000)
	third.view._process(20)
	scene.game_time.debug_skip_minutes(5)
	scene.player_control.move_to(target.data.id, Vector2(-500, 200))
	check(assignment.state == Assignment.State.QUEUED and scene.social_world.group_of(actor.data.id).participants.size() == 2, "Target leaves early, active requeues while others continue")
	scene.game_time.debug_skip_minutes(15)
	check(assignment.state == Assignment.State.QUEUED, "Actor total time cannot replace pair shared time")
	scene.free()
	# Independent conversations complete oldest matching duplicate once, not every tick.
	for owned in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[1]
		target = scene.resident_runtimes[3]
		hold(actor, target)
		var oldest = task(scene, actor, target, &"z_oldest")
		var newer = task(scene, actor, target, &"a_newer")
		var latest = task(scene, actor, target, &"b_latest")
		if owned: actor.assignments.start(newer.id)
		else: actor.social.try_social_at(StringName(target.data.id), 8000)
		actor.view._process(20)
		scene.game_time.debug_skip_minutes(25)
		check((newer if owned else oldest).state == Assignment.State.COMPLETED, "Owned precedence or oldest independent matching request")
		check((oldest if owned else newer).state == Assignment.State.QUEUED and latest.state == Assignment.State.QUEUED, "Whole conversation closes one instance only")
		check(actor.data.assignments == [oldest, newer, latest], "Stable chronological duplicate history")
		scene.free()
	# Joining late counts only overlap, and conversation with another target does not match.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	third = scene.resident_runtimes[2]
	hold(actor, third)
	target.data.get_need(Need.SOCIAL).value = 100
	assignment = task(scene, actor, target, &"late_join")
	actor.social.try_social_at(StringName(third.data.id), 8000)
	actor.view._process(20)
	scene.game_time.debug_skip_minutes(15)
	check(assignment.state == Assignment.State.QUEUED, "Other resident conversation does not match")
	target.social.try_social_at(StringName(actor.data.id), 8000)
	target.view._process(20)
	scene.game_time.debug_skip_minutes(14)
	check(assignment.state == Assignment.State.QUEUED, "Late group participant needs own 15-minute overlap")
	scene.game_time.debug_skip_minutes(1)
	check(assignment.state == Assignment.State.COMPLETED, "Late participant 15 shared minutes meets result")
	scene.free()
	# Invitation still supports SOCIAL=0, without a new refusal rule.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	assignment = task(scene, actor, target, &"zero_social")
	check(actor.assignments.start(assignment.id), "Zero SOCIAL does not reject assignment or partner")
	actor.view._process(20)
	check(actor.data.activity == Activity.TALKING and target.data.activity == Activity.TALKING, "Zero SOCIAL target accepts existing invitation")
	scene.free()
	# Event-driven target availability wakes an idle requester, not a committed actor.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	target.data.activity = Activity.WORKING
	assignment = task(scene, actor, target, &"world_event")
	actor.decision._next_decision_at = scene.game_time.total_minutes + 1000
	check(actor.assignments.collect_actions().is_empty(), "Unavailable TALK_TO excluded without retry")
	target.data.activity = Activity.IDLE
	await process_frame
	check(assignment.state == Assignment.State.ACTIVE, "Availability event starts normal choice without clock polling")
	scene.free()
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	target.data.activity = Activity.WORKING
	assignment = task(scene, actor, target, &"not_forced")
	actor.social.try_leisure(100)
	old = actor.intents.current_intent
	target.data.activity = Activity.IDLE
	await process_frame
	check(assignment.state == Assignment.State.QUEUED and actor.intents.current_intent == old, "Availability never interrupts committed leisure")
	scene.free()
	# A route invalidated by target work returns queued; real deletion cancels immediately.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[3]
	assignment = task(scene, actor, target, &"route_invalid")
	actor.assignments.start(assignment.id)
	target.data.activity = Activity.WORKING
	scene.game_time.debug_skip_minutes(1)
	check(assignment.state == Assignment.State.QUEUED and actor.assignments.active_assignment == null, "Invalidated exact target route requeues")
	scene.social_world.unregister(target.data.id)
	check(assignment.state == Assignment.State.CANCELLED, "Unregistered target cancels waiting request via world event")
	scene.free()
	# Target departing at exactly 15 must not erase the just-earned result, even if its
	# minute listener precedes the actor's. SOCIAL=0 can voluntarily exit here.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	target = scene.resident_runtimes[0]
	assignment = task(scene, actor, target, &"boundary")
	actor.assignments.start(assignment.id)
	actor.view._process(20)
	var probe := RandomNumberGenerator.new()
	for seed_value in range(100):
		probe.seed = seed_value
		if probe.randf() < Balance.CONVERSATION_EXIT_CHANCE:
			target.social.rng.seed = seed_value
			break
	scene.game_time.debug_skip_minutes(15)
	check(assignment.state == Assignment.State.COMPLETED, "Before-membership-change checkpoint preserves exact 15-minute success")
	scene.free()
	print("TALK_TO assignments: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
