extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Need = preload("res://scripts/need_type.gd").Type
const Trait = preload("res://scripts/trait_type.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func run() -> void:
	for foolish in [false, true]:
		var data := Data.new("rates", "Rates", 25)
		if foolish: data.add_trait(Trait.FOOLISH)
		var dynamics := Dynamics.new(); dynamics._data = data
		var baseline_data := Data.new("base", "Base", 25)
		var baseline := Dynamics.new(); baseline._data = baseline_data
		for activity in Dynamics.LEISURE_RATES:
			data.activity = activity; baseline_data.activity = activity
			for need in 4:
				data.get_need(need).value = 90; baseline_data.get_need(need).value = 90
				dynamics._fractions[need] = 0; baseline._fractions[need] = 0
			for minute in 20:
				dynamics._on_minute_changed(minute); baseline._on_minute_changed(minute)
			var rate: float = Dynamics.LEISURE_RATES[activity]
			if foolish and rate < 0:
				check(data.get_need(Need.LEISURE).value == (0 if activity == Activity.RELAXING else 75), "All negative LEISURE rates use exactly x1.5")
			else:
				check(data.get_need(Need.LEISURE).value == baseline_data.get_need(Need.LEISURE).value and dynamics._fractions[Need.LEISURE] == baseline._fractions[Need.LEISURE], "Growth and neutral residents retain exact values and fractions")
			for other in [Need.HUNGER, Need.FATIGUE, Need.SOCIAL]:
				check(data.get_need(other).value == baseline_data.get_need(other).value and dynamics._fractions[other] == baseline._fractions[other], "Other needs are unchanged for every activity")
		for activity in [Activity.RELAXING, Activity.TALKING]:
			data.activity = activity
			for need in 4: data.get_need(need).value = 90; dynamics._fractions[need] = 0
			for minute in 4: dynamics._on_minute_changed(minute)
			var expected_recovery: int = (18 if foolish else 12) if activity == Activity.RELAXING else (3 if foolish else 2)
			check(data.get_need(Need.LEISURE).value == 90 - expected_recovery and dynamics._fractions[Need.LEISURE] == 0, "Exact four-minute recovery without clamping or doubled multiplier")
			if activity == Activity.TALKING: check(data.get_need(Need.SOCIAL).value == 78, "Conversation still restores SOCIAL at its base rate")
		check(Modifiers.action_utility(data, Modifiers.Action.LEISURE, 3000) == (4500 if foolish else 3000), "Only entertainment utility gets x1.5")
		for action in [Modifiers.Action.WORK, Modifiers.Action.EAT, Modifiers.Action.SOCIAL, Modifiers.Action.WANDER]:
			check(Modifiers.action_utility(data, action, 1000) == 1000, "Unapproved action utility remains unchanged")
		check(is_equal_approx(Modifiers.selector_candidate_ratio(data), 0.55 if foolish else 0.75), "Existing random candidate ratio is preserved")
		check(is_equal_approx(Modifiers.selector_random_exponent(data), 1.5 if foolish else 2.0), "Existing random exponent is preserved")
		check(Modifiers.leisure_need_rate(data, 12, true) == 12 and Modifiers.leisure_need_rate(data, 0, true) == 0, "FOOLISH never increases growth or zero rate")
		dynamics.free(); baseline.free()
		_live_leisure(foolish)
	var combined := Data.new("combined", "Combined", 25)
	combined.add_trait(Trait.RESTLESS); combined.add_trait(Trait.FOOLISH)
	check(Modifiers.leisure_need_rate(combined, 12, true) == 48 and Modifiers.leisure_need_rate(combined, 12, false) == 12, "RESTLESS idle growth composes without a FOOLISH growth bonus")
	check(Modifiers.leisure_need_rate(combined, -180, true) == -270 and Modifiers.leisure_need_rate(combined, -30, false) == -45, "Recovery never receives RESTLESS or a second FOOLISH multiplier")
	check(Modifiers.action_utility(combined, Modifiers.Action.WANDER, 500) == 750 and Modifiers.movement_speed(combined, 120) == 132, "Previous RESTLESS effects stay independent")
	print("Foolish leisure: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _live_leisure(foolish: bool) -> void:
	var world: Node = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	for resident in world.resident_runtimes:
		resident.decision._deciding = true; resident.intents.abort_current(resident.intents.current_intent)
	var actor: Node = world.resident_runtimes[1]
	if foolish: actor.data.add_trait(Trait.FOOLISH)
	actor.wander.target_available = func(): return true
	actor.wander.target_provider = func(_rng): return {"position": Vector2(100, 0)}
	actor.data.fatigue = 40; actor.data.get_need(Need.SOCIAL).value = 40; actor.data.get_need(Need.LEISURE).value = 40
	var actions: Array = actor.decision.collect_actions(true)
	var priorities: Dictionary = {}
	for action in actions: priorities[action.id] = action.priority
	check(priorities.LEISURE == (4500 if foolish else 3000), "Actual DecisionController applies entertainment multiplier exactly once")
	check(priorities.REST == 4000 and priorities.SOCIAL == 3200 and priorities.WANDER == 500 and priorities.WORK == 7000, "Actual fatigue rest, social, walk and work priorities stay unchanged")
	actor.data.get_need(Need.LEISURE).value = 10
	check(not actor.decision.collect_actions(false).any(func(row): return row.id == "LEISURE"), "Existing raw need admission threshold is unchanged")
	actor.data.get_need(Need.LEISURE).value = 60
	world.game_time.minute_changed.disconnect(actor.social._on_minute)
	world.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	world.game_time.minute_changed.connect(actor.social._on_minute)
	var mood: int = actor.data.mood
	check(actor.social.try_leisure(int(priorities.LEISURE)), "Existing RELAXING action starts")
	check(actor.intents.current_intent.priority == priorities.LEISURE, "Executor retains the already calculated priority")
	world.game_time.advance(4)
	check(actor.data.get_need(Need.LEISURE).value == (42 if foolish else 48), "Real clock uses base 3 or enhanced 4.5 points per minute")
	world.game_time.advance(16)
	check(actor.data.get_need(Need.LEISURE).value == 0 and actor.data.activity == Activity.RELAXING, "Zero leisure does not introduce early completion")
	world.game_time.advance(9)
	check(actor.data.activity == Activity.RELAXING, "Original thirty-minute duration is retained")
	world.game_time.advance(1)
	check(actor.intents.current_intent.reason_id != &"leisure", "Ordinary completion still occurs at thirty minutes")
	check(actor.data.mood == mood, "No mood effect is added")
	for skill in preload("res://scripts/skill_type.gd").Type.values(): check(actor.data.get_skill_xp(skill) == 0, "Entertainment grants no skill XP")
	world.free()
