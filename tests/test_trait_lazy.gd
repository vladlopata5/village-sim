extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Balance = preload("res://scripts/balance_config.gd")
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
	for lazy in [false, true]:
		var data := Data.new("rate", "Rate", 25)
		if lazy: data.add_trait(Trait.LAZY)
		var dynamics := Dynamics.new(); dynamics._data = data
		var baseline_data := Data.new("base", "Base", 25)
		var baseline := Dynamics.new(); baseline._data = baseline_data
		data.current_sleep_quality = 0.5; baseline_data.current_sleep_quality = 0.5
		for activity in Dynamics.FATIGUE_RATES:
			data.activity = activity; baseline_data.activity = activity
			for need in 4:
				data.get_need(need).value = 60; baseline_data.get_need(need).value = 60
				dynamics._fractions[need] = 0; baseline._fractions[need] = 0
			for minute in 120:
				dynamics._on_minute_changed(minute); baseline._on_minute_changed(minute)
			check(data.fatigue == baseline_data.fatigue and dynamics._fractions[Need.FATIGUE] == baseline._fractions[Need.FATIGUE], "Every activity, including LAZY RESTING, preserves base fatigue/fractions")
			for other in [Need.HUNGER, Need.SOCIAL, Need.LEISURE]:
				check(data.get_need(other).value == baseline_data.get_need(other).value and dynamics._fractions[other] == baseline._fractions[other], "Other needs are unchanged for every activity")
		check(Modifiers.action_utility(data, Modifiers.Action.REST, 4000) == (6000 if lazy else 4000), "Only ordinary REST utility gets x1.5")
		check(Modifiers.action_utility(data, Modifiers.Action.WORK, 7000) == (6300 if lazy else 7000), "Existing WORK x0.9 is applied once")
		for action in [Modifiers.Action.EAT, Modifiers.Action.SOCIAL, Modifiers.Action.WANDER, Modifiers.Action.LEISURE]:
			check(Modifiers.action_utility(data, action, 1000) == 1000, "Unapproved action utilities remain unchanged")
		check(Modifiers.selector_candidate_ratio(data) == 0.75 and Modifiers.selector_random_exponent(data) == 2.0, "LAZY adds no random-selector changes")
		dynamics.free(); baseline.free()
		_live_rest(lazy)
		_critical_sleep(lazy)
	print("Lazy rest: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func fixture(lazy: bool) -> Node:
	var world: Node = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	for actor in world.resident_runtimes:
		actor.decision._deciding = true; actor.intents.abort_current(actor.intents.current_intent)
	var resident: Node = world.resident_runtimes[1]
	if lazy: resident.data.add_trait(Trait.LAZY)
	world.game_time.minute_changed.disconnect(resident.needs._on_minute_changed)
	world.game_time.minute_changed.connect(resident.need_dynamics._on_minute_changed)
	world.game_time.minute_changed.connect(resident.needs._on_minute_changed)
	return world
func _live_rest(lazy: bool) -> void:
	var world := fixture(lazy); var actor: Node = world.resident_runtimes[1]
	actor.wander.target_available = func(): return true
	actor.wander.target_provider = func(_rng): return {"position": Vector2(100, 0)}
	actor.data.fatigue = 40; actor.data.get_need(Need.SOCIAL).value = 40; actor.data.get_need(Need.LEISURE).value = 40
	var priorities: Dictionary = {}
	for action in actor.decision.collect_actions(true): priorities[action.id] = action.priority
	check(priorities.REST == (6000 if lazy else 4000) and priorities.WORK == (6300 if lazy else 7000), "Real candidates apply independent REST/WORK modifiers once")
	check(priorities.LEISURE == 3000 and priorities.SOCIAL == 3200 and priorities.WANDER == 500, "Entertainment, talking and walking get no LAZY bonus")
	actor.data.fatigue = 9
	check(not actor.decision.collect_actions(false).any(func(row): return row.id == "REST"), "Raw fatigue admission threshold is unchanged")
	actor.data.fatigue = 40; actor.need_dynamics._fractions[Need.FATIGUE] = 0
	var mood: int = actor.data.mood
	check(actor.needs.try_rest(int(priorities.REST)), "Existing normal rest starts")
	check(actor.data.activity == Activity.RESTING and actor.intents.current_intent.reason_id == &"rest" and actor.intents.current_intent.priority == priorities.REST and actor.intents.forced_priority == 0, "REST bonus never turns normal rest into sleep/forced action")
	world.game_time.advance(9)
	check(actor.data.activity == Activity.RESTING and actor.needs._minutes_left == 1, "Original ten-minute rest duration is preserved")
	world.game_time.advance(1)
	check(actor.data.fatigue == 39 and actor.need_dynamics._fractions[Need.FATIGUE] == -40, "Real ten-minute cycle preserves baseline recovery for both residents")
	check(actor.needs._active_intent == null and actor.intents.current_intent.reason_id != &"rest", "Rest completes through the original lifecycle")
	check(actor.data.mood == mood and actor.data.moodlets.size() == 0, "Rest creates no mood or moodlet effects")
	for skill in preload("res://scripts/skill_type.gd").Type.values(): check(actor.data.get_skill_xp(skill) == 0, "Rest adds no XP")
	world.free()
func _critical_sleep(lazy: bool) -> void:
	var world := fixture(lazy); var actor: Node = world.resident_runtimes[1]
	actor.decision._deciding = false
	actor.data.fatigue = 100
	check(actor.data.activity == Activity.SLEEPING and actor.intents.current_intent.reason_id == &"critical_sleep" and actor.intents.current_intent.priority == 0 and actor.intents.forced_priority == 100, "Critical fatigue keeps its original forced sleep path and priority")
	check(actor.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY, "Critical sleep quality is unchanged")
	world.game_time.advance(20)
	var raw: float = -30.0 * Balance.OUTDOOR_SLEEP_QUALITY * 20
	var points := int(raw / 60.0)
	check(actor.data.fatigue == 100 + points and is_equal_approx(actor.need_dynamics._fractions[Need.FATIGUE], raw - points * 60), "Actual critical sleep uses base recovery without LAZY multiplier")
	check(actor.data.activity == Activity.SLEEPING and actor.intents.forced_priority == 100, "Sleep does not end on the ordinary ten-minute REST timer")
	world.free()
