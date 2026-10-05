extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Utility = preload("res://scripts/action_utility.gd")
const Selector = preload("res://scripts/utility_selector.gd")
const Seed = preload("res://tests/utility_test_seed.gd")
const Target = preload("res://scripts/wander_target.gd")
const Group = preload("res://scripts/conversation_group.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func listen(scene: Node) -> void:
	lines.clear()
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
func enable_wander(scene: Node, runtime: Node) -> void:
	runtime.wander.target_provider = scene._wander_target_2d.bind(runtime.data.id)
func work_choices() -> int:
	var count := 0
	for line in lines:
		if "Фёдор: выбрал работу (priority=7000)" in line: count += 1
	return count
func _run() -> void:
	# Before this fix: one decision and two identical logs at 07:14.
	var scene = Setup.make_scene(self)
	var resident = scene.resident_runtimes[2]
	resident.data.work_location_id = scene.gatherer_hut_data.id
	resident.decision.work_available = scene.production.can_work.bind(resident.data)
	listen(scene)
	scene.game_time.total_minutes = 434
	var before: int = resident.decision.decision_count
	resident.schedule._on_phase_changed("День")
	check(resident.decision.decision_count == before + 1 and work_choices() == 1, "07:14: exactly one work decision and one choice log, no filtering")
	print("Regression 07:14: decisions=1; work INFO=1 (before fix: decisions=1, INFO=2)")
	resident.view._process(20)
	before = resident.decision.decision_count
	lines.clear()
	scene.game_time.debug_skip_minutes(60)
	check(resident.decision.decision_count == before + 1 and work_choices() == 1, "Cycle completion starts exactly one new decision without a second schedule draw")
	scene.free()
	# Normal completion outside a phase boundary.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	resident.data.get_need(Type.LEISURE).value = 80
	resident.decision.request_decision()
	resident.data.get_need(Type.LEISURE).value = 0
	before = resident.decision.decision_count
	scene.game_time.debug_skip_minutes(30)
	check(resident.decision.decision_count == before + 1, "Normal action completion creates exactly one decision point")
	scene.free()
	# An idle minute deadline and phase_changed used to each request a free decision.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	scene.game_time.total_minutes = 419
	resident.decision._next_decision_at = 420
	before = resident.decision.decision_count
	scene.game_time.debug_skip_minutes(1)
	check(resident.decision.decision_count == before + 1, "Coincident idle deadline and phase_changed create one normal decision, even without fallback target")
	scene.free()
	# Completion and phase_changed in the same minute have a single owner.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	scene.game_time.total_minutes = 390
	resident.data.get_need(Type.LEISURE).value = 80
	resident.decision.request_decision()
	resident.data.get_need(Type.LEISURE).value = 0
	resident.data.work_location_id = scene.gatherer_hut_data.id
	resident.decision.work_available = scene.production.can_work.bind(resident.data)
	before = resident.decision.decision_count
	listen(scene)
	scene.game_time.debug_skip_minutes(30)
	check(resident.decision.decision_count == before + 1 and work_choices() == 1 and resident.intents.current_intent.reason_id == &"day_work", "07:00 completion waits for phase_changed instead of deciding against stale morning schedule")
	scene.free()
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	scene.game_time.total_minutes = 1350
	resident.schedule._on_phase_changed("Вечер")
	resident.data.get_need(Type.LEISURE).value = 80
	resident.decision.request_decision()
	resident.data.get_need(Type.LEISURE).value = 0
	var saved_rng: int = resident.decision.rng.state
	scene.game_time.debug_skip_minutes(30)
	check(resident.intents.current_intent.reason_id == &"night_home" and resident.decision.rng.state == saved_rng, "23:00 completion yields to mandatory night without random work/idle decision")
	scene.free()
	# Random nearby candidate is reachable on the open prototype field.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[0]
	enable_wander(scene, resident)
	var random := RandomNumberGenerator.new()
	for origin in [Vector2.ZERO, Vector2(-1599, -999), Vector2(1599, 999)]:
		for seed_value in range(100):
			random.seed = seed_value
			var target = Target.nearby(origin, random, scene.field.FIELD)
			check(target != null and scene.field.FIELD.has_point(target.position) and origin.distance_to(target.position) <= Balance.WANDER_RADIUS + 0.01, "Wander candidate stays inside reachable field and radius")
	resident.data.get_need(Type.SOCIAL).value = 10
	resident.data.get_need(Type.LEISURE).value = 10
	resident.decision.request_decision()
	check(resident.intents.current_intent.reason_id == &"wander" and resident.decision.last_selection.candidates[0].id == "WANDER", "WANDER is selected by unchanged UtilitySelector as fallback")
	var destination: Vector2 = resident.intents.current_intent.target_position
	before = resident.decision.decision_count
	resident.view._process(20)
	check(resident.view.global_position == destination and resident.intents.current_intent.type == Intent.Type.NONE and resident.intents.current_intent.reason_id == &"wander", "Wander reaches candidate and retains a stationary stay")
	check(resident.decision.decision_count == before, "Arrival is a walk stage, not a premature new decision")
	scene.game_time.minute_changed.connect(resident.need_dynamics._on_minute_changed)
	scene.game_time.debug_skip_minutes(Balance.WANDER_STAY_MINUTES - 1)
	check(resident.decision.decision_count == before, "Wander stays for configured game time")
	scene.game_time.debug_skip_minutes(2)
	check(resident.decision.decision_count == before + 1, "Crossed stay deadline completes one action and creates one decision")
	check(resident.data.get_need(Type.SOCIAL).value >= 10 and resident.data.get_need(Type.LEISURE).value >= 10, "Wander never satisfies SOCIAL or LEISURE")
	scene.free()
	# Fallback must not prevent daytime work or manual control.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	enable_wander(scene, resident)
	resident.decision.request_decision()
	check(resident.schedule.request_manual_move(Vector2.ZERO), "Manual command can replace fallback in morning")
	resident.intents.cancel_current(resident.intents.current_intent)
	resident.decision.request_decision()
	resident.data.work_location_id = scene.gatherer_hut_data.id
	resident.decision.work_available = scene.production.can_work.bind(resident.data)
	scene.game_time.total_minutes = 419
	before = resident.decision.decision_count
	scene.game_time.debug_skip_minutes(1)
	check(resident.intents.current_intent.reason_id == &"day_work" and resident.decision.decision_count == before + 1, "Daytime obligation replaces fallback with exactly one decision")
	scene.free()
	# Group center and slots are stable, including zero-social invited participants.
	scene = Setup.make_scene(self)
	var residents: Array = scene.resident_runtimes
	enable_wander(scene, residents[1])
	residents[1].decision.request_decision()
	residents[1].view._process(20)
	var option := {"target_id": residents[1].data.id, "group_id": 0}
	check(scene.social_world.valid_option(option) and scene.social_world.arrive(residents[0].data.id, option), "SOCIAL=0 idle wander-stay participant accepts invitation")
	var group = scene.social_world.group_of(residents[0].data.id)
	var old_center: Vector2 = group.center
	for runtime in residents.slice(0, 2): runtime.view._process(20)
	check(residents[0].view.global_position != residents[1].view.global_position and residents[1].data.activity == Activity.TALKING, "Two talking residents stand at different actual positions")
	var old_positions: Dictionary = group.positions.duplicate()
	for index in [2, 3]:
		check(scene.social_world.arrive(residents[index].data.id, {"target_id": residents[1].data.id, "group_id": group.id}), "New participant joins existing conversation")
		residents[index].view._process(20)
		check(group.positions.values().count(residents[index].view.global_position) == 1, "New participant receives a unique free place")
	for id in old_positions: check(group.positions[id] == old_positions[id], "Existing participants never reshuffle when someone joins")
	check(group.center == old_center and group.participants.size() == 4, "Four-person group retains center")
	residents[0].data.fatigue = 100
	check(group.participants.size() == 3 and not group.positions.has(residents[0].data.id), "Forced departure releases only departing participant's slot")
	print("Conversation proof: 4 distinct view positions; SOCIAL=0 accepted; forced departure leaves 3")
	scene.free()
	var large_group = Group.new(1)
	for index in range(12): large_group.add_participant(str(index))
	check(large_group.positions.size() == 12, "Formation has no fixed participant cap")
	for position in large_group.positions.values(): check(large_group.positions.values().count(position) == 1, "Additional rings retain unique positions")
	# Need value stays linear state; EAT attractiveness uses its own response curve.
	check(Utility.eat(29) == 0 and Utility.eat(30) == 0, "Minimum threshold maps to zero utility")
	check(absf(Utility.eat(50) - 816.3265) < 0.01 and absf(Utility.eat(70) - 3265.3061) < 0.01 and absf(Utility.eat(90) - 7346.9388) < 0.01, "Nonlinear utility increases through 50/70/90")
	check(Utility.eat(100) == Balance.EAT_MAX_UTILITY, "Critical threshold reaches maximum utility")
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[0]
	enable_wander(scene, resident)
	scene.kitchen_data.resources.add(FOOD, 2)
	resident.data.hunger = 29
	check(not resident.needs.has_food_action() and not resident.decision.collect_actions(false).any(func(row): return row.id == "EAT"), "Hunger below 30 excludes EAT")
	resident.data.hunger = 30
	var actions: Array = resident.decision.collect_actions(false)
	check(resident.needs.has_food_action() and actions.any(func(row): return row.id == "EAT" and row.priority == 0), "Hunger 30 is available with zero action utility")
	resident.data.hunger = 80
	var report := Selector.evaluate(resident.decision.collect_actions(true))
	check(report.discarded.any(func(row): return row.id == "EAT") and report.candidates[0].id == "WORK", "EAT 5102 falls below work cutoff 5250")
	resident.data.hunger = 70
	check(not resident.decision.has_more_important_action(5000), "Conversation exit compares EAT curve 3265, not linear hunger priority 7000")
	resident.data.hunger = 90
	check(resident.decision.has_more_important_action(5000), "Higher nonlinear EAT can win at a conversation recheck")
	check(resident.data.get_need(Type.HUNGER).get_priority() == 9000, "Need priority is unchanged by action response curve")
	report = Selector.evaluate(resident.decision.collect_actions(true))
	check(report.candidates.any(func(row): return row.id == "EAT") and report.candidates.any(func(row): return row.id == "WORK"), "EAT 7347 competes with work under existing weighted cutoff")
	resident.decision.rng.seed = 123
	saved_rng = resident.decision.rng.state
	resident.intents.submit(Intent.new(Intent.Type.NONE, &"locked", Vector2.ZERO, 999999, false))
	resident.data.hunger = 100
	check(resident.intents.current_intent.reason_id == &"eat" and resident.intents.forced_priority == 200 and resident.decision.rng.state == saved_rng, "Critical hunger still bypasses selector and noninterruptibility")
	scene.free()
	# Real DEBUG report includes both ordinary WANDER and nonlinear EAT.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[0]
	enable_wander(scene, resident)
	scene.kitchen_data.resources.add(FOOD, 1)
	resident.data.hunger = 45
	listen(scene)
	scene.game_logger.debug_enabled = true
	resident.decision.rng.seed = Seed.for_action(resident.decision.collect_actions(false), "EAT")
	resident.decision.request_decision()
	resident.view._process(20)
	check(lines.any(func(line): return "EAT hunger=45 utility=459.18 shifted=" in line and "WANDER priority=500.00 shifted=" in line), "DEBUG reports curve utility and WANDER candidates without changing selector")
	check(lines.any(func(line): return "HUNGER=45, utility=459" in line), "Meal INFO logs current hunger and curve utility")
	for line in lines:
		if "[AI][DEBUG]" in line: print(line)
	scene.free()
	print("Behavior pass checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
