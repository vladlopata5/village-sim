extends SceneTree
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Balance = preload("res://scripts/balance_config.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func _run():
	var critical_recovery: float = -float(Dynamics.FATIGUE_RATES[Activity.Type.SLEEPING]) / Dynamics.UNITS_PER_POINT * Balance.OUTDOOR_SLEEP_QUALITY
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for r in scene.resident_runtimes:
		r.view.set_process(false)
		r.data.hunger = 0
		r.data.fatigue = 0
	scene.kitchen_data.resources.add(FOOD, 3)
	var residents = scene.resident_runtimes
	residents[0].data.hunger = 80
	residents[0].data.fatigue = 20
	residents[0].decision.request_decision()
	residents[1].data.hunger = 20
	residents[1].data.fatigue = 90
	residents[1].decision.request_decision()
	residents[2].data.hunger = 100
	residents[2].data.fatigue = 100
	scene.resident_selection.select(residents[3].data)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_5
	event.shift_pressed = true
	event.pressed = true
	scene._unhandled_key_input(event)
	check(residents[0].intents.current_intent.reason_id == &"eat" and residents[1].data.activity == Activity.Type.RESTING and residents[2].intents.forced_priority == 200 and residents[3].intents.forced_priority == 100, "Four independent choices: ordinary food/rest, critical food/sleep")
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 2 and scene.kitchen_data.resources.get_available_amount(FOOD) == 1, "Two selected meal methods reserve distinct available units")
	var saved = residents[2].intents.current_intent
	residents[2].data.fatigue = 99
	residents[2].data.fatigue = 100
	check(residents[2].intents.current_intent == saved and residents[3].data.activity == Activity.Type.SLEEPING, "Each critical hierarchy belongs to its own resident")
	residents[0].view._process(20)
	residents[2].view._process(20)
	check(scene.kitchen_data.resources.get_amount(FOOD) == 1 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Exactly two promised FOOD consumed on arrival")
	scene.game_time.debug_skip_minutes(10)
	check(residents[0].data.hunger == 60 and residents[2].data.hunger == 80 and residents[3].data.fatigue == 100 - int(10 * critical_recovery), "Game time evolves each action independently")
	scene.resident_selection.select(residents[1].data)
	scene.get_node("HUD/ResidentCard")._refresh()
	check(scene.get_node("HUD/ResidentCard").activity_label.text == "Занятие: Отдыхает", "Card displays resident's RESTING activity")
	check(residents[1].data.fatigue < 90 and residents[1].data.fatigue > 85, "Rest is slower than sleeping")
	scene.game_time.debug_skip_minutes(20)
	check(residents[2].data.activity == Activity.Type.SLEEPING and residents[2].intents.forced_priority == 100, "Critical food finishes before deferred exhaustion")
	check(scene.residents[0].inventory != scene.residents[1].inventory and residents[0].data.get_need(Type.HUNGER) != residents[1].data.get_need(Type.HUNGER), "No shared mutable need/inventory data")
	scene.free()
	# Same container pool protects both meal and other outgoing reservations.
	scene = preload("res://tests/need_test_setup.gd").make_scene(self, 360, 2)
	var r = scene.resident_runtimes[0]
	check(scene.kitchen_data.resources.reserve_out(FOOD, 1), "Simulate another transport promise from this container")
	r.data.hunger = 80
	r.decision.request_decision()
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 2 and not scene.kitchen_data.resources.reserve_out(FOOD, 1), "One pool: meal cannot double-promise outgoing cargo")
	r.intents.force_set_intent(Intent.new())
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 1, "Cancelling own meal leaves another system's outgoing reserve")
	scene.free()
	print("Need population checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
