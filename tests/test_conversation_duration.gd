extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func seed_for(continue_count: int, exiting: bool = false) -> int:
	var random = RandomNumberGenerator.new()
	for candidate in range(10000):
		random.seed = candidate
		var valid := true
		for draw in range(continue_count):
			if (random.randf() < 0.2) != exiting: valid = false
		if valid: return candidate
	return -1
func group(scene: Node, size: int = 2) -> Array:
	var residents: Array = scene.resident_runtimes
	# Start a real group, bypassing only the arbitrary approach distance.
	var option: Dictionary = {"target_id": residents[1].data.id, "group_id": 0}
	check(scene.social_world.arrive(residents[0].data.id, option), "Two idle residents start a group")
	for index in range(2, size):
		option = {"target_id": residents[1].data.id, "group_id": scene.social_world.group_of(residents[1].data.id).id}
		check(scene.social_world.arrive(residents[index].data.id, option), "Further participant joins group")
	for resident in residents:
		resident.social.rng.seed = seed_for(9)
		resident.decision._next_decision_at = scene.game_time.total_minutes + 1000
	return residents
func _run() -> void:
	var scene = Setup.make_scene(self)
	var residents = group(scene)
	scene.game_time.debug_skip_minutes(14)
	check(residents[0].data.activity == Activity.TALKING and residents[0].data.get_need(Type.SOCIAL).value == 0, "SOCIAL zero does not end a conversation before minimum")
	scene.game_time.debug_skip_minutes(1)
	check(residents[0].data.activity == Activity.TALKING, "Without more important actions conversation continues after 15 minutes")
	var random_a = RandomNumberGenerator.new()
	var random_b = RandomNumberGenerator.new()
	random_a.seed = seed_for(9)
	random_b.seed = random_a.seed
	for draw in range(9): check(random_a.randf() == random_b.randf(), "Exit RNG is reproducible")
	scene.game_time.debug_skip_minutes(44)
	check(residents[0].data.activity == Activity.TALKING, "Deterministic continuing participant may talk until minute 59")
	scene.game_time.debug_skip_minutes(1)
	await process_frame
	check(scene.social_world.groups.is_empty() and residents[0].data.activity != Activity.TALKING, "Maximum 60 minutes guarantees exit")
	scene.free()
	scene = Setup.make_scene(self)
	residents = group(scene, 3)
	residents[0].social.rng.seed = seed_for(1, true)
	scene.game_time.debug_skip_minutes(14)
	check(scene.social_world.groups.values()[0].participants.size() == 3, "Even a voluntary exit cannot happen before 15 minutes")
	scene.game_time.debug_skip_minutes(1)
	check(scene.social_world.groups.values()[0].participants.size() == 2 and residents[1].data.activity == Activity.TALKING, "Seeded voluntary exit is independent; two others continue")
	residents[1].data.fatigue = 100
	await process_frame
	check(scene.social_world.groups.is_empty() and residents[2].data.activity != Activity.TALKING, "Forced departure dissolves singleton and redecides for remaining participant")
	scene.free()
	scene = Setup.make_scene(self)
	residents = group(scene, 3)
	scene.game_time.debug_skip_minutes(5)
	residents[0].data.fatigue = 100
	check(residents[0].data.activity == Activity.SLEEPING and scene.social_world.groups.values()[0].participants.size() == 2, "Critical interrupt can leave before minimum duration")
	residents[1].data.get_need(Type.LEISURE).value = 100
	scene.game_time.debug_skip_minutes(9)
	check(residents[1].data.activity == Activity.TALKING, "Ordinary higher leisure still waits for minimum")
	scene.game_time.debug_skip_minutes(1)
	check(residents[1].data.activity == Activity.RELAXING, "At recheck a more important available action wins")
	scene.free()
	scene = Setup.make_scene(self)
	residents = group(scene, 3)
	scene.kitchen_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 1)
	scene.game_time.debug_skip_minutes(5)
	residents[0].data.hunger = 100
	check(residents[0].intents.current_intent.reason_id == &"eat" and scene.social_world.groups.values()[0].participants.size() == 2, "Critical hunger also interrupts before 15 minutes")
	scene.free()
	print("Conversation duration checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
