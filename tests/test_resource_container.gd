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
	for speed in [1, 2, 4]:
		var scene = make_scene()
		var clock = scene.game_time
		var data = scene.residents[0]
		var view = scene.resident_runtimes[0].view
		stock = scene.kitchen_data.resources
		check(stock.get_amount(ResourceType.Type.FOOD) == 3 and scene.food_label.text == "Еда в кухне: 3", "Starting food and UI")
		clock.set_speed(speed)
		scene.resident_selection.select(data)
		key(KEY_F8)
		view._process(20.0)
		key(KEY_F10)
		view._process(20.0)
		check(data.activity == Activity.Type.EATING and stock.get_amount(ResourceType.Type.FOOD) == 3, "Meal starts without reserving resource")
		clock.advance(29.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 3, "Food not consumed before meal completion")
		clock.advance(1.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 2 and scene.food_label.text == "Еда в кухне: 2" and data.hunger == 17, "Completion consumes 1, updates UI and reduces hunger")
		check(scene.resident_runtimes[0].intents.current_intent.reason_id == &"day_work", "Successful meal resumes daytime work")
		stock.try_take(ResourceType.Type.FOOD, 2)
		var messages: Array[String] = []
		scene.resident_runtimes[0].needs.developer_message.connect(func(message: String): messages.append(message))
		key(KEY_F10)
		view._process(20.0)
		check(data.activity == Activity.Type.EATING, "Empty stock begins short failed attempt")
		paused = true
		clock.advance(100.0)
		check(data.activity == Activity.Type.EATING and messages.is_empty(), "Paused failed attempt does not progress")
		paused = false
		clock.advance(4.0 / speed)
		check(data.activity == Activity.Type.EATING, "Short attempt lasts five game minutes")
		var before: int = data.hunger
		clock.advance(1.0 / speed)
		check(data.activity == Activity.Type.IDLE and data.hunger >= before and stock.get_amount(ResourceType.Type.FOOD) == 0, "Empty stock does not reduce hunger and exits EATING")
		check(messages == ["Степан не смог поесть: нет еды."], "One developer message emitted")
		clock.advance(60.0 / speed)
		check(data.activity == Activity.Type.IDLE and messages.size() == 1, "Empty stock never loops failed meals")
		paused = true
		var minute: int = clock.total_minutes
		key(KEY_F11)
		check(stock.get_amount(ResourceType.Type.FOOD) == 1 and scene.food_label.text == "Еда в кухне: 1" and data.activity == Activity.Type.EATING, "F11 restocks and unblocks hungry resident")
		key(KEY_F11, true)
		check(stock.get_amount(ResourceType.Type.FOOD) == 1 and clock.total_minutes == minute, "F11 ignores held echo and leaves paused time alone")
		paused = false
		clock.advance(30.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 0 and data.hunger < 70, "Restocked meal consumes one and satisfies hunger")
		check(data.fatigue == 35 and data.mood == 65, "Storage does not alter fatigue or mood")
		scene.free()
	# Stock may disappear during a normal meal: check again at completion.
	var scene = make_scene()
	var clock = scene.game_time
	var data = scene.residents[0]
	var view = scene.resident_runtimes[0].view
	stock = scene.kitchen_data.resources
	data.hunger = 75
	view._process(20.0)
	stock.try_take(ResourceType.Type.FOOD, 3)
	clock.advance(30.0)
	check(data.activity == Activity.Type.IDLE and data.hunger == 77 and stock.get_amount(ResourceType.Type.FOOD) == 0, "Depleted during meal gets no free hunger reduction")
	scene.free()
	# Restocking during the short attempt starts a full 30-minute meal.
	scene = make_scene()
	clock = scene.game_time
	data = scene.residents[0]
	view = scene.resident_runtimes[0].view
	stock = scene.kitchen_data.resources
	stock.try_take(ResourceType.Type.FOOD, 3)
	data.hunger = 75
	view._process(20.0)
	clock.advance(4.0)
	key(KEY_F11)
	clock.advance(29.0)
	check(data.activity == Activity.Type.EATING and stock.get_amount(ResourceType.Type.FOOD) == 1, "Restocking short attempt does not grant instant meal")
	clock.advance(1.0)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0 and data.hunger < 70, "Full meal after mid-attempt restock succeeds")
	scene.free()
	# Night waits for meal consumption, then activates home.
	scene = make_scene()
	clock = scene.game_time
	data = scene.residents[0]
	view = scene.resident_runtimes[0].view
	stock = scene.kitchen_data.resources
	clock.debug_next_phase()
	clock.debug_next_phase()
	data.hunger = 75
	view._process(20.0)
	clock.total_minutes = 1379
	clock.advance(1.0)
	check(scene.resident_runtimes[0].intents.pending_intent.reason_id == &"night_home" and data.activity == Activity.Type.EATING and stock.get_amount(ResourceType.Type.FOOD) == 3, "Night waits for meal before consumption")
	clock.advance(29.0)
	check(stock.get_amount(ResourceType.Type.FOOD) == 2 and scene.resident_runtimes[0].intents.current_intent.reason_id == &"night_home", "Completed meal consumes locally then starts pending home")
	scene.free()
	# Plenty of food somewhere else cannot satisfy an empty selected kitchen.
	scene = make_scene()
	clock = scene.game_time
	data = scene.residents[0]
	view = scene.resident_runtimes[0].view
	stock = scene.kitchen_data.resources
	stock.try_take(ResourceType.Type.FOOD, 3)
	var another_building = load("res://scripts/building_data.gd").new(&"other_test_place", "Другое место", load("res://scripts/building_type.gd").Type.FOOD)
	another_building.resources.set_capacity(ResourceType.Type.FOOD, 30)
	another_building.resources.add(ResourceType.Type.FOOD, 20)
	check(another_building.resources != stock and stock.owner_id == scene.kitchen_data.id, "Every building owns a separate container")
	data.hunger = 75
	view._process(20.0)
	clock.advance(5.0)
	check(data.activity == Activity.Type.IDLE and data.hunger == 75 and another_building.resources.get_amount(ResourceType.Type.FOOD) == 20, "Other place food cannot pay for kitchen meal")
	another_building.resources.add(ResourceType.Type.FOOD, 1)
	scene.resident_runtimes[0].needs.evaluate()
	check(data.activity == Activity.Type.IDLE and not view.has_movement_target, "Other place restock cannot unlock this kitchen")
	stock.add(ResourceType.Type.FOOD, 1)
	check(data.activity == Activity.Type.EATING, "Only selected kitchen restock unlocks meal")
	var kitchen = scene.kitchen_data
	scene.get_node("World/CommunalKitchen").free()
	check(kitchen.resources == stock and stock.get_amount(ResourceType.Type.FOOD) == 1, "Local stock survives visual removal")
	scene.free()
	paused = false
	print("Local container checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
