extends SceneTree
const Setup = preload("res://tests/need_test_setup.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func _run():
	var scene = Setup.make_scene(self)
	var r = scene.resident_runtimes[0]
	r.data.hunger = 9
	r.data.fatigue = 9
	r.decision.request_decision()
	check(not r.intents.has_current_action(), "Both priorities below 1000 leave idle")
	var count: int = r.decision.decision_count
	for frame in range(120): r.view._process(0.01)
	scene.game_time.debug_skip_minutes(9)
	check(r.decision.decision_count == count, "No per-frame or per-minute ordinary decision")
	scene.game_time.debug_skip_minutes(1)
	check(r.decision.decision_count == count + 1, "Idle segment completes at ten game minutes")
	r.data.hunger = 10
	r.data.fatigue = 0
	r.decision.request_decision()
	check(r.intents.current_intent.reason_id == &"eat" and scene.kitchen_data.resources.get_reserved_out(FOOD) == 1, "1000 threshold selects concrete food action and reserves before path")
	var current = r.intents.current_intent
	r.data.fatigue = 99
	check(r.intents.current_intent == current, "Higher ordinary fatigue never interrupts started food route")
	scene.get_node("World/CommunalKitchen").free()
	scene.game_time.debug_skip_minutes(1)
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 0 and r.data.activity == Activity.Type.RESTING, "Impossible food route releases its reservation and chooses again")
	scene.free()
	# Work preference is 7000, separate from current-action execution priority.
	scene = Setup.make_scene(self, 420)
	r = scene.resident_runtimes[0]
	r.data.hunger = 60
	r.data.fatigue = 65
	r.decision.request_decision()
	check(r.intents.current_intent.reason_id == &"day_work", "Work wins over needs below 7000")
	current = r.intents.current_intent
	r.data.hunger = 80
	r.data.fatigue = 90
	check(r.intents.current_intent == current and r.data.activity == Activity.Type.MOVING, "Ordinary changes leave started work route untouched")
	r.view._process(20)
	check(r.data.activity == Activity.Type.WORKING, "Work route arrival starts work segment")
	scene.game_time.debug_skip_minutes(60)
	check(r.data.activity == Activity.Type.RESTING, "Next action boundary compares needs: fatigue 9000 wins hunger 8000 and work 7000")
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Unchosen hunger does not reserve food")
	r.data.hunger = 99
	current = r.intents.current_intent
	check(r.intents.current_intent == current, "A new ordinary winner waits for rest completion")
	scene.game_time.debug_skip_minutes(10)
	check(r.intents.current_intent.reason_id == &"eat", "Rest completion produces next decision")
	scene.free()
	# At exactly 7000, the deterministic tie goes to work.
	scene = Setup.make_scene(self, 420)
	r = scene.resident_runtimes[0]
	r.data.hunger = 70
	r.decision.request_decision()
	check(r.intents.current_intent.reason_id == &"day_work" and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Work wins tie at 7000 without reserving unchosen food")
	scene.free()
	# No work task: consider even a need below work priority.
	scene = Setup.make_scene(self, 420)
	r = scene.resident_runtimes[0]
	r.decision.work_available = func(): return false
	r.data.hunger = 20
	r.decision.request_decision()
	check(r.intents.current_intent.reason_id == &"eat", "No real work permits a need at 2000")
	scene.free()
	# Critical levels remain separate from ordinary need weights/priorities.
	scene = Setup.make_scene(self)
	r = scene.resident_runtimes[0]
	r.intents.submit(Intent.new(Intent.Type.MOVE_TO, &"locked", Vector2(500, 0), 50000, false))
	r.data.hunger = 100
	current = r.intents.current_intent
	check(current.reason_id == &"eat" and r.intents.forced_priority == 200, "Critical hunger interrupts a locked ordinary action")
	r.data.fatigue = 100
	check(r.intents.current_intent == current, "Critical fatigue cannot interrupt higher critical hunger")
	r.view._process(20)
	check(r.data.activity == Activity.Type.EATING, "Critical food arrival eats")
	scene.game_time.debug_skip_minutes(15)
	check(r.data.hunger == 70 and r.data.activity == Activity.Type.EATING and r.intents.forced_priority == 200, "Critical protection lasts through meal even after hunger falls")
	scene.game_time.debug_skip_minutes(15)
	check(r.data.activity == Activity.Type.SLEEPING and r.intents.forced_priority == 100 and not r.view.has_movement_target, "After higher critical action completes exhaustion sleeps in place")
	var position: Vector2 = r.view.position
	scene.game_time.debug_skip_minutes(60)
	check(r.data.fatigue == 70 and r.view.position == position, "Critical sleep recovers fatigue without movement")
	scene.free()
	# Fatigue alone can interrupt ordinary eating (already consumed food is not refunded).
	scene = Setup.make_scene(self)
	r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	r.view._process(20)
	r.data.fatigue = 100
	check(r.data.activity == Activity.Type.SLEEPING and r.intents.current_intent.reason_id == &"critical_sleep", "Exhaustion interrupts noncritical locked eating")
	check(scene.kitchen_data.resources.get_amount(FOOD) == 1 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Already consumed food is not created again")
	scene.game_time.debug_skip_minutes(160)
	check(r.data.fatigue <= 20 and r.intents.forced_priority == 0, "Recovery ends critical sleep and unlocks ordinary choices")
	scene.free()
	# A future higher emergency is not overridden; exhaustion is handled on completion.
	scene = Setup.make_scene(self)
	r = scene.resident_runtimes[0]
	var danger = Intent.new(Intent.Type.MOVE_TO, &"test_danger", Vector2(500, 0), 0, false)
	r.intents.force_set_intent(danger, 300)
	r.data.fatigue = 100
	check(r.intents.current_intent == danger, "Higher critical level remains protected")
	r.intents.clear_completed(danger)
	check(r.data.activity == Activity.Type.SLEEPING, "Critical exhaustion considered after higher action completes")
	scene.free()
	# A synchronous critical event while FOOD is consumed must not be lost/overwritten.
	scene = Setup.make_scene(self)
	r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	var test_resident = r.data
	scene.kitchen_data.resources.changed.connect(func(_resource, _amount): test_resident.fatigue = 100)
	r.view._process(20)
	check(r.data.activity == Activity.Type.SLEEPING and r.intents.forced_priority == 100, "Critical event during consumption remains current")
	check(scene.kitchen_data.resources.get_amount(FOOD) == 1, "Synchronous event consumes one food only")
	scene.free()
	print("Decision checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
