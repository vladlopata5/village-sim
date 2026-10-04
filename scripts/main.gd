extends Node
const ResidentData = preload("res://scripts/resident_data.gd")
const ResidentView2D = preload("res://scenes/resident_view_2d.tscn")
const WorldLocation = preload("res://scripts/world_location.gd")
const WorldLocations2D = preload("res://scripts/world_locations_2d.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const BuildingView2D = preload("res://scenes/building_view_2d.tscn")
const ResourceType = preload("res://scripts/resource_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const LogisticsController = preload("res://scripts/logistics_controller.gd")
var logistics = LogisticsController.new()
var logistics_label: Label
var warehouse_food_label: Label
var warehouse_data: BuildingData
var food_label: Label
var buildings: Array[BuildingData] = []
var kitchen_data: BuildingData
var world_locations = WorldLocations2D.new()
var resident_data: ResidentData
var resident_view: Node2D
@onready var game_time = $GameTime
@onready var field = $World/Field
@onready var resident_selection = $ResidentSelection
@onready var resident_schedule = $ResidentScheduleController
@onready var resident_intents = $ResidentIntentController
var clock_label: Label
var phase_label: Label
var pause_button: Button
var speed_buttons: Array[Button] = []

func _ready() -> void:
	$HUD/ResidentCard.bind_selection(resident_selection)
	_create_test_kitchen()
	_create_test_warehouse()
	_create_test_resident()
	$ResidentNeedsController.setup(game_time, resident_data, buildings, world_locations, resident_intents, resident_schedule)
	_build_hud()
	logistics.setup(warehouse_data, kitchen_data, resident_data)
	logistics.changed.connect(_update_logistics)
	logistics.recalculate()
	_update_logistics()
	warehouse_data.resources.changed.connect(_update_warehouse_food)
	_update_warehouse_food(ResourceType.Type.FOOD, warehouse_data.resources.get_amount(ResourceType.Type.FOOD))
	kitchen_data.resources.changed.connect(_update_food)
	_update_food(ResourceType.Type.FOOD, kitchen_data.resources.get_amount(ResourceType.Type.FOOD))
	game_time.minute_changed.connect(_update_clock)
	game_time.phase_changed.connect(field.show_phase)
	game_time.phase_changed.connect(_update_phase)
	game_time.speed_changed.connect(_update_speed)
	_update_clock(game_time.total_minutes)
	_update_phase(game_time.get_phase())
	field.show_phase(game_time.get_phase())
	_update_speed(game_time.speed_multiplier)

func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	$HUD.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "Village Sim — временный прототип"
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 24)
	row.add_child(clock_label)
	phase_label = Label.new()
	phase_label.custom_minimum_size.x = 80
	row.add_child(phase_label)
	pause_button = Button.new()
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_toggle_pause)
	row.add_child(pause_button)
	for multiplier in [1, 2, 4]:
		var button := Button.new()
		button.text = "x%d" % multiplier
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(game_time.set_speed.bind(multiplier))
		row.add_child(button)
		speed_buttons.append(button)
	warehouse_food_label = Label.new()
	column.add_child(warehouse_food_label)
	food_label = Label.new()
	column.add_child(food_label)
	logistics_label = Label.new()
	column.add_child(logistics_label)
	var help := Label.new()
	help.text = "WASD / стрелки — камера\nПробел — пауза • 1 / 2 / 4 — скорость\nЛКМ — выбор • ПКМ по полю — перемещение (утром и вечером)"
	column.add_child(help)
	var debug_help := Label.new()
	debug_help.text = "F6 +1ч | F7 +6ч | F8 следующая фаза | F9 +25 голода | F10 голод 75 | F11 +1 еды в кухню\nF12 пересчитать логистику"
	debug_help.add_theme_font_size_override("font_size", 14)
	column.add_child(debug_help)
	_update_pause()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE: _toggle_pause()
		KEY_1: game_time.set_speed(1)
		KEY_2: game_time.set_speed(2)
		KEY_4: game_time.set_speed(4)
		KEY_F6: game_time.debug_skip_minutes(60)
		KEY_F7: game_time.debug_skip_minutes(360)
		KEY_F8: game_time.debug_next_phase()
		KEY_F9: _debug_add_hunger()
		KEY_F10: _debug_set_hunger()
		KEY_F11: kitchen_data.resources.add(ResourceType.Type.FOOD, 1)
		KEY_F12: logistics.recalculate()
		_: return
	get_viewport().set_input_as_handled()

func _debug_add_hunger() -> void:
	var selected = resident_selection.selected_resident
	if selected != null:
		selected.hunger += 25

func _debug_set_hunger() -> void:
	var selected = resident_selection.selected_resident
	if selected != null:
		selected.hunger = 75

func _update_food(resource: ResourceType.Type, amount: int) -> void:
	if resource == ResourceType.Type.FOOD:
		food_label.text = "Еда в кухне: %d" % amount
		_update_logistics()

