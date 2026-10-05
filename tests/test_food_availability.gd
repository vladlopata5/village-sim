extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Priority = preload("res://scripts/logistics_priority.gd")
var failures := 0
var messages: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var scene = Setup.make_scene(self)
	var resident = scene.resident_runtimes[1]
	scene.game_logger.line_logged.connect(func(line: String, _level: int): messages.append(line))
	resident.data.hunger = 80
	resident.decision.request_decision()
	check(resident.needs.food_search_count == 1 and resident.data.activity == Activity.IDLE, "First unavailable FOOD request fails and returns to other options")
	scene.game_time.debug_skip_minutes(180)
	check(resident.needs.food_search_count == 1, "180 minutes without a world event: exactly one actual food search")
	var failures_logged := 0
	for message in messages:
		if message.contains("Анна не удалось поесть"): failures_logged += 1
	check(failures_logged == 1, "No repeated INFO failure, without logger filtering")
	var count: int = resident.decision.decision_count
	scene.kitchen_data.resources.add(FOOD, 1)
	check(resident.intents.current_intent.reason_id == &"eat" and resident.decision.decision_count > count and resident.needs.food_search_count == 2, "New FOOD event immediately wakes a hungry idle resident")
	print("Availability proof: 180 game minutes, searches=1, failure INFO=1; FOOD arrived -> searches=2 and eat intent")
	scene.free()
	# Critical hunger previously failed; arrival of food must still respect an existing ordinary action.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[3]
	resident.data.hunger = 100
	resident.data.get_need(Type.LEISURE).value = 100
	resident.decision.request_decision()
	check(resident.data.activity == Activity.RELAXING, "Unavailable critical food allows another concrete action")
	var current = resident.intents.current_intent
	count = resident.needs.food_search_count
	scene.kitchen_data.resources.add(FOOD, 1)
	check(resident.intents.current_intent == current and resident.data.activity == Activity.RELAXING and resident.needs.food_search_count == count, "World availability is not a forced interrupt, even with hunger 100")
	scene.game_time.debug_skip_minutes(30)
	check(resident.intents.current_intent.reason_id == &"eat" and resident.needs.food_search_count == count + 1, "New option considered when ordinary action finishes")
	scene.free()
	# The same event must not interrupt TALKING, even after a failed critical search.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[3]
	resident.data.hunger = 100
	var partner = scene.resident_runtimes[1]
	scene.social_world.arrive(resident.data.id, {"target_id": partner.data.id, "group_id": 0})
	current = resident.intents.current_intent
	count = resident.needs.food_search_count
	scene.game_time.debug_skip_minutes(5)
	scene.kitchen_data.resources.add(FOOD, 1)
	check(resident.intents.current_intent == current and resident.data.activity == Activity.TALKING and resident.needs.food_search_count == count, "FOOD event does not end an existing conversation")
	scene.game_time.debug_skip_minutes(10)
	check(resident.intents.current_intent.reason_id == &"eat", "Conversation's own recheck can end it for now-available hunger")
	scene.free()
	# Reservation release is also a real increase in available portions.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	scene.kitchen_data.resources.reserve_out(FOOD, 1)
	resident.data.hunger = 80
	resident.decision.request_decision()
	check(resident.needs.food_search_count == 1 and not resident.intents.has_current_action(), "Promised FOOD is unavailable")
	scene.kitchen_data.resources.release_out(FOOD, 1)
	check(resident.intents.current_intent.reason_id == &"eat" and resident.needs.food_search_count == 2, "Freed reservation wakes idle hungry resident")
	scene.free()
	# Formula depends on real capacity, not kitchen-specific stock steps.
	scene = Setup.make_scene(self)
	var container = scene.kitchen_data.resources
	check(container.get_capacity(FOOD) == 20 and is_equal_approx(Priority.import_priority(container, FOOD), 11000), "Empty capacity-20 kitchen urgency")
	container.add(FOOD, 4)
	check(is_equal_approx(Priority.import_priority(container, FOOD), 8800), "4/20 uses projected fill 20 percent")
	container.reserve_in(FOOD, 1)
	check(is_equal_approx(Priority.import_priority(container, FOOD), 8250), "Incoming promise uses 5/20 projected fill")
	scene.free()
	print("Event-driven FOOD checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
