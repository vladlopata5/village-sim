extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Intents = preload("res://scripts/resident_intent_controller.gd")
const Intent = preload("res://scripts/resident_intent.gd")
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
	for restless in [false, true]:
		var data := Data.new("rate", "Rate", 25)
		if restless: data.add_trait(Trait.RESTLESS)
		var intents := Intents.new(); intents.setup(data)
		var dynamics := Dynamics.new(); dynamics._data = data
		dynamics.ordinary_idle_provider = intents.is_ordinary_idle
		var baseline_data := Data.new("base", "Base", 25)
		var baseline := Dynamics.new(); baseline._data = baseline_data
		for activity in Dynamics.LEISURE_RATES:
			data.activity = activity; baseline_data.activity = activity
			for need in 4:
				data.get_need(need).value = 50; baseline_data.get_need(need).value = 50
				dynamics._fractions[need] = 0; baseline._fractions[need] = 0
			for minute in 100:
				dynamics._on_minute_changed(minute); baseline._on_minute_changed(minute)
			if restless and activity == Activity.IDLE:
				check(data.get_need(Need.LEISURE).value == 66 and dynamics._fractions[Need.LEISURE] == 0, "Exactly x4 ordinary idle growth, not x16")
			else:
				check(data.get_need(Need.LEISURE).value == baseline_data.get_need(Need.LEISURE).value and dynamics._fractions[Need.LEISURE] == baseline._fractions[Need.LEISURE], "Every other activity, sleep and recovery retains the exact base rate")
			for other in [Need.HUNGER, Need.FATIGUE, Need.SOCIAL]:
				check(data.get_need(other).value == baseline_data.get_need(other).value and dynamics._fractions[other] == baseline._fractions[other], "Other needs and fractional progress are unchanged")
		check(Modifiers.leisure_need_rate(data, -180, true) == -180 and Modifiers.leisure_need_rate(data, 0, true) == 0, "Even an idle flag cannot accelerate recovery or zero rate")
		check(Modifiers.action_utility(data, Modifiers.Action.WANDER, 500) == (750 if restless else 500), "Pure WANDER utility")
		check(is_equal_approx(Modifiers.movement_speed(data, 120), 132 if restless else 120), "Previous movement multiplier remains exactly x1.1")
		for action in [Modifiers.Action.WORK, Modifiers.Action.EAT, Modifiers.Action.SOCIAL]:
			check(Modifiers.action_utility(data, action, 1000) == 1000, "RESTLESS leaves other action utility unchanged")
		for reason in [&"builder_wait_materials", &"social", &"wander", &"other_stationary_task"]:
			intents.current_intent = Intent.new(Intent.Type.NONE, reason)
			data.activity = Activity.IDLE; data.get_need(Need.LEISURE).value = 50; dynamics._fractions[Need.LEISURE] = 0
			check(not intents.is_ordinary_idle(), "Stationary task ownership excludes idle boredom")
			for minute in 100: dynamics._on_minute_changed(minute)
			check(data.get_need(Need.LEISURE).value == 54, "Task waiting keeps baseline leisure growth")
		intents.current_intent = Intent.new(); data.activity = Activity.IDLE
		for control in ["forced", "player"]:
			intents.forced_priority = 100 if control == "forced" else 0
			intents.player_controlled = control == "player"
			data.get_need(Need.LEISURE).value = 50; dynamics._fractions[Need.LEISURE] = 0
			check(not intents.is_ordinary_idle(), "Forced/player stop is not ordinary idle")
			for minute in 100: dynamics._on_minute_changed(minute)
			check(data.get_need(Need.LEISURE).value == 54, "Forced/player stop keeps baseline leisure growth")
		intents.forced_priority = 0; intents.player_controlled = false
		check(intents.is_ordinary_idle(), "No accepted task/control is ordinary idle")
		dynamics.free(); baseline.free(); intents.free()
		_walk_case(restless)
	print("Restless traits: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _walk_case(restless: bool) -> void:
	var world: Node = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	var actor: Node = world.resident_runtimes[1]
	actor.decision._deciding = true; actor.intents.abort_current(actor.intents.current_intent)
	if restless: actor.data.add_trait(Trait.RESTLESS)
	actor.wander.target_available = func(): return true
	actor.wander.target_provider = func(_rng): return {"position": actor.view.global_position + Vector2(1000, 0)}
	var actions: Array = actor.decision.collect_actions(false)
	var priority := -1.0
	for action in actions:
		if action.id == "WANDER": priority = action.priority
	check(priority == (750 if restless else 500), "Real DecisionController applies WANDER multiplier once")
	check(actor.wander.try_wander(int(priority)), "Existing walk starts")
	var origin: Vector2 = actor.view.global_position
	actor.view._process(1)
	check(is_equal_approx(actor.view.global_position.distance_to(origin), 132 if restless else 120), "Actual walking keeps existing speed bonus")
	actor.view._process(100)
	check(actor.data.activity == Activity.IDLE and actor.intents.current_intent.reason_id == &"wander" and actor.intents.current_intent.priority == priority, "Real arrival retains walk/stay and its already-resolved priority")
	check(not actor.need_dynamics.ordinary_idle_provider.call(), "Runtime binds ordinary-idle context and excludes walk stay")
	actor.data.get_need(Need.LEISURE).value = 50; actor.need_dynamics._fractions[Need.LEISURE] = 0
	for minute in 100: actor.need_dynamics._on_minute_changed(minute)
	check(actor.data.get_need(Need.LEISURE).value == 54, "Actual walk stay uses baseline leisure growth")
	actor.intents.abort_current(actor.intents.current_intent)
	check(actor.need_dynamics.ordinary_idle_provider.call(), "Completed/cancelled ownership exposes ordinary idle immediately")
	actor.data.get_need(Need.LEISURE).value = 50; actor.need_dynamics._fractions[Need.LEISURE] = 0
	for minute in 100: actor.need_dynamics._on_minute_changed(minute)
	check(actor.data.get_need(Need.LEISURE).value == (66 if restless else 54), "Runtime ordinary idle receives the intended rate")
	world.free()
