extends SceneTree
const Intent = preload("res://scripts/resident_intent.gd")
const Intents = preload("res://scripts/resident_intent_controller.gd")
const Job = preload("res://scripts/haul_job.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Drop = preload("res://scripts/ground_resource.gd")
const FOOD = ResourceType.Type.FOOD
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
	scene.residents[0].fatigue = 0
	for need in scene.residents[0].needs.values(): need.base_weight = 0
	scene.kitchen_data.resources.add(FOOD, 1)
	return scene
func critical_key() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F10
		event.shift_pressed = true
		event.pressed = pressed
		root.push_input(event, true)
func _run() -> void:
	var intents = Intents.new()
	root.add_child(intents)
	var locked = Intent.new(Intent.Type.MOVE_TO, &"locked", Vector2.ZERO, 80, false)
	var home = Intent.new(Intent.Type.MOVE_TO, &"night_home", Vector2.ONE, 100)
	intents.submit(locked)
	intents.submit(home)
	check(intents.current_intent == locked and intents.pending_intent == home, "Ordinary high priority still waits behind locked current")
	var critical = Intent.new(Intent.Type.MOVE_TO, &"critical", Vector2(2, 2), 1)
	check(intents.force_set_intent(critical) and intents.current_intent == critical and intents.pending_intent.type == Intent.Type.NONE, "Forced even lower priority replaces locked action and clears pending")
	check(not intents.submit(home) and not intents.clear_completed(locked), "Ordinary priority and stale completion cannot erase emergency")
	intents.clear_completed(critical)
	check(intents.submit(home), "Ordinary rules restored after emergency completion")
	intents.free()
	# Before pickup: no ground resource, source stock untouched, both reserves freed.
	var scene = make_scene()
	scene.game_time.debug_next_phase()
	var job = scene.logistics.current_job
	scene.resident_selection.select(scene.residents[0])
	critical_key()
	check(scene.residents[0].hunger == 100 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"eat", "Actual Shift+F10 immediately creates critical food route")
	check(job.state == Job.State.CANCELLED and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0, "Critical before pickup cancels job and both reserves")
	check(scene.warehouse_data.resources.get_amount(FOOD) == 10 and scene.ground_resources.drops.is_empty() and scene.residents[0].inventory.amount == 0, "No resource moved before pickup")
	scene.free()
	# Loaded critical interrupt also clears a pending night goal and drops cargo here.
	for speed in [1, 2, 4]:
		scene = make_scene()
		scene.game_time.set_speed(speed)
		scene.game_time.debug_next_phase()
		scene.resident_runtimes[0].view._process(20.0)
		job = scene.logistics.current_job
		var old = scene.resident_runtimes[0].intents.current_intent
		scene.game_time.debug_next_phase()
		scene.game_time.debug_next_phase()
		check(scene.resident_runtimes[0].intents.pending_intent.reason_id == &"night_home", "Ordinary night is pending before emergency")
		var position: Vector2 = scene.resident_runtimes[0].view.global_position
		# Keep unrelated outgoing reservation: forced cancellation must not release it.
		scene.warehouse_data.resources.reserve_out(FOOD, 2)
		paused = true
		scene.residents[0].hunger = 100
		check(job.state == Job.State.CANCELLED and scene.residents[0].inventory.amount == 0 and not scene.resident_runtimes[0].view.cargo_indicator.visible, "Emergency cancels loaded job and clears inventory picture")
		check(scene.warehouse_data.resources.get_amount(FOOD) == 9 and scene.warehouse_data.resources.get_reserved_out(FOOD) == 2 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0, "Only incoming reserve released after pickup; unrelated outgoing reserve preserved")
		check(scene.ground_resources.drops.size() == 1 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"eat" and scene.resident_runtimes[0].intents.pending_intent.type == Intent.Type.NONE, "Exactly one physical drop; emergency supersedes pending night")
		var drop = scene.ground_resources.drops[0]
		check(drop is RefCounted and not drop is Node and drop.amount == 1 and drop.resource_type == FOOD and drop.world_position == position and drop.age_minutes(scene.game_time.total_minutes) == 0, "Drop owns FOOD with world position and creation time")
		var view = scene._ground_views[drop]
		check(view.is_visible_in_tree() and view.global_position == position, "Ground picture at actual interruption point")
		scene.resident_runtimes[0].view.intent_completed.emit(old)
		check(scene.ground_resources.drops.size() == 1 and scene.kitchen_data.resources.get_amount(FOOD) == 1, "Late delivery cannot duplicate dropped FOOD")
		scene.game_time.advance(100.0)
		check(drop.age_minutes(scene.game_time.total_minutes) == 0, "Pause does not age physical resource")
		# Isolate lifetime from further resident decisions while advancing all game minutes.
		scene.logistics.unbind_execution()
		scene.resident_runtimes[0].decision.free()
		scene.resident_runtimes[0].needs.free()
		scene.game_time.debug_skip_minutes(Drop.LIFETIME_MINUTES - 1)
		check(scene.ground_resources.drops.size() == 1, "Drop remains through 4319 game minutes even on pause")
		scene.game_time.debug_skip_minutes(1)
		check(scene.ground_resources.drops.is_empty() and not scene._ground_views.has(drop), "At 3 game days data removed and picture scheduled for removal")
		paused = false
		scene.free()
	# 76–99 finishes current action and attempts food before another working task.
	scene = make_scene()
	scene.game_time.debug_next_phase()
	job = scene.logistics.current_job
	scene.residents[0].get_need(preload("res://scripts/need_type.gd").Type.HUNGER).base_weight = 100
	scene.residents[0].hunger = 90
	check(job.state == Job.State.GOING_TO_SOURCE and scene.resident_runtimes[0].intents.current_intent.reason_id == &"haul_source", "Strong hunger does not interrupt work to source")
	scene.resident_runtimes[0].view._process(20.0)
	check(scene.residents[0].inventory.amount == 1 and scene.ground_resources.drops.is_empty(), "Strong hunger also retains loaded task")
	scene.resident_runtimes[0].view._process(20.0)
	check(job.state == Job.State.COMPLETED and scene.residents[0].activity == Activity.Type.EATING and scene.resident_runtimes[0].intents.current_intent.reason_id == &"eat", "At action boundary eats before starting next haul")
	scene.game_time.debug_skip_minutes(30)
	check(scene.residents[0].hunger < 76, "Successful meal lowers strong hunger")
	scene.free()
	# Forced interruption in the exposed CARRYING transition cannot resurrect the job.
	scene = make_scene()
	scene.game_time.debug_next_phase()
	var carrying_scene = scene
	scene.logistics.changed.connect(func():
		if carrying_scene.logistics.current_job.state == Job.State.CARRYING:
			carrying_scene.residents[0].hunger = 100)
	scene.resident_runtimes[0].view._process(20.0)
	check(scene.logistics.current_job.state == Job.State.CANCELLED and scene.ground_resources.drops.size() == 1 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"eat", "Forced in CARRYING notification remains cancelled and does not issue a delivery route")
	scene.free()
	# Already eating at the critical threshold keeps its elapsed meal time.
	scene = make_scene()
	scene.kitchen_data.resources.add(FOOD, 1)
	scene.residents[0].get_need(preload("res://scripts/need_type.gd").Type.HUNGER).base_weight = 100
	scene.residents[0].hunger = 75
	scene.resident_runtimes[0].decision.request_decision("test")
	scene.resident_runtimes[0].view._process(20.0)
	scene.game_time.debug_skip_minutes(20)
	scene.residents[0].hunger = 100
	check(scene.residents[0].activity == Activity.Type.EATING, "Critical hunger retains already active food action")
	scene.game_time.debug_skip_minutes(10)
	check(scene.residents[0].hunger == 80 and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Forced protection does not restart existing meal timer")
	scene.free()
	# Exhaustion uses the same forced cleanup before and after resource pickup.
	for picked_up in [false, true]:
		scene = make_scene()
		scene.game_time.debug_next_phase()
		job = scene.logistics.current_job
		if picked_up: scene.resident_runtimes[0].view._process(20)
		var dropped_at: Vector2 = scene.resident_runtimes[0].view.position
		scene.residents[0].fatigue = 100
		check(job.state == Job.State.CANCELLED and scene.residents[0].activity == Activity.Type.SLEEPING, "Critical fatigue cancels ordinary haul and sleeps in place")
		check(scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0 and scene.residents[0].inventory.amount == 0, "Exhaustion settles correct reserves and clears carried slot")
		check(scene.ground_resources.drops.size() == (1 if picked_up else 0), "Only already picked cargo becomes a physical drop")
		if picked_up: check(scene.ground_resources.drops[0].world_position == dropped_at, "Exhaustion drop stays where resident stopped")
		scene.free()
	paused = false
	print("Emergency checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
