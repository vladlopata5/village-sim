extends SceneTree
const Selector = preload("res://scripts/utility_selector.gd")
const Seed = preload("res://tests/utility_test_seed.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Intent = preload("res://scripts/resident_intent.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Clock = preload("res://scripts/game_time.gd")
const Data = preload("res://scripts/resident_data.gd")
var failures := 0
var messages: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var example: Array = [{"id": "WORK", "priority": 7000}, {"id": "EAT", "priority": 6500}, {"id": "SOCIAL", "priority": 6500}, {"id": "LEISURE", "priority": 6000}, {"id": "REST", "priority": 6000}, {"id": "WEAK", "priority": 5000}]
	var report := Selector.evaluate(example)
	check(report.max_priority == 7000 and report.threshold == 5250, "75 percent candidate cutoff")
	check(report.candidates.size() == 5 and report.discarded[0].id == "WEAK", "Weak utility is discarded")
	check(report.candidates[0].shifted == 1750 and report.candidates[1].shifted == 1250, "Shifted utility matches agreed example")
	check(report.candidates[0].random_weight == 3062500 and report.candidates[3].random_weight == 562500, "Exponent two is applied")
	var edge := Selector.evaluate([{"id": "WORK", "priority": 7000}, {"id": "EDGE", "priority": 5250}])
	check(edge.candidates.size() == 2 and edge.candidates[1].shifted == 1.0, "Inclusive cutoff retains boundary with minimum weight one")
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 12345
	rng_b.seed = 12345
	for draw in range(200): check(Selector.pick(report, rng_a).id == Selector.pick(report, rng_b).id, "Same seed gives same sequence")
	var counts: Dictionary = {"WORK": 0, "EAT": 0, "SOCIAL": 0, "LEISURE": 0, "REST": 0}
	for seed_value in range(10000):
		rng_a.seed = seed_value
		var selected: Dictionary = Selector.pick(report, rng_a)
		check(selected.id != "WEAK", "Below-cutoff action is never selected")
		counts[selected.id] += 1
	check(counts.WORK > counts.EAT and counts.EAT > counts.LEISURE and counts.REST > 0, "Higher utility is statistically more frequent; different seeds produce alternatives")
	var only := Selector.evaluate([{"id": "WORK", "priority": 7000}, {"id": "EAT", "priority": 5000}, {"id": "SOCIAL", "priority": 1000}])
	for seed_value in range(100):
		rng_a.seed = seed_value
		check(Selector.pick(only, rng_a).id == "WORK", "Single surviving candidate always wins")
	check(Selector.pick(Selector.evaluate([]), rng_a) == null, "Empty action pool has no random action")
	print("Deterministic RNG: seed=12345 reproduces 200 draws; 10000 seeds counts=", counts)
	for action_id in ["WORK", "EAT", "LEISURE"]:
		rng_a.seed = Seed.for_action(example, action_id)
		print("[06:00][AI][DEBUG] ", Selector.debug_text("Тест", report, Selector.pick(report, rng_a).id, []))
	var scene = Setup.make_scene(self)
	var resident = scene.resident_runtimes[0]
	for runtime in scene.resident_runtimes:
		if runtime != resident: runtime.data.activity = Activity.WORKING
	resident.data.hunger = 29
	resident.data.get_need(Type.SOCIAL).value = 100
	var actions: Array = resident.decision.collect_actions(false)
	check(actions.is_empty(), "EAT below minimum, SOCIAL without partner and unavailable WORK excluded")
	resident.data.hunger = 80
	check(resident.decision.collect_actions(false).is_empty(), "No available FOOD excludes EAT")
	resident.data.activity = Activity.WORKING
	scene.kitchen_data.resources.add(FOOD, 1)
	resident.data.activity = Activity.IDLE
	# Keep availability event from starting an action before the read-only check.
	var amount: int = scene.kitchen_data.resources.get_amount(FOOD)
	var reserved: int = scene.kitchen_data.resources.get_reserved_out(FOOD)
	actions = resident.decision.collect_actions(false)
	check(actions.size() == 1 and actions[0].id == "EAT", "Only available EAT enters pool")
	check(scene.kitchen_data.resources.get_amount(FOOD) == amount and scene.kitchen_data.resources.get_reserved_out(FOOD) == reserved, "Gathering actions never reserves resources")
	scene.free()
	# Critical and forced paths never consume the normal selector's RNG.
	for critical_type in [Type.HUNGER, Type.FATIGUE]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		scene.kitchen_data.resources.add(FOOD, 1)
		resident.intents.submit(Intent.new(Intent.Type.NONE, &"locked", Vector2.ZERO, 90000, false))
		resident.decision.rng.seed = 987
		var saved_state: int = resident.decision.rng.state
		resident.data.get_need(critical_type).value = 100
		check(resident.intents.current_intent.reason_id == (&"eat" if critical_type == Type.HUNGER else &"critical_sleep"), "Critical action always replaces locked action")
		check(resident.decision.rng.state == saved_state, "Critical action bypasses weighted RNG")
		resident.intents.force_set_intent(Intent.new(Intent.Type.NONE, &"forced_test", Vector2.ZERO, 999999, false), 999)
		check(resident.decision.rng.state == saved_state and resident.intents.current_intent.reason_id == &"forced_test", "Forced intent bypasses random selection")
		scene.free()
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[0]
	resident.decision.rng.seed = 456
	var night_rng_state: int = resident.decision.rng.state
	resident.schedule._on_phase_changed("Ночь")
	check(resident.intents.current_intent.reason_id == &"night_home" and resident.decision.rng.state == night_rng_state, "Mandatory night schedule bypasses random selection")
	scene.free()
	# Current values are logged at action start, rather than cached decision values.
	for action_id in ["EAT", "SOCIAL", "LEISURE"]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		messages.clear()
		scene.game_logger.debug_enabled = true
		scene.game_logger.line_logged.connect(func(line: String, _level: int): messages.append(line))
		scene.kitchen_data.resources.add(FOOD, 1)
		var need_type: int = {"EAT": Type.HUNGER, "SOCIAL": Type.SOCIAL, "LEISURE": Type.LEISURE}[action_id]
		resident.data.get_need(need_type).value = 80
		resident.decision.request_decision()
		if action_id != "LEISURE": resident.view._process(100)
		var parameter: String = {"EAT": "HUNGER=80, utility=5102", "SOCIAL": "SOCIAL=80, priority=6400", "LEISURE": "LEISURE=80, priority=6000"}[action_id]
		check(messages.any(func(line): return parameter in line), "INFO action start includes current need and priority")
		check(messages.any(func(line): return "[AI][DEBUG]" in line and "max_priority=" in line and "threshold=" in line and "shifted=" in line and "random_weight=" in line and "selected=" in line and "discarded=" in line), "DEBUG decision includes pool, cutoff, weights, exclusions and selection")
		scene.free()
	# 1500 minutes gives exact integer growth: old sleeping rate 30, new rate 6.
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	var data = Data.new("sleep_test", "Тест", 30)
	data.activity = Activity.SLEEPING
	var dynamics = Dynamics.new()
	root.add_child(dynamics)
	dynamics.setup(clock, data)
	clock.advance(1500)
	check(data.get_need(Type.SOCIAL).value == 6 and data.get_need(Type.LEISURE).value == 6, "Sleep SOCIAL/LEISURE multiplier 0.2 preserves nonzero growth, five times below previous sleeping rate")
	clock.free()
	dynamics.free()
	print("Utility selection checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