func _toggle_pause() -> void:
	game_time.toggle_pause()
	_update_pause()

func _update_pause() -> void:
	pause_button.text = "Продолжить" if get_tree().paused else "Пауза"

func _update_clock(_total_minutes: int) -> void:
	clock_label.text = game_time.get_clock_text()

func _update_phase(phase: String) -> void:
	phase_label.text = phase

func _update_speed(multiplier: int) -> void:
	for index in range(speed_buttons.size()):
		speed_buttons[index].set_pressed_no_signal([1, 2, 4][index] == multiplier)

func _create_test_resident() -> void:
	resident_data = ResidentData.new("resident_001", "Степан", 30, Profession.Type.PORTER)
	var home = WorldLocation.new(&"home_stepan", "Дом Степана")
	$World/HomePoint.setup(home)
	world_locations.register(home, $World/HomePoint)
	resident_data.home_location_id = home.id
	resident_data.work_location_id = warehouse_data.id
	resident_data.hunger = 20
	resident_data.fatigue = 35
	resident_data.mood = 65
	resident_data.traits.assign([
		preload("res://assets/traits/hardworking.tres"),
		preload("res://assets/traits/sociable.tres"),
		preload("res://assets/traits/stubborn.tres"),
	])
	var view = ResidentView2D.instantiate()
	view.setup(resident_data)
	view.position = Vector2(120, 80)
	view.selection_requested.connect(resident_selection.select)
	view.set_time_speed(game_time.speed_multiplier)
	game_time.speed_changed.connect(view.set_time_speed)
	resident_view = view
	$World.add_child(view)
	resident_intents.setup(resident_data)
	resident_intents.intent_changed.connect(view.apply_intent)
	view.intent_completed.connect(resident_intents.report_arrival)
	resident_schedule.setup(game_time, world_locations, resident_intents)
	$ResidentHunger.setup(game_time, resident_data)

func _unhandled_input(event: InputEvent) -> void:
	# UI and resident selection consume their clicks before this parent.
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var field_point: Vector2 = field.get_global_transform_with_canvas().affine_inverse() * event.position
	if not field.FIELD.has_point(field_point):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		resident_selection.clear()
	elif is_instance_valid(resident_view) and resident_selection.selected_resident == resident_view.resident_data:
		resident_schedule.request_manual_move(field.to_global(field_point))
	get_viewport().set_input_as_handled()

func _create_test_kitchen() -> void:
	kitchen_data = BuildingData.new(&"communal_kitchen_01", "Общая кухня", BuildingType.Type.FOOD)
	kitchen_data.resources.set_capacity(ResourceType.Type.FOOD, 5)
	buildings.append(kitchen_data)
	# Same ID links two distinct data objects: building meaning and world place.
	var location = WorldLocation.new(kitchen_data.id, kitchen_data.display_name)
	var view = BuildingView2D.instantiate()
	view.name = "CommunalKitchen"
	view.setup(kitchen_data)
	view.position = Vector2(-280, 240)
	$World.add_child(view)
	world_locations.register(location, view)

func _update_warehouse_food(resource: ResourceType.Type, amount: int) -> void:
	if resource == ResourceType.Type.FOOD:
		warehouse_food_label.text = "Еда на складе: %d" % amount
		_update_logistics()

func _create_test_warehouse() -> void:
	warehouse_data = BuildingData.new(&"warehouse_01", "Склад", BuildingType.Type.STORAGE)
	warehouse_data.resources.set_capacity(ResourceType.Type.FOOD, 20)
	warehouse_data.resources.add(ResourceType.Type.FOOD, 10)
	buildings.append(warehouse_data)
	var location = WorldLocation.new(warehouse_data.id, warehouse_data.display_name)
	var view = BuildingView2D.instantiate()
	view.name = "Warehouse"
	view.setup(warehouse_data)
	view.position = Vector2(300, 240)
	$World.add_child(view)
	world_locations.register(location, view)

func _update_logistics() -> void:
	if logistics_label == null:
		return
	var source = warehouse_data.resources
	var destination = kitchen_data.resources
	var summary := "Склад: %d/%d FOOD • зарезервировано на вывоз: %d\nКухня: %d/%d FOOD • зарезервировано под доставку: %d" % [source.get_amount(ResourceType.Type.FOOD), source.get_capacity(ResourceType.Type.FOOD), source.get_reserved_out(ResourceType.Type.FOOD), destination.get_amount(ResourceType.Type.FOOD), destination.get_capacity(ResourceType.Type.FOOD), destination.get_reserved_in(ResourceType.Type.FOOD)]
	var job = logistics.current_job
	if job == null or not job.is_active():
		summary += "\nЛогистика: нет активной доставки"
	elif job.assigned_resident_id == resident_data.id:
		summary += "\nЛогистика: %s: доставить %d FOOD → %s" % [resident_data.resident_name, job.amount, kitchen_data.display_name]
	else:
		summary += "\nЛогистика: доставка зарезервирована, ожидает носильщика"
	logistics_label.text = summary
