extends SceneTree
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func make_scene() -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.resident_view.set_process(false)
	return scene
func key(code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
func _run() -> void:
	for speed in [1, 2, 4]:
		var scene = make_scene()
		var data = scene.resident_data
		var view = scene.resident_view
		var clock = scene.game_time
		var intents = scene.resident_intents
		var needs = scene.get_node("ResidentNeedsController")
		clock.set_speed(speed)
		key(KEY_F10)
		check(data.hunger == 20, "F10 without selection does nothing")
		scene.resident_selection.select(data)
		key(KEY_F8)
		view._process(20.0)
		check(data.activity == Activity.Type.WORKING, "Initial day work")
		# Reach 11:00 with low hunger, then trigger the actual debug command.
		clock.debug_skip_minutes(240)
		paused = true
		var before: Vector2 = view.global_position
		key(KEY_F10)
		check(data.hunger == 75 and intents.current_intent.reason_id == &"eat" and intents.current_intent.priority == 75, "F10 sets 75 and food outranks work")
		var eat = intents.current_intent
		for _repeat in range(10):
			needs.evaluate()
		check(intents.current_intent == eat, "Repeated evaluations do not recreate food intent")
		check(view.target_position == scene.world_locations.get_position(scene.kitchen_data.id), "Food position resolved through existing world mapping")
		view._process(1.0)
		check(view.global_position == before, "Paused food route does not move")
		paused = false
		view._process(20.0)
		check(data.activity == Activity.Type.EATING and intents.current_intent.type == Intent.Type.NONE and not view.has_movement_target, "Kitchen arrival starts EATING after intent completion")
		var card = scene.get_node("HUD/ResidentCard")
		card._refresh()
		check(card.activity_label.text == "Занятие: Ест", "Card reads EATING")
		paused = true
		clock.advance(100.0)
		check(data.activity == Activity.Type.EATING and data.hunger == 75, "Paused meal timer does not advance")
		paused = false
		var food_point: Vector2 = view.global_position
		clock.advance(29.0 / speed)
		check(data.activity == Activity.Type.EATING and view.global_position == food_point, "Meal lasts at least 29 game minutes on every speed")
		clock.advance(1.0 / speed)
		check(data.hunger == 17 and intents.current_intent.reason_id == &"day_work", "Minute 30 reduces hunger by 60 and resumes work schedule")
		view._process(20.0)
		check(data.activity == Activity.Type.WORKING, "After food returns to WORKING in daytime")
		check(data.fatigue == 35 and data.mood == 65, "Food leaves fatigue/mood unchanged")
		scene.free()
	# Evening meal remains IDLE, manual commands cannot interrupt eating.
	var scene = make_scene()
	var data = scene.resident_data
	var view = scene.resident_view
	var clock = scene.game_time
	var needs = scene.get_node("ResidentNeedsController")
	clock.debug_next_phase()
	clock.debug_next_phase()
	data.hunger = 75
	view._process(20.0)
	check(data.activity == Activity.Type.EATING and not scene.resident_schedule.request_manual_move(Vector2.ZERO), "Evening food holds priority after arrival")
	clock.debug_skip_minutes(30)
	check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "Evening completion does not assign automatic destination")
	# Night interrupts an unfinished meal: no hunger reduction later.
	clock.debug_skip_minutes(329)
	data.hunger = 75
	view._process(20.0)
	check(data.activity == Activity.Type.EATING, "Already at kitchen starts meal immediately")
	clock.debug_next_phase()
	check(scene.resident_intents.current_intent.reason_id == &"night_home" and data.activity == Activity.Type.MOVING, "23:00 interrupts EATING with priority 100 home route")
	var after_interruption: int = data.hunger
	clock.debug_skip_minutes(30)
	check(data.hunger >= after_interruption, "Interrupted meal never applies delayed hunger reduction")
	view._process(20.0)
	data.hunger = 75
	check(data.activity == Activity.Type.SLEEPING and not view.has_movement_target, "Hungry sleeper does not seek food")
	clock.debug_next_phase()
	check(scene.resident_intents.current_intent.reason_id == &"eat", "Morning awakening reevaluates high hunger")
	scene.free()
	# Missing FOOD representation means no fake destination or meal.
	scene = make_scene()
	data = scene.resident_data
	view = scene.resident_view
	clock = scene.game_time
	scene.get_node("World/CommunalKitchen").free()
	data.hunger = 75
	check(not view.has_movement_target and data.activity == Activity.Type.IDLE, "Missing kitchen does not send resident to world origin")
	scene.free()
	# Food route across phase transitions: work cannot overwrite it; evening preserves meal.
	scene = make_scene()
	data = scene.resident_data
	view = scene.resident_view
	clock = scene.game_time
	data.hunger = 69
	clock.debug_skip_minutes(15)
	check(scene.resident_intents.current_intent.reason_id == &"eat", "Natural growth crossing 70 triggers food decision")
	var same = scene.resident_intents.current_intent
	clock.debug_next_phase()
	check(scene.resident_intents.current_intent == same, "07:00 work cannot overwrite an existing food route")
	view._process(20.0)
	# Lower hunger for clamp check, and skip to evening while timer stays under 30.
	clock.total_minutes = 1019
	clock.advance(1.0)
	check(data.activity == Activity.Type.EATING, "17:00 does not prematurely interrupt food")
	data.hunger = 0
	clock.debug_skip_minutes(29)
	check(data.hunger == 0 and data.activity == Activity.Type.IDLE, "Meal reduction clamps at zero and resumes evening IDLE")
	scene.free()
	# Night also interrupts movement to food; stale arrival cannot start meal.
	scene = make_scene()
	data = scene.resident_data
	view = scene.resident_view
	clock = scene.game_time
	clock.debug_next_phase()
	clock.debug_next_phase()
	data.hunger = 75
	var old_eat = scene.resident_intents.current_intent
	clock.debug_next_phase()
	view.intent_completed.emit(old_eat)
	check(scene.resident_intents.current_intent.reason_id == &"night_home" and data.activity == Activity.Type.MOVING, "Night preempts food route and ignores stale arrival")
	scene.free()
	# Arrival during the same minute signal must not count that minute twice.
	scene = make_scene()
	data = scene.resident_data
	view = scene.resident_view
	clock = scene.game_time
	view.global_position = scene.world_locations.get_position(scene.kitchen_data.id)
	data.hunger = 69
	clock.advance(15.0)
	check(data.activity == Activity.Type.EATING and data.hunger == 70, "Natural threshold at kitchen starts meal synchronously")
	clock.advance(29.0)
	check(data.activity == Activity.Type.EATING, "Arrival minute is excluded from meal duration")
	clock.advance(1.0)
	check(data.activity == Activity.Type.IDLE and data.hunger == 12, "Synchronous meal completes after exactly 30 following minutes")
	scene.free()
	# A morning meal survives 07:00 and then returns to daytime work.
	scene = make_scene()
	data = scene.resident_data
	view = scene.resident_view
	clock = scene.game_time
	clock.debug_skip_minutes(59)
	data.hunger = 75
	view._process(20.0)
	clock.debug_next_phase()
	check(data.activity == Activity.Type.EATING, "07:00 cannot interrupt an ongoing morning meal")
	clock.debug_skip_minutes(29)
	check(scene.resident_intents.current_intent.reason_id == &"day_work", "Meal spanning 07:00 resumes work on completion")
	scene.free()
	paused = false
	print("Needs checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
