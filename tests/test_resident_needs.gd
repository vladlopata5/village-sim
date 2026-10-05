extends SceneTree
const Seed = preload("res://tests/utility_test_seed.gd")
const Setup = preload("res://tests/need_test_setup.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func _run():
	for speed in [1, 2, 4, 10, 20]:
		var speed_scene = Setup.make_scene(self, 420)
		var speed_resident = speed_scene.resident_runtimes[0]
		var clock = speed_scene.game_time
		clock.set_speed(speed)
		speed_resident.data.hunger = 80
		speed_resident.decision.rng.seed = Seed.for_action(speed_resident.decision.collect_actions(true), "EAT")
		speed_resident.decision.request_decision()
		check(speed_resident.intents.current_intent.reason_id == &"eat" and speed_scene.kitchen_data.resources.get_reserved_out(FOOD) == 1, "Concrete action reserves before movement")
		clock.advance(15.0 / speed)
		check(speed_resident.data.hunger == 81, "Hunger still grows during route")
		speed_resident.view._process(20)
		check(speed_resident.data.activity == Activity.Type.EATING and not speed_resident.intents.current_intent.interruptible and speed_scene.kitchen_data.resources.get_amount(FOOD) == 1 and speed_scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Arrival consumes exactly promised food and retains meal")
		paused = true
		clock.advance(1000)
		check(speed_resident.data.hunger == 81 and speed_resident.data.activity == Activity.Type.EATING, "Pause freezes meal")
		paused = false
		clock.advance(10.0 / speed)
		check(speed_resident.data.hunger == 61 and speed_resident.data.activity == Activity.Type.EATING, "First ten minutes reduce hunger gradually")
		clock.advance(19.0 / speed)
		check(speed_resident.data.hunger == 23 and speed_resident.data.activity == Activity.Type.EATING, "Meal lasts thirty game minutes on each speed")
		clock.advance(1.0 / speed)
		check(speed_resident.data.hunger == 21 and speed_resident.intents.current_intent.reason_id == &"day_work", "End has no additional hunger jump and returns to work")
		speed_resident.view._process(20)
		check(speed_resident.data.activity == Activity.Type.WORKING, "Work after meal")
		speed_scene.free()
	# Ordinary night still waits for the paid meal; the route is interruptible.
	var scene = Setup.make_scene(self, 1370)
	var r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	r.view._process(20)
	scene.game_time.debug_skip_minutes(10)
	check(r.data.activity == Activity.Type.EATING and r.intents.pending_intent.reason_id == &"night_home", "Night queues behind ordinary meal")
	scene.game_time.debug_skip_minutes(20)
	check(r.data.hunger == 20 and r.intents.current_intent.reason_id == &"night_home", "Meal completes then pending home starts")
	r.view._process(20)
	check(r.data.activity == Activity.Type.SLEEPING, "Night meal goes home and sleeps")
	scene.free()
	scene = Setup.make_scene(self, 1370)
	r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	scene.game_time.debug_skip_minutes(10)
	check(r.intents.current_intent.reason_id == &"night_home" and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Night interrupts unpaid route and releases meal reservation")
	scene.free()
	print("Need action checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
