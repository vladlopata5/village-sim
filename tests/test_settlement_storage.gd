extends SceneTree
const Storage = preload("res://scripts/settlement_storage.gd")
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
	scene.game_time.set_process(false)
	scene.resident_view.set_process(false)
	return scene
func _run() -> void:
	var stock = Storage.new()
	check(stock.get_amount(ResourceType.Type.FOOD) == 0, "Uninitialized resource is zero")
	stock.add(ResourceType.Type.FOOD, 10)
	check(stock.try_consume(ResourceType.Type.FOOD, 1) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Consumes exactly one resource")
	check(not stock.try_consume(ResourceType.Type.FOOD, 10) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Insufficient consumption is atomic")
	stock.add(ResourceType.Type.FOOD, -5)
	check(not stock.try_consume(ResourceType.Type.FOOD, -1) and not stock.try_consume(ResourceType.Type.FOOD, 0) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Invalid operations cannot create or remove stock")
	for speed in [1, 2, 4]:
		var scene = make_scene()
		var clock = scene.game_time
		var data = scene.resident_data
		var view = scene.resident_view
		stock = scene.settlement_storage
		check(stock.get_amount(ResourceType.Type.FOOD) == 10 and scene.food_label.text == "Еда: 10", "Starting food and UI")
		clock.set_speed(speed)
		scene.resident_selection.select(data)
		key(KEY_F8)
		view._process(20.0)
		key(KEY_F10)
		view._process(20.0)
		check(data.activity == Activity.Type.EATING and stock.get_amount(ResourceType.Type.FOOD) == 10, "Meal starts without reserving resource")
		clock.advance(29.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 10, "Food not consumed before meal completion")
		clock.advance(1.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 9 and scene.food_label.text == "Еда: 9" and data.hunger == 17, "Completion consumes 1, updates UI and reduces hunger")
		check(scene.resident_intents.current_intent.reason_id == &"day_work", "Successful meal resumes daytime work")
		stock.try_consume(ResourceType.Type.FOOD, 9)
		var messages: Array[String] = []
		scene.get_node("ResidentNeedsController").developer_message.connect(func(message: String): messages.append(message))
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
		check(stock.get_amount(ResourceType.Type.FOOD) == 5 and scene.food_label.text == "Еда: 5" and data.activity == Activity.Type.EATING, "F11 restocks and unblocks hungry resident")
		key(KEY_F11, true)
		check(stock.get_amount(ResourceType.Type.FOOD) == 5 and clock.total_minutes == minute, "F11 ignores held echo and leaves paused time alone")
		paused = false
		clock.advance(30.0 / speed)
		check(stock.get_amount(ResourceType.Type.FOOD) == 4 and data.hunger < 70, "Restocked meal consumes one and satisfies hunger")
		check(data.fatigue == 35 and data.mood == 65, "Storage does not alter fatigue or mood")
		scene.free()
	# Stock may disappear during a normal meal: check again at completion.
	var scene = make_scene()
	var clock = scene.game_time
	var data = scene.resident_data
	var view = scene.resident_view
	stock = scene.settlement_storage
	data.hunger = 75
	view._process(20.0)
	stock.try_consume(ResourceType.Type.FOOD, 10)
	clock.advance(30.0)
	check(data.activity == Activity.Type.IDLE and data.hunger == 77 and stock.get_amount(ResourceType.Type.FOOD) == 0, "Depleted during meal gets no free hunger reduction")
	scene.free()
	# Restocking during the short attempt starts a full 30-minute meal.
	scene = make_scene()
	clock = scene.game_time
	data = scene.resident_data
	view = scene.resident_view
	stock = scene.settlement_storage
	stock.try_consume(ResourceType.Type.FOOD, 10)
	data.hunger = 75
	view._process(20.0)
	clock.advance(4.0)
	key(KEY_F11)
	clock.advance(29.0)
	check(data.activity == Activity.Type.EATING and stock.get_amount(ResourceType.Type.FOOD) == 5, "Restocking short attempt does not grant instant meal")
	clock.advance(1.0)
	check(stock.get_amount(ResourceType.Type.FOOD) == 4 and data.hunger < 70, "Full meal after mid-attempt restock succeeds")
	scene.free()
	# Night cancels without consuming food.
	scene = make_scene()
	clock = scene.game_time
	data = scene.resident_data
	view = scene.resident_view
	stock = scene.settlement_storage
	clock.debug_next_phase()
	clock.debug_next_phase()
	data.hunger = 75
	view._process(20.0)
	clock.total_minutes = 1379
	clock.advance(1.0)
	check(scene.resident_intents.current_intent.reason_id == &"night_home" and stock.get_amount(ResourceType.Type.FOOD) == 10, "Interrupted meal consumes nothing")
	scene.free()
	paused = false
	print("Storage checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
