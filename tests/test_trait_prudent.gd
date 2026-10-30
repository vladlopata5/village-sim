extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Selector = preload("res://scripts/utility_selector.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Generator = preload("res://scripts/resident_generator.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var normal := Data.new("normal", "Обычный", 25)
	var prudent := Data.new("prudent", "Рассудительный", 25)
	var foolish := Data.new("foolish", "Балбес", 25)
	prudent.add_trait(Trait.Type.PRUDENT); foolish.add_trait(Trait.Type.FOOLISH)
	var actions := [{"id":"BEST", "priority":1000}, {"id":"HIGH", "priority":900}, {"id":"MID", "priority":800}, {"id":"LOW", "priority":600}]
	var reports: Array = []
	for row in [[normal, 0.75, 2.0, 3], [foolish, 0.55, 1.5, 4], [prudent, 0.85, 2.5, 2]]:
		var ratio := Modifiers.selector_candidate_ratio(row[0]); var exponent := Modifiers.selector_random_exponent(row[0])
		check(is_equal_approx(ratio, row[1]) and is_equal_approx(exponent, row[2]), "Exact neutral, FOOLISH and PRUDENT parameters")
		var report := Selector.evaluate(actions, ratio, exponent); reports.append(report)
		check(report.candidates.size() == row[3] and is_equal_approx(report.threshold, 1000 * row[1]), "Different utility values respect personal cutoff")
		check(report.candidates[0].id == "BEST" and report.candidates.all(func(item): return item.random_weight > 0), "Best retained; every eligible candidate keeps a positive probability")
		var rng := RandomNumberGenerator.new(); rng.seed = 135
		for only in [[{"id":"ONLY", "priority":7000}], [{"id":"ONLY", "priority":0}]]:
			var single := Selector.evaluate(only, ratio, exponent)
			check(Selector.pick(single, rng).id == "ONLY", "Single admissible action always selected, including zero utility")
		check(Selector.pick(Selector.evaluate([], ratio, exponent), rng) == null, "No actions safely yields no choice")
	check(actions == [{"id":"BEST", "priority":1000}, {"id":"HIGH", "priority":900}, {"id":"MID", "priority":800}, {"id":"LOW", "priority":600}], "Selection does not mutate utility inputs")
	check(is_equal_approx(reports[2].candidates[0].random_weight, pow(150.0, 2.5)) and is_equal_approx(reports[2].candidates[1].random_weight, pow(50.0, 2.5)), "Exponent applied once to existing shifted weights")
	var boundary := Selector.evaluate([{"id":"BEST", "priority":1000}, {"id":"EDGE", "priority":850}, {"id":"OUT", "priority":849}], 0.85, 2.5)
	check(boundary.candidates.size() == 2 and boundary.candidates[1].random_weight == 1, "Exact cutoff remains eligible; below cutoff excluded")
	var counts: Array = []
	for report in reports:
		var rng := RandomNumberGenerator.new(); rng.seed = 77
		var replay := RandomNumberGenerator.new(); replay.seed = 77
		var count: Dictionary = {}
		for draw in 30000:
			var selected: Dictionary = Selector.pick(report, rng)
			count[selected.id] = count.get(selected.id, 0) + 1
			if draw < 50: check(selected.id == Selector.pick(report, replay).id, "Seeded choice is deterministic")
		counts.append(count)
	check(counts[2].get("BEST", 0) > counts[0].get("BEST", 0) and counts[2].get("HIGH", 0) > 0 and not counts[2].has("MID") and not counts[2].has("LOW"), "PRUDENT favors best utility without forcing a single choice")
	check(not prudent.add_trait(Trait.Type.FOOLISH) and not foolish.add_trait(Trait.Type.PRUDENT), "Conflict remains symmetric and preserves incumbent")
	for action in Modifiers.Action.values(): check(Modifiers.action_utility(prudent, action, 5000) == Modifiers.action_utility(normal, action, 5000), "PRUDENT changes no action utility")
	check(Modifiers.social_need_rate(prudent, 60) == 60 and Modifiers.leisure_need_rate(prudent, -180, false) == -180 and Modifiers.movement_speed(prudent, 120) == 120 and Modifiers.eat_threshold(prudent) == 30, "No need, movement or eating changes")
	check(Balance.UTILITY_CANDIDATE_RATIO == 0.75 and Balance.UTILITY_RANDOM_EXPONENT == 2.0 and Balance.FOOLISH_UTILITY_CANDIDATE_RATIO == 0.55 and Balance.FOOLISH_UTILITY_RANDOM_EXPONENT == 1.5, "All pre-existing selector constants unchanged")
	_generation()
	_live()
	print("PRUDENT: ", checks, " checks, ", failures, " failures; synthetic choices ", counts)
	quit(0 if failures == 0 else 1)
func _generation() -> void:
	var generator := Generator.new(91); var replay := Generator.new(91)
	var found := 0
	for index in 1000:
		var person = generator.generate(); var same = replay.generate()
		check(person.traits.size() == 2 and Trait.compatible(person.traits) and person.traits == same.traits, "Two compatible traits with reproducible order")
		check(person.trait_description() == same.trait_description(), "Generation preserves stable composite description")
		for type in person.traits + person.liked_traits + person.disliked_traits:
			check(type in Trait.GENERATION_POOL and type not in [Trait.Type.CARING, Trait.Type.DELIBERATE], "Two unfinished traits excluded from random issue")
		if person.has_trait(Trait.Type.PRUDENT):
			found += 1
			check(not person.has_trait(Trait.Type.FOOLISH), "Generated PRUDENT never conflicts with FOOLISH")
	check(found > 0 and Trait.GENERATION_POOL.size() == 11, "PRUDENT remains in normal generation alongside HOTHEADED/CALM")
	check(Trait.description([Trait.Type.INTROVERTED, Trait.Type.PRUDENT]) == "Замкнутый прагматик" and Trait.description([Trait.Type.PRUDENT, Trait.Type.GLUTTON], Trait.GrammaticalGender.FEMININE) == "Рассудительная обжора", "Both grammatical forms compose with PRUDENT")
func _live() -> void:
	var world = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	var actor = world.resident_runtimes[1]
	actor.data.fatigue = 40; actor.data.get_need(3).value = 50
	var before: Array = actor.decision.collect_actions(true)
	actor.data.add_trait(Trait.Type.PRUDENT)
	check(actor.decision.collect_actions(true) == before, "Real DecisionController utility and availability remain identical")
	actor.decision._choose_need(false)
	check(is_equal_approx(actor.decision.last_selection.candidate_ratio, 0.85) and actor.decision.last_selection.random_exponent == 2.5, "Real ordinary selection receives personal parameters")
	actor.intents.abort_current(actor.intents.current_intent)
	actor.commands.move_to(Vector2(300, 0))
	var rng_state: int = actor.decision.rng.state
	actor.data.fatigue = 100
	check(actor.intents.player_controlled and actor.intents.current_intent.reason_id == &"player_move" and actor.decision.rng.state == rng_state, "Player command bypass remains unchanged")
	world.free()
	world = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	actor = world.resident_runtimes[1]; actor.data.add_trait(Trait.Type.PRUDENT)
	rng_state = actor.decision.rng.state
	actor.data.fatigue = 100
	check(actor.intents.current_intent.reason_id == &"critical_sleep" and actor.intents.forced_priority == 100 and actor.decision.rng.state == rng_state, "Critical sleep bypasses selector and consumes no selector RNG")
	world.free()
