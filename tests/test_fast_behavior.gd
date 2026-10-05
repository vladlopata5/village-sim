extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func exit_seed() -> int:
	var random := RandomNumberGenerator.new()
	for candidate in range(100):
		random.seed = candidate
		if random.randf() < 0.2: return candidate
	return -1
func _run() -> void:
	var scene = Setup.make_scene(self)
	var resident = scene.resident_runtimes[0]
	scene.kitchen_data.resources.add(FOOD, 1)
	resident.data.hunger = 29
	check(not resident.needs.can_try_eat() and not resident.needs.has_food_action(), "HUNGER 29: EAT unavailable")
	resident.decision.request_decision()
	scene.game_time.debug_skip_minutes(20)
	check(resident.needs.food_search_count == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 1, "Idle resident never snacks below minimum")
	resident.data.hunger = 30
	check(resident.needs.can_try_eat() and resident.needs.has_food_action(), "HUNGER 30: EAT available")
	resident.decision.request_decision()
	check(resident.intents.current_intent.reason_id == &"eat", "Minimum hunger starts normal reserved meal")
	scene.free()
	for speed in [10, 20]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		scene.game_time.set_speed(speed)
		resident.data.get_need(Type.LEISURE).value = 100
		resident.decision.request_decision()
		resident.data.get_need(Type.LEISURE).value = 0
		paused = true
		scene.game_time.advance(1000)
		check(resident.data.activity == Activity.RELAXING and scene.game_time.total_minutes == 360, "Pause freezes committed relaxation")
		paused = false
		scene.game_time.advance(29.0 / speed)
		check(resident.data.activity == Activity.RELAXING, "Low leisure cannot end action before 30 minutes")
		scene.game_time.advance(2.0 / speed)
		check(resident.data.activity == Activity.IDLE, "Crossing minute 30 completes relaxation at fast speed")
		resident.data.get_need(Type.LEISURE).value = 100
		resident.decision.request_decision()
		resident.data.fatigue = 100
		check(resident.data.activity == Activity.SLEEPING, "Critical fatigue interrupts committed relaxation")
		scene.free()
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		scene.game_time.set_speed(speed)
		for runtime in scene.resident_runtimes:
			runtime.data.get_need(Type.SOCIAL).value = 100
			runtime.social.rng.seed = exit_seed()
		check(scene.social_world.arrive(resident.data.id, {"target_id": scene.resident_runtimes[1].data.id, "group_id": 0}), "Conversation starts")
		scene.game_time.advance(16.0 / speed)
		check(resident.data.activity == Activity.TALKING, "High SOCIAL blocks RNG-only exit after minimum")
		resident.data.get_need(Type.SOCIAL).value = 0
		resident.social.rng.seed = exit_seed()
		scene.game_time.advance(5.0 / speed)
		check(resident.data.activity != Activity.TALKING, "Satisfied SOCIAL permits seeded voluntary exit at crossed recheck")
		scene.free()
		var clock = preload("res://scripts/game_time.gd").new()
		root.add_child(clock)
		clock.set_process(false)
		clock.set_speed(speed)
		var phases: Array[String] = []
		clock.phase_changed.connect(func(phase: String): phases.append(phase))
		clock.advance(1500.0 / speed)
		check(clock.total_minutes == 1860 and phases == ["День", "Вечер", "Ночь", "Утро", "День"], "Large fast step emits every crossed phase")
		clock.free()
		print("Fast behavior x%d: relaxation, pause, forced interrupt, conversation rechecks, phase boundaries" % speed)
	print("Fast behavior checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
