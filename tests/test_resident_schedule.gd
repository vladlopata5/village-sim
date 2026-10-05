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
func next_phase() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F8
		event.pressed = pressed
		root.push_input(event, true)
func right_click(scene: Node, target: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = scene.resident_runtimes[0].view.get_canvas_transform() * target
		event.pressed = pressed
		root.push_input(event, true)
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.logistics.unbind_execution()
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	await process_frame
	await process_frame
	var clock = scene.game_time
	var view = scene.resident_runtimes[0].view
	var data = scene.residents[0]
	var schedule = scene.resident_runtimes[0].schedule
	var intents = scene.resident_runtimes[0].intents
	var home = scene.get_node("World/home_stepan")
	var work = scene.get_node("World/Warehouse")
	var card = scene.get_node("HUD/ResidentCard")
	clock.set_process(false)
	view.set_process(false)
	scene.resident_selection.select(data)
	check(not scene.has_node("NightHomeController"), "Old schedule controller removed")
	check(data.work_location_id == &"warehouse_01" and work.building_data.display_name == "Склад", "Warehouse is resident work location")
	for speed in [1, 2, 4]:
		clock.set_speed(speed)
		check(clock.get_clock_text() == "06:00" and data.activity == Activity.Type.IDLE, "Cycle starts morning IDLE")
		right_click(scene, Vector2(-100, 180))
		check(intents.current_intent.reason_id == &"manual_move", "Morning right click accepted")
		paused = true
		var before: Vector2 = view.global_position
		next_phase()
		check(clock.get_clock_text() == "07:00" and intents.current_intent.reason_id == &"day_work" and intents.current_intent.priority == 7000 and view.target_position == work.global_position, "F8 to day replaces manual goal with work goal")
		view._process(1.0)
		check(view.global_position == before and data.activity == Activity.Type.MOVING, "Paused work command does not move")
		right_click(scene, Vector2(-100, 180))
		check(intents.current_intent.reason_id == &"day_work", "Day right click cannot replace work route")
		paused = false
		view._process(0.1)
		check(view.global_position.is_equal_approx(before.move_toward(work.global_position, 12.0 * speed)), "Work resumes at current speed without catch-up")
		view._process(20.0)
		check(data.activity == Activity.Type.WORKING and view.global_position == work.global_position and intents.current_intent.type == Intent.Type.NONE, "Work arrival completes intent and enters WORKING")
		card._refresh()
		check(card.activity_label.text == "Занятие: Работает", "Card reads WORKING from data")
		right_click(scene, Vector2(-100, 180))
		check(data.activity == Activity.Type.WORKING and not view.has_movement_target, "Day manual input remains blocked after arrival")
		next_phase()
		check(clock.get_clock_text() == "17:00" and data.activity == Activity.Type.IDLE, "F8 ends working at 17:00")
		right_click(scene, Vector2(-100, 180))
		check(intents.current_intent.reason_id == &"manual_move", "Evening right click accepted")
		paused = true
		before = view.global_position
		next_phase()
		check(clock.get_clock_text() == "23:00" and intents.current_intent.reason_id == &"night_home" and intents.current_intent.priority == 10000 and data.activity == Activity.Type.MOVING, "F8 night preempts evening goal")
		view._process(1.0)
		check(view.global_position == before, "Paused home command does not move")
		paused = false
		view._process(0.1)
		check(view.global_position.is_equal_approx(before.move_toward(home.global_position, 12.0 * speed)), "Home resumes at current speed without catch-up")
		view._process(20.0)
		check(data.activity == Activity.Type.SLEEPING and view.global_position == home.global_position, "Home arrival enters SLEEPING")
		right_click(scene, Vector2(-100, 180))
		check(data.activity == Activity.Type.SLEEPING and not view.has_movement_target, "Night click cannot wake resident")
		next_phase()
		check(clock.get_clock_text() == "06:00" and data.activity == Activity.Type.IDLE and not view.has_movement_target, "F8 wakes resident at next morning")
	# Cancel unfinished work at evening, ignore late arrival.
	next_phase()
	var cancelled_work = intents.current_intent
	next_phase()
	check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "17:00 cancels unfinished work route")
	view.intent_completed.emit(cancelled_work)
	check(data.activity == Activity.Type.IDLE, "Late work completion cannot restart work in evening")
	next_phase()
	var cancelled_home = intents.current_intent
	next_phase()
	check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "06:00 cancels unfinished home route")
	view.intent_completed.emit(cancelled_home)
	check(data.activity == Activity.Type.IDLE, "Late home completion cannot restart sleep in morning")
	# Resolve moved work marker, including immediate completion at current position.
	work.global_position = view.global_position
	next_phase()
	check(data.activity == Activity.Type.WORKING, "Already at work completes synchronously")
	next_phase()
	next_phase()
	view._process(20.0)
	next_phase()
	data.work_location_id = &"missing"
	next_phase()
	check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "Missing work location does not create bogus route")
	check(not schedule.request_manual_move(Vector2.ZERO), "Work period remains protected without place")
	next_phase()
	check(schedule.request_manual_move(Vector2(-100, 180)), "Evening permits manual command after missing work")
	check(data.fatigue >= 0 and data.fatigue <= 100 and data.mood == 65, "Full cycles leave mood unchanged and fatigue bounded")
	scene.queue_free()
	# Initial setup during a work phase also follows the schedule.
	var day_scene = load("res://scenes/main.tscn").instantiate()
	day_scene.get_node("GameTime").total_minutes = 420
	root.add_child(day_scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(day_scene)
	day_scene.logistics.unbind_execution()
	day_scene.resident_runtimes[0].intents.clear_reason(&"haul_source")
	day_scene.resident_runtimes[0].schedule.resume_current_phase()
	check(day_scene.resident_runtimes[0].intents.current_intent.reason_id == &"day_work", "Starting at 07:00 issues work intent")
	day_scene.queue_free()
	print("Schedule checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
