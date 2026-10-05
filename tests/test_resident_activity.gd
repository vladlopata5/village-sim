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

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	await process_frame
	await process_frame
	var data = scene.residents[0]
	var view = scene.resident_runtimes[0].view
	var intents = scene.resident_runtimes[0].intents
	var night = scene.resident_runtimes[0].schedule
	var clock = scene.game_time
	var card = scene.get_node("HUD/ResidentCard")
	clock.set_process(false)
	view.set_process(false)
	scene.resident_selection.select(data)
	check(data.activity == Activity.Type.IDLE, "Initial IDLE")
	card._refresh()
	check(card.activity_label.text == "Занятие: Бездельничает", "Card reads initial activity")
	for speed in [1, 2, 4]:
		clock.set_speed(speed)
		var goal: Vector2 = view.global_position + Vector2(100, 0)
		check(night.request_manual_move(goal) and data.activity == Activity.Type.MOVING, "Manual intent sets MOVING")
		var old = intents.current_intent
		check(not intents.submit(Intent.new(Intent.Type.MOVE_TO, &"other", goal, 1)) and data.activity == Activity.Type.MOVING, "Rejected intent leaves activity intact")
		card._refresh()
		check(card.activity_label.text == "Занятие: Идёт", "Card reads moving state")
		paused = true
		var before: Vector2 = view.global_position
		view._process(1.0)
		check(data.activity == Activity.Type.MOVING and view.global_position == before, "Paused movement preserves activity without moving")
		paused = false
		view._process(10.0)
		check(data.activity == Activity.Type.IDLE and intents.current_intent.type == Intent.Type.NONE, "Ordinary arrival sets IDLE")
		# Real phase progression; no direct controller phase calls.
		while clock.get_phase() != "Ночь":
			clock.debug_next_phase()
		check(data.activity == Activity.Type.MOVING and intents.current_intent.reason_id == &"night_home", "Night sets home movement")
		view.intent_completed.emit(old)
		check(data.activity == Activity.Type.MOVING, "Stale arrival cannot start sleep")
		view._process(20.0)
		check(data.activity == Activity.Type.SLEEPING and intents.current_intent.type == Intent.Type.NONE, "Home arrival at night starts sleep after intent clears")
		card._refresh()
		check(card.activity_label.text == "Занятие: Спит", "Card reads sleeping state")
		check(not night.request_manual_move(goal) and data.activity == Activity.Type.SLEEPING, "Night manual command cannot wake resident")
		clock.debug_skip_minutes(60)
		check(data.activity == Activity.Type.SLEEPING, "Midnight preserves sleep")
		paused = true
		clock.debug_next_phase()
		check(data.activity == Activity.Type.IDLE and not night.is_night, "06:00 wakes resident even during debug pause")
		paused = false
		check(night.request_manual_move(goal), "Morning allows manual command")
		view._process(10.0)
		# Already home at next night: synchronous arrival must still become sleep.
		night.request_manual_move(scene.world_locations.get_position(data.home_location_id))
		view._process(20.0)
		while clock.get_phase() != "Ночь":
			clock.debug_next_phase()
		check(data.activity == Activity.Type.SLEEPING, "Already at home starts sleep immediately at night")
		clock.debug_next_phase()
		# Unfinished home movement must cancel, not report a completed arrival.
		night.request_manual_move(goal)
		view._process(20.0)
		while clock.get_phase() != "Ночь":
			clock.debug_next_phase()
		var cancelled = intents.current_intent
		check(data.activity == Activity.Type.MOVING, "Unfinished night path starts MOVING")
		clock.debug_next_phase()
		check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "Morning cancels unfinished home movement to IDLE")
		view.intent_completed.emit(cancelled)
		check(data.activity == Activity.Type.IDLE, "Late cancelled arrival cannot cause sleep")
	check(data.fatigue >= 0 and data.fatigue <= 100 and data.mood == 65, "Activities leave mood unchanged and fatigue bounded")
	data.activity = Activity.Type.SLEEPING
	card._refresh()
	check(card.activity_label.text == "Занятие: Спит", "Card reads original data without its own state")
	await process_frame
	check(root.get_visible_rect().encloses(card.close_button.get_global_rect()), "Card close button fits viewport with activity")
	scene.queue_free()
	print("Activity checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
