extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Generator = preload("res://scripts/resident_generator.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Selector = preload("res://scripts/utility_selector.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Need = preload("res://scripts/need_type.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Definition = preload("res://scripts/building_definition.gd")
const HOME = preload("res://scripts/building_type.gd").Type.HOME
var failures := 0
var checks := 0
var events := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func value(rows: Array, id: String) -> float:
	for row in rows:
		if row.id == id: return row.priority
	return -1
func _run() -> void:
	var data = Data.new("traits", "Тест", 25)
	data.traits_changed.connect(func(): events += 1)
	check(data.add_trait(Trait.Type.SOCIABLE) and data.has_trait(Trait.Type.SOCIABLE), "Add/has trait_type")
	check(not data.add_trait(Trait.Type.SOCIABLE) and not data.add_trait(Trait.Type.INTROVERTED), "Duplicates/conflicts rejected without removing original")
	check(events == 1 and data.traits.size() == 1, "Rejected trait_type emits no change")
	check(data.remove_trait(Trait.Type.SOCIABLE) and not data.remove_trait(Trait.Type.SOCIABLE), "Remove and absent removal safe")
	check(events == 2 and data.traits.is_empty(), "Successful mutations emit one signal")
	data.add_trait(Trait.Type.INDUSTRIOUS)
	check(not data.add_trait(Trait.Type.LAZY), "Work traits conflict")
	data.remove_trait(Trait.Type.INDUSTRIOUS)
	data.add_trait(Trait.Type.LAZY)
	check(not data.add_trait(Trait.Type.INDUSTRIOUS), "Conflict symmetric")
	data.remove_trait(Trait.Type.LAZY)
	var first = Generator.new(123)
	var second = Generator.new(123)
	var other = Generator.new(456)
	var different := false
	for _index in range(100):
		var generated = first.generate()
		var alternative = other.generate()
		check(generated.traits == second.generate().traits, "Same seed reproducible")
		check(generated.traits.size() == 2 and generated.traits[0] != generated.traits[1] and generated.traits[1] != Trait.conflict(generated.traits[0]), "Exactly two unique compatible traits")
		different = different or generated.traits != alternative.traits
		var removed: int = generated.traits[0]
		generated.remove_trait(removed)
		check(not generated.has_trait(removed), "Traits remain mutable data, not recomputed from seed")
	check(different, "Different seed can change trait_type pair")
	var world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.game_logger.console_enabled = false
	for resident in world.residents: check(resident.traits.size() == 2, "All starting residents including Stepan generated with two traits")
	world.free()
	check(Modifiers.action_utility(data, Modifiers.Action.WORK, 7000) == 7000 and Modifiers.eat_threshold(data) == 30 and Modifiers.movement_speed(data, 120) == 120, "No traits preserves base values")
	for pair in [[Trait.Type.SOCIABLE, 5000], [Trait.Type.INTROVERTED, 3000]]:
		data.add_trait(pair[0])
		check(Modifiers.action_utility(data, Modifiers.Action.SOCIAL, 4000) == pair[1], "Social utility multiplier")
		check(Modifiers.action_utility(data, Modifiers.Action.WORK, 7000) == 7000, "Social trait_type leaves work unchanged")
		data.remove_trait(pair[0])
	for pair in [[Trait.Type.INDUSTRIOUS, 7700], [Trait.Type.LAZY, 6300]]:
		data.add_trait(pair[0])
		check(is_equal_approx(Modifiers.action_utility(data, Modifiers.Action.WORK, 7000), pair[1]), "Work utility multiplier")
		data.remove_trait(pair[0])
	check(Modifiers.selector_candidate_ratio(data) == 0.75 and Modifiers.selector_random_exponent(data) == 2, "Baseline selector parameters")
	data.add_trait(Trait.Type.FOOLISH)
	check(is_equal_approx(Modifiers.selector_candidate_ratio(data), 0.55) and Modifiers.selector_random_exponent(data) == 1.5, "Foolish selector parameters")
	var rows = [{"id":"BEST", "priority":1000}, {"id":"LOW", "priority":600}]
	var report = Selector.evaluate(rows, Modifiers.selector_candidate_ratio(data), Modifiers.selector_random_exponent(data))
	check(Selector.evaluate(rows).candidates.size() == 1 and report.candidates.size() == 2, "Foolish widens candidate set without discarding best")
	check(is_equal_approx(report.candidates[1].random_weight, pow(50, 1.5)), "Effective exponent used in existing weighting")
	var rng_a = RandomNumberGenerator.new()
	var rng_b = RandomNumberGenerator.new()
	rng_a.seed = 99
	rng_b.seed = 99
	for _index in range(30): check(Selector.pick(report, rng_a).id == Selector.pick(report, rng_b).id, "Foolish remains seeded deterministic")
	check(not FileAccess.get_file_as_string("res://scripts/utility_selector.gd").contains("trait_type"), "Selector has no trait_type dependency")
	check(Selector.debug_text("Тест", report, "BEST", []).contains("ratio=0.55 exponent=1.50"), "Debug shows effective parameters")
	data.remove_trait(Trait.Type.FOOLISH)
	data.add_trait(Trait.Type.RESTLESS)
	data.add_trait(Trait.Type.SOCIABLE)
	check(Modifiers.movement_speed(data, 120) == 132 and Modifiers.action_utility(data, Modifiers.Action.SOCIAL, 4000) == 5000, "Independent traits compose on separate parameters")
	check(Modifiers.eat_threshold(data) == 30 and Modifiers.selector_candidate_ratio(data) == 0.75, "Unrelated values unchanged")
	# Explicit base arguments exercise product and additive composition.
	check(Modifiers.movement_speed(data, 240) == 264, "Multiplier composes with supplied base")
	data.remove_trait(Trait.Type.RESTLESS)
	data.remove_trait(Trait.Type.SOCIABLE)
	data.add_trait(Trait.Type.GLUTTON)
	check(Modifiers.eat_threshold(data, 35) == 25 and Modifiers.eat_threshold(data, 5) == 0, "Additive threshold composes and clamps")
	data.hunger = 100
	check(Modifiers.eat_utility(data) == Balance.EAT_MAX_UTILITY * 1.2, "Glutton eat multiplier")
	check(Balance.WORK_PRIORITY == 7000 and Balance.EAT_MIN_HUNGER == 30 and Balance.UTILITY_CANDIDATE_RATIO == 0.75, "Base constants unchanged")

	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	var target = scene.resident_runtimes[3]
	scene.kitchen_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 5)
	actor.data.hunger = 25
	check(not actor.needs.has_food_action() and value(actor.decision.collect_actions(false), "EAT") == -1, "Ordinary hunger 25 unavailable")
	actor.data.add_trait(Trait.Type.GLUTTON)
	check(actor.needs.has_food_action() and value(actor.decision.collect_actions(false), "EAT") > 0, "Glutton hunger 25 available with positive nonlinear utility")
	actor.data.hunger = 50
	check(is_equal_approx(value(actor.decision.collect_actions(false), "EAT"), Modifiers.eat_utility(actor.data)), "Effective eat utility passed to selector")
	actor.data.remove_trait(Trait.Type.GLUTTON)
	actor.data.get_need(Need.Type.SOCIAL).value = 50
	actor.data.add_trait(Trait.Type.SOCIABLE)
	check(value(actor.decision.collect_actions(false), "SOCIAL") == 5000, "Social effective candidate")
	actor.data.add_trait(Trait.Type.INDUSTRIOUS)
	check(is_equal_approx(value(actor.decision.collect_actions(true), "WORK"), 7700), "Work effective candidate")
	actor.data.remove_trait(Trait.Type.SOCIABLE)
	actor.data.add_trait(Trait.Type.INTROVERTED)
	var task = Assignment.new(&"trait_talk", actor.data.id, Assignment.TALK_TO, StringName(target.data.id))
	check(actor.assignments.add(task) and value(actor.assignments.collect_actions(), "ASSIGNMENT:%s" % task.id) == 7000, "Introverted still permits TALK_TO with unchanged assignment utility")
	# UI receives trait_type mutations without processing frames, including on pause.
	var card = scene.get_node("HUD/ResidentCard")
	card.set_process(false)
	scene.resident_selection.select(actor.data)
	check(card.traits_label.text.contains("Нелюдимый") and not card.traits_label.text.contains("0.75"), "Card uses display names without numeric modifiers")
	actor.data.remove_trait(Trait.Type.INTROVERTED)
	check(not card.traits_label.text.contains("Нелюдимый"), "Removal signal updates card")
	paused = true
	actor.data.add_trait(Trait.Type.RESTLESS)
	check(card.traits_label.text.contains("Неусидчивый"), "Addition signal updates card on pause")
	paused = false
	card.traits_label.text = "event marker"
	card._refresh()
	check(card.traits_label.text == "event marker", "Frame refresh does not poll traits")
	scene.resident_selection.select(target.data)
	actor.data.add_trait(Trait.Type.FOOLISH)
	check(card.traits_label.text == "Черты: нет", "Selection disconnects previous resident's traits")
	# One movement resolver serves all intent sources, including forced player commands.
	actor.assignments.cancel(task.id)
	actor.view.global_position = Vector2.ZERO
	actor.commands.move_to(Vector2(1000, 0))
	actor.view._process(1)
	check(is_equal_approx(actor.view.global_position.x, actor.view.movement_speed * 1.1), "MOVE_TO uses effective movement speed")
	actor.view._process(100)
	actor.data.fatigue = 100
	check(actor.intents.current_intent.reason_id == &"critical_sleep" and actor.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY, "Foolish leaves forced critical fatigue unchanged")
	actor.commands.move_to(Vector2(500, 0))
	check(actor.intents.player_controlled and actor.intents.current_intent.reason_id == &"player_move", "PlayerCommand bypass still absolute")
	scene.free()
	for route in ["porter", "builder", "wander", "work", "eat", "sleep", "social"]:
		scene = Setup.make_scene(self)
		scene.game_time.debug_next_phase()
		actor = scene.resident_runtimes[1]
		actor.data.add_trait(Trait.Type.RESTLESS)
		actor.view.global_position = Vector2(-1000, -1000)
		match route:
			"porter":
				scene.player_control.assign_profession(actor.data.id, preload("res://scripts/resident_profession.gd").Type.PORTER)
				check(scene._request_haul_work(actor), "Actual porter task starts")
			"builder":
				scene.placement.select(Definition.for_type(HOME))
				scene.placement.update_position(Vector2(-500, 200))
				scene.placement.confirm()
				scene.player_control.assign_profession(actor.data.id, preload("res://scripts/resident_profession.gd").Type.BUILDER)
				check(actor.builder.request_work(), "Actual builder transport starts")
			"wander":
				actor.wander.target_available = func(): return true
				actor.wander.target_provider = func(_rng): return {"position": Vector2(1000, 1000)}
				check(actor.wander.try_wander(100), "Actual wander starts")
			"work":
				scene.player_control.assign_profession(actor.data.id, preload("res://scripts/resident_profession.gd").Type.GATHERER)
				actor.decision.work_available = scene.production.can_work.bind(actor.data)
				check(actor.schedule.request_work(), "Actual work trip starts")
			"eat":
				scene.kitchen_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 1)
				actor.data.hunger = 50
				check(actor.needs.try_eat(1000), "Actual eat trip starts")
			"sleep":
				actor.data.add_trait(Trait.Type.FOOLISH)
				scene.game_time.debug_skip_minutes(960)
				check(actor.intents.current_intent.reason_id == &"night_home", "Mandatory night home ignores foolish selector")
			"social":
				check(actor.social.try_social_at(StringName(scene.resident_runtimes[3].data.id), 1000), "Actual social trip starts")
		var origin: Vector2 = actor.view.global_position
		actor.view._process(1)
		check(is_equal_approx(actor.view.global_position.distance_to(origin), actor.view.movement_speed * 1.1), "Restless modifies actual %s movement" % route)
		check(Balance.WORK_CYCLE_MINUTES == 60 and Balance.BUILDER_WORK_CYCLE_MINUTES == 60, "Restless does not change work duration")
		if route in ["porter", "builder"]:
			actor.view._process(100)
			origin = actor.view.global_position
			actor.view._process(0.5)
			check(is_equal_approx(actor.view.global_position.distance_to(origin), actor.view.movement_speed * 1.1 * 0.5), "Actual carried-resource leg also uses modifier")
		scene.free()
	# Critical eat consumes one FOOD, preserves duration/recovery and bypasses the selector.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	actor.data.add_trait(Trait.Type.FOOLISH)
	actor.data.add_trait(Trait.Type.GLUTTON)
	var food = preload("res://scripts/resource_type.gd").Type.FOOD
	scene.kitchen_data.resources.add(food, 1)
	scene.game_time.minute_changed.disconnect(actor.needs._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.needs._on_minute_changed)
	var decisions: int = actor.decision.decision_count
	actor.data.hunger = 100
	check(actor.intents.forced_priority == 200 and actor.decision.decision_count == decisions, "Critical hunger bypasses trait selector")
	actor.view._process(100)
	check(actor.needs._minutes_left == 30 and scene.kitchen_data.resources.get_amount(food) == 0, "Glutton critical meal still consumes one FOOD for 30 minutes")
	scene.game_time.debug_skip_minutes(29)
	check(actor.data.hunger == 42 and actor.needs._meal_active, "Glutton recovery unchanged: 2 points per minute")
	scene.game_time.debug_skip_minutes(1)
	check(actor.data.hunger == 40 and not actor.needs._meal_active, "Meal completes normally with no extra effect")
	scene.free()
	print("Trait/modifier checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
