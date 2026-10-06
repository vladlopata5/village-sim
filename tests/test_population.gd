extends SceneTree
const Activity = preload("res://scripts/resident_activity.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Job = preload("res://scripts/haul_job.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func click(point: Vector2):
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
func _run():
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	# Isolate the population/selection/logistics scenario from ordinary need choice.
	# Critical events still bypass weights; full weights are tested separately.
	for data in scene.residents:
		for need in data.needs.values(): need.base_weight = 0
	var clock = scene.game_time
	clock.set_process(false)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.wander.target_provider = Callable()
	await process_frame
	await process_frame
	check(scene.residents.size() == 4 and scene.resident_runtimes.size() == 4 and scene.population_label.text == "Жителей: 4", "Four resident data/controller/view bundles and count")
	var positions: Array = []
	var ids: Array = []
	var initial: Array = []
	for runtime in scene.resident_runtimes:
		check(not ids.has(runtime.data.id) and not positions.has(runtime.view.position), "Unique IDs and distinct start positions")
		ids.append(runtime.data.id)
		positions.append(runtime.view.position)
		initial.append(runtime.data.hunger)
		for other in scene.resident_runtimes:
			if runtime != other:
				check(runtime.intents != other.intents and runtime.needs != other.needs and runtime.need_dynamics != other.need_dynamics and runtime.data.inventory != other.data.inventory, "Own controllers and inventory")
		scene.resident_selection.clear()
		click(runtime.view.get_global_transform_with_canvas() * Vector2.ZERO)
		check(scene.resident_selection.selected_resident == runtime.data and scene.get_node("HUD/ResidentCard").name_label.text == "Имя: " + runtime.data.resident_name, "Actual click/card selects each resident")
		var target: Vector2 = runtime.view.global_position + Vector2(30, 40)
		var command := InputEventMouseButton.new()
		command.position = runtime.view.get_canvas_transform() * target
		command.button_index = MOUSE_BUTTON_RIGHT
		command.pressed = true
		scene._unhandled_input(command)
		check(runtime.view.target_position == target and runtime.intents.current_intent.reason_id == &"player_move", "Right click addresses selected runtime")
		runtime.view._process(20.0)
	clock.debug_skip_minutes(15)
	for index in range(4): check(scene.residents[index].hunger == initial[index] + 1, "Every hunger advances independently")
	scene.residents[1].activity = Activity.Type.SLEEPING
	clock.debug_skip_minutes(15)
	check(scene.residents[1].hunger == initial[1] + 1 and scene.residents[2].hunger == initial[2] + 2, "One sleeping resident does not change others' growth")
	scene.residents[1].activity = Activity.Type.IDLE
	clock.debug_next_phase()
	check(scene.logistics.current_job.assigned_resident_id == scene.residents[0].id and scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE, "Only assigned porter starts logistics")
	for runtime in [scene.resident_runtimes[1], scene.resident_runtimes[3]]:
		check(runtime.data.profession == Profession.Type.NONE and runtime.data.work_location_id.is_empty() and runtime.data.activity == Activity.Type.IDLE, "Residents without work stay idle by day")
	check(scene.residents[2].profession == Profession.Type.GATHERER and scene.residents[2].work_location_id == scene.gatherer_hut_data.id and scene.residents[2].activity == Activity.Type.MOVING, "Fedor goes to his assigned gatherer hut")
	for delivery in range(5):
		scene.resident_runtimes[0].view._process(20.0)
		scene.resident_runtimes[0].view._process(20.0)
	check(scene.kitchen_data.resources.get_amount(FOOD) == 5 and scene.warehouse_data.resources.get_amount(FOOD) == 5, "Porter fills common kitchen to capacity")
	for runtime in scene.resident_runtimes.slice(1): check(runtime.data.inventory.amount == 0, "No other resident carries cargo")
	var untouched = scene.resident_runtimes[0].intents.current_intent
	var hunger_before: Array = []
	for data in scene.residents: hunger_before.append(data.hunger)
	scene.resident_selection.select(scene.residents[2])
	paused = true
	var event := InputEventKey.new()
	event.physical_keycode = KEY_7
	event.shift_pressed = true
	event.pressed = true
	scene._unhandled_key_input(event)
	check(scene.residents[2].hunger == 100 and scene.resident_runtimes[2].intents.current_intent.reason_id == &"eat", "Shift+7 affects selected resident on pause")
	for index in [0, 1, 3]: check(scene.residents[index].hunger == hunger_before[index], "Other hunger values untouched by debug command")
	check(scene.resident_runtimes[0].intents.current_intent == untouched, "Another resident's emergency does not interrupt porter")
	paused = false
	scene.resident_runtimes[2].view._process(20.0)
	check(scene.residents[2].activity == Activity.Type.EATING, "Non-porter eats at shared kitchen")
	clock.debug_skip_minutes(30)
	check(scene.residents[2].hunger < 70 and scene.kitchen_data.resources.get_amount(FOOD) == 4 and scene.residents[2].activity == Activity.Type.MOVING, "Common food is consumed for the correct resident")
	# Isolate the night schedule from naturally escalating hunger during Shift+3 jumps.
	for runtime in scene.resident_runtimes: runtime.need_dynamics.free()
	for data in scene.residents: data.hunger = 0
	clock.debug_next_phase()
	clock.debug_next_phase()
	for runtime in scene.resident_runtimes:
		check(runtime.intents.current_intent.reason_id == &"night_home" and runtime.view.target_position == scene.world_locations.get_position(runtime.data.home_location_id), "Every resident targets their own home at 23:00")
		runtime.view._process(20.0)
		check(runtime.data.activity == Activity.Type.SLEEPING, "Each resident sleeps at own home")
	clock.debug_next_phase()
	for runtime in scene.resident_runtimes:
		check(runtime.data.activity == Activity.Type.IDLE and runtime.schedule.request_manual_move(runtime.view.position + Vector2(25, 0)), "Each resident wakes and accepts manual commands")
	# All four presentations receive speed changes and obey pause.
	for speed in [1, 2, 4]:
		clock.set_speed(speed)
		for runtime in scene.resident_runtimes:
			var start: Vector2 = runtime.view.position
			runtime.schedule.request_manual_move(start + Vector2(1000, 0))
			paused = true
			runtime.view._process(0.1)
			check(runtime.view.position == start, "Every view remains still on pause")
			paused = false
			runtime.view._process(0.1)
			check(is_equal_approx(runtime.view.position.x - start.x, 12.0 * speed), "Every view moves at x1/x2/x4 without pause jump")
	scene.free()
	# Simultaneous meals share one finite kitchen; no resident-specific branch.
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	for data in scene.residents:
		data.hunger = 0
		data.fatigue = 0
	scene.kitchen_data.resources.add(FOOD, 3)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.data.hunger = 100
		runtime.view._process(20.0)
		check(runtime.data.activity == Activity.Type.EATING or (runtime.data.hunger == 100 and runtime.data.activity == Activity.Type.IDLE), "Critical food action needs an available reservation; fourth cannot start")
	scene.game_time.debug_skip_minutes(30)
	var fed := 0
	var failed := 0
	for data in scene.residents:
		if data.hunger < 70: fed += 1
		else: failed += 1
		check(data.activity != Activity.Type.EATING and data.inventory.amount == 0, "Meal resolves individually without leaking cargo/state")
	check(fed == 3 and failed == 1 and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Three meals consume three FOOD; fourth fails without duplication")
	scene.free()
	print("Population checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
