extends SceneTree
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var controller = IntentController.new()
	root.add_child(controller)
	check(controller.current_intent.type == ResidentIntent.Type.NONE, "Initially NONE")
	var manual = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", Vector2(100, 0), 10)
	check(manual is RefCounted and not manual is Node, "Intent is non-visual data")
	check(controller.submit(manual) and controller.current_intent == manual, "Accept first intent")
	check(not controller.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"other", Vector2.ZERO, 5)), "Reject lower priority")
	check(not controller.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"other", Vector2.ZERO, 10)), "Reject equal priority from another source")
	var retarget = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", Vector2(200, 0), 10)
	check(controller.submit(retarget), "Same-source manual intent updates its target")
	check(not controller.clear_completed(manual) and controller.current_intent == retarget, "Stale completion cannot clear retargeted intent")
	var home = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"night_home", Vector2(-300, -120), 100)
	check(controller.submit(home), "Higher priority preempts manual intent")
	check(not controller.submit(retarget), "Lower manual intent cannot preempt home")
	check(not controller.clear_completed(retarget), "Preempted intent cannot clear current home intent")
	check(controller.clear_completed(home) and controller.current_intent.type == ResidentIntent.Type.NONE, "Correct completion clears to NONE")
	check(not controller.submit(ResidentIntent.new()), "NONE cannot erase an active command via submission")
	var meal = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"eat", Vector2.ZERO, 75, false)
	check(controller.submit(meal), "Accept locked action")
	check(not controller.submit(retarget), "Locked action rejects lower priority")
	check(controller.submit(home) and controller.current_intent == meal and controller.pending_intent == home, "Locked action defers home in one pending slot")
	check(not controller.submit(ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"other", Vector2.ZERO, 90)), "Pending keeps highest priority")
	check(not controller.clear_completed(home), "Pending cannot complete before activation")
	check(controller.clear_completed(meal) and controller.current_intent == home and controller.pending_intent.type == ResidentIntent.Type.NONE, "Completion promotes pending and empties slot")
	controller.clear_completed(home)
	controller.submit(meal)
	controller.submit(home)
	controller.clear_reason(&"night_home")
	check(controller.current_intent == meal and controller.pending_intent.type == ResidentIntent.Type.NONE, "Morning drops expired pending without cancelling locked meal")
	controller.clear_completed(meal)
	check(controller.current_intent.type == ResidentIntent.Type.NONE, "Expired home is not activated after completion")
	controller.queue_free()

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.logistics.unbind_execution()
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.get_node("ResidentNeedsController").free()
	await process_frame
	await process_frame
	var intents = scene.get_node("ResidentIntentController")
	var view = scene.get_node("World/ResidentView2D")
	var clock = scene.get_node("GameTime")
	view.set_process(false)
	clock.set_process(false)
	var start: Vector2 = view.global_position
	var first = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", start + Vector2(10, 0), 10)
	intents.submit(first)
	check(view.target_position == first.target_position and view.has_movement_target, "Controller sends accepted intent to view")
	view._process(1.0)
	check(view.global_position == first.target_position and not view.has_movement_target, "View reaches intent target")
	check(intents.current_intent.type == ResidentIntent.Type.NONE, "View arrival clears controller intent")
	var at_current_point = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", view.global_position, 10)
	intents.submit(at_current_point)
	check(intents.current_intent.type == ResidentIntent.Type.NONE, "Already at target completes immediately")
	var old = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", start + Vector2(100, 0), 10)
	intents.submit(old)
	var newer = ResidentIntent.new(ResidentIntent.Type.MOVE_TO, &"manual_move", start + Vector2(200, 0), 10)
	intents.submit(newer)
	view.intent_completed.emit(old)
	check(intents.current_intent == newer and view.target_position == newer.target_position, "Late visual completion does not clear replacement")
	view._process(10.0)
	check(intents.current_intent.type == ResidentIntent.Type.NONE, "Replacement completes normally")
	# Morning must permit a new manual goal even if the home path is unfinished.
	clock.total_minutes = 1379
	clock.advance(1.0)
	check(intents.current_intent.reason_id == &"night_home" and intents.current_intent.priority == 100, "23:00 creates home intent")
	var morning_position: Vector2 = view.global_position
	clock.total_minutes = 1799
	clock.advance(1.0)
	check(intents.current_intent.type == ResidentIntent.Type.NONE and not view.has_movement_target and view.global_position == morning_position, "Morning cancels unfinished home intent without moving")
	check(scene.get_node("ResidentScheduleController").request_manual_move(start), "Morning manual intent replaces unfinished home path")
	check(intents.current_intent.reason_id == &"manual_move", "Manual intent becomes current after morning release")
	var data = scene.resident_data
	check(data.fatigue == 35 and data.mood == 65, "Intent mechanism leaves fatigue and mood untouched")
	scene.queue_free()
	print("Intent checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
