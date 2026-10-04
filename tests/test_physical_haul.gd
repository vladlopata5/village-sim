extends SceneTree
const Job = preload("res://scripts/haul_job.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Resources = preload("res://scripts/resource_type.gd")
const Inventory = preload("res://scripts/resident_inventory.gd")
const FOOD = Resources.Type.FOOD
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
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	scene.resident_runtimes[0].view.set_process(false)
	return scene
func total(scene: Node) -> int:
	return scene.warehouse_data.resources.get_amount(FOOD) + scene.kitchen_data.resources.get_amount(FOOD) + scene.residents[0].inventory.amount
func _run() -> void:
	var inventory = Inventory.new()
	check(not inventory.put(FOOD, 2) and inventory.put(FOOD, 1) and not inventory.put(FOOD, 1), "Inventory accepts only one FOOD")
	inventory.clear()
	check(inventory.amount == 0, "Inventory clears cargo")
	for speed in [1, 2, 4]:
		var scene = make_scene()
		var view = scene.resident_runtimes[0].view
		var clock = scene.game_time
		var data = scene.residents[0]
		clock.set_speed(speed)
		clock.debug_next_phase()
		check(scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE and view.target_position == scene.world_locations.get_position(&"warehouse_01"), "Day starts haul to source")
		for number in range(3):
			var job = scene.logistics.current_job
			check(total(scene) == 10 and data.inventory.amount == 0 and scene.warehouse_data.resources.get_reserved_out(FOOD) == 1, "Before pickup FOOD exists only in containers")
			paused = true
			var before: Vector2 = view.global_position
			view._process(1.0)
			check(view.global_position == before and data.inventory.amount == 0, "Pause stops source path")
			paused = false
			view._process(20.0)
			check(job.state == Job.State.GOING_TO_DESTINATION and data.inventory.amount == 1 and data.activity == Activity.Type.HAULING, "Pickup switches to carrying destination route")
			check(scene.warehouse_data.resources.get_amount(FOOD) == 9 - number and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and total(scene) == 10, "Pickup consumes exactly the reserved unit")
			check(view.cargo_indicator.visible and not scene.resident_runtimes[0].intents.current_intent.interruptible, "Visible cargo and noninterruptible transport")
			var card = scene.get_node("HUD/ResidentCard")
			scene.resident_selection.select(data)
			card._refresh()
			check(card.activity_label.text == "Занятие: Несёт груз", "Card reads HAULING")
			check(not scene.resident_runtimes[0].schedule.request_manual_move(Vector2.ZERO), "Manual commands cannot interrupt haul")
			paused = true
			before = view.global_position
			view._process(1.0)
			check(view.global_position == before and data.inventory.amount == 1, "Pause retains carried FOOD")
			paused = false
			var destination_intent = scene.resident_runtimes[0].intents.current_intent
			view._process(20.0)
			check(job.state == Job.State.COMPLETED and data.inventory.amount == 0 and not view.cargo_indicator.visible and scene.kitchen_data.resources.get_amount(FOOD) == number + 1 and total(scene) == 10, "Delivery puts unit only in kitchen")
			view.intent_completed.emit(destination_intent)
			check(total(scene) == 10 and scene.kitchen_data.resources.get_amount(FOOD) == number + 1, "Stale arrival cannot duplicate delivery")
		check(scene.warehouse_data.resources.get_amount(FOOD) == 7 and scene.kitchen_data.resources.get_amount(FOOD) == 3 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0 and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0, "Target stock 3 stops new jobs with all reserves settled")
		view._process(20.0)
		check(data.activity == Activity.Type.WORKING, "After target returns to normal warehouse work")
		scene.free()
	# Evening preserves both already-started stages, then returns to IDLE.
	for picked_up in [false, true]:
		var scene = make_scene()
		scene.game_time.debug_next_phase()
		var job = scene.logistics.current_job
		if picked_up:
			scene.resident_runtimes[0].view._process(20.0)
		scene.game_time.debug_next_phase()
		check(job.is_active() and not scene.resident_runtimes[0].schedule.request_manual_move(Vector2.ZERO), "17:00 and manual input do not discard started haul")
		if not picked_up:
			scene.resident_runtimes[0].view._process(20.0)
		scene.resident_runtimes[0].view._process(20.0)
		check(job.state == Job.State.COMPLETED and scene.residents[0].activity == Activity.Type.IDLE and total(scene) == 10, "Evening delivery completes and returns IDLE")
		scene.free()
	# Night before pickup releases both reserves; next day gets a new job.
	var scene = make_scene()
	scene.game_time.debug_next_phase()
	var cancelled = scene.logistics.current_job
	var stale_source = scene.resident_runtimes[0].intents.current_intent
	scene.game_time.debug_next_phase()
	scene.game_time.debug_next_phase()
	check(cancelled.state == Job.State.CANCELLED and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0 and scene.residents[0].inventory.amount == 0 and total(scene) == 10, "23:00 before pickup cancels both promises without changing physical stock")
	check(scene.resident_runtimes[0].intents.current_intent.reason_id == &"night_home", "Cancelled source path immediately heads home")
	scene.resident_runtimes[0].view.intent_completed.emit(stale_source)
	check(scene.residents[0].inventory.amount == 0, "Late pickup cannot steal released FOOD")
	scene.resident_runtimes[0].view._process(20.0)
	scene.residents[0].hunger = 20 # Isolate workday restart from the new strong-hunger rule.
	scene.game_time.debug_next_phase()
	scene.game_time.debug_next_phase()
	check(scene.logistics.current_job.id != cancelled.id and scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE, "Next workday creates fresh haul")
	scene.free()
	# Night after pickup waits for delivery, not for a second pickup or empty hands.
	scene = make_scene()
	scene.game_time.debug_next_phase()
	scene.resident_runtimes[0].view._process(20.0)
	var delivered = scene.logistics.current_job
	scene.game_time.debug_next_phase()
	scene.game_time.debug_next_phase()
	check(scene.resident_runtimes[0].intents.pending_intent.reason_id == &"night_home" and scene.residents[0].inventory.amount == 1 and scene.residents[0].activity == Activity.Type.HAULING, "Night home waits while FOOD is carried")
	check(not scene.logistics.cancel_job(delivered), "Loaded haul cannot be cancelled or lose reserved destination")
	scene.resident_runtimes[0].view._process(20.0)
	check(delivered.state == Job.State.COMPLETED and scene.residents[0].inventory.amount == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 1 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"night_home" and total(scene) == 10, "Delivery settles FOOD then promotes pending home")
	scene.resident_runtimes[0].view._process(20.0)
	check(scene.residents[0].activity == Activity.Type.SLEEPING, "After loaded night delivery reaches sleep")
	scene.free()
	# Hungry resident delivers first, eats from kitchen, then resumes logistics.
	scene = make_scene()
	scene.game_time.debug_next_phase()
	scene.resident_runtimes[0].view._process(20.0)
	scene.residents[0].hunger = 75
	check(scene.residents[0].inventory.amount == 1 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"haul_destination", "Hunger cannot discard carried FOOD")
	scene.resident_runtimes[0].view._process(20.0)
	check(scene.residents[0].activity == Activity.Type.EATING and scene.residents[0].inventory.amount == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 1, "Hungry porter begins meal only after delivery")
	scene.game_time.debug_skip_minutes(30)
	check(scene.residents[0].hunger < 70 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"haul_source", "After meal resumes assigned haul during work period")
	scene.free()
	# Immediate source arrival must transition to destination without stale clearing.
	scene = make_scene()
	scene.resident_runtimes[0].view.global_position = scene.world_locations.get_position(&"warehouse_01")
	scene.game_time.debug_next_phase()
	check(scene.residents[0].inventory.amount == 1 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"haul_destination", "Resident already at warehouse picks up once synchronously")
	scene.free()
	paused = false
	print("Physical haul checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
