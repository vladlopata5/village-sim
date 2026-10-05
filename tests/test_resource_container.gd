extends SceneTree
const LocalResources = preload("res://scripts/resource_container.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func key(code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
func make_scene() -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.logistics.unbind_execution()
	scene.kitchen_data.resources.add(ResourceType.Type.FOOD, 3)
	scene.game_time.set_process(false)
	scene.resident_runtimes[0].view.set_process(false)
	return scene
func _run() -> void:
	var stock = LocalResources.new(&"test_place")
	stock.set_capacity(ResourceType.Type.FOOD, 20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0, "Uninitialized resource is zero")
	check(stock.owner_id == &"test_place", "Container identifies its owner")
	var other_container = LocalResources.new(&"other_place")
	other_container.set_capacity(ResourceType.Type.FOOD, 30)
	other_container.add(ResourceType.Type.FOOD, 20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0, "Other place resources never appear in this container")
	stock.add(ResourceType.Type.FOOD, 10)
	check(stock.has_resource(ResourceType.Type.FOOD, 10) and not stock.has_resource(ResourceType.Type.FOOD, 11), "Presence check is local")
	check(stock.try_take(ResourceType.Type.FOOD, 1) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Consumes exactly one resource")
	check(not stock.try_take(ResourceType.Type.FOOD, 10) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Insufficient consumption is atomic")
	stock.add(ResourceType.Type.FOOD, -5)
	check(not stock.try_take(ResourceType.Type.FOOD, -1) and not stock.try_take(ResourceType.Type.FOOD, 0) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Invalid operations cannot create or remove stock")
	var scene = preload("res://tests/need_test_setup.gd").make_scene(self, 360, 1)
	var r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	stock = scene.kitchen_data.resources
	check(stock.get_amount(ResourceType.Type.FOOD) == 1 and stock.get_available_amount(ResourceType.Type.FOOD) == 0, "Food belongs to kitchen and is promised to this resident")
	check(not stock.try_take(ResourceType.Type.FOOD, 1), "Other consumer cannot take promised meal")
	r.intents.force_set_intent(preload("res://scripts/resident_intent.gd").new())
	check(stock.get_reserved_out(ResourceType.Type.FOOD) == 0 and stock.get_amount(ResourceType.Type.FOOD) == 1, "Cancellation before consumption releases meal without losing food")
	r.decision.request_decision()
	r.view._process(20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0 and r.data.activity == Activity.Type.EATING and scene.food_label.text == "Еда в кухне: 0", "Consume locally at start; UI reads actual stock")
	scene.game_time.debug_skip_minutes(30)
	check(r.data.hunger == 20 and stock.get_reserved_out(ResourceType.Type.FOOD) == 0, "Paid meal has gradual benefit and settled reservation")
	scene.free()
	# Warehouse food does not make an empty kitchen a valid meal.
	scene = preload("res://tests/need_test_setup.gd").make_scene(self, 360, 0)
	r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	check(r.data.activity == Activity.Type.IDLE and scene.warehouse_data.resources.get_amount(ResourceType.Type.FOOD) == 10, "No local food means no kitchen trip or free hunger benefit")
	scene.resident_selection.select(r.data)
	key(KEY_F11)
	check(scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 1 and scene.kitchen_data.resources.get_reserved_out(ResourceType.Type.FOOD) == 1, "F11 adds kitchen food and permits a newly available option")
	r.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(r.data.hunger == 20 and scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 0, "Restocked kitchen pays for meal")
	scene.free()
	print("Local resource checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
