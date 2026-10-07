extends Node
const GameLogger = preload("res://scripts/game_logger.gd")
var game_logger = GameLogger.new()
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
const GroundResources = preload("res://scripts/ground_resources.gd")
const GroundView = preload("res://scripts/ground_resource_view_2d.gd")
var ground_resources = GroundResources.new()
var _ground_views: Dictionary = {}
var logistics = LogisticsController.new()
var logistics_label: Label
var warehouse_food_label: Label
const Balance = preload("res://scripts/balance_config.gd")
const Production = preload("res://scripts/gatherer_production.gd")
var production = Production.new()
var gatherer_hut_data: BuildingData
var production_label: Label
var warehouse_data: BuildingData
var food_label: Label
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingDefinition = preload("res://scripts/building_definition.gd")
var buildings: Array[BuildingInstance] = []
var placement = preload("res://scripts/building_placement.gd").new()
var construction_panel: PanelContainer
var placement_input: Node
var kitchen_data: BuildingData
var world_locations = WorldLocations2D.new()
const ResidentFactory = preload("res://scripts/resident_factory.gd")
const ResidentGenerator = preload("res://scripts/resident_generator.gd")
const ResidentRuntime = preload("res://scripts/resident_runtime.gd")
const LocationView = preload("res://scenes/world_location_view_2d.tscn")
const WanderTarget = preload("res://scripts/wander_target.gd")
const SocialWorld = preload("res://scripts/social_world.gd")
var social_world = SocialWorld.new()
const PlayerControl = preload("res://scripts/player_control.gd")
var player_control = PlayerControl.new()
const InteractionService = preload("res://scripts/interaction_service.gd")
const InteractionTargets2D = preload("res://scripts/interaction_targets_2d.gd")
const InteractionMenu = preload("res://scripts/interaction_menu.gd")
var interactions = InteractionService.new()
var interaction_targets = InteractionTargets2D.new()
var interaction_menu: PanelContainer
var _ground_ids: Dictionary = {}
var _next_ground_id := 1
var residents: Array[ResidentData] = []
var resident_runtimes: Array[ResidentRuntime] = []
var population_label: Label
@onready var game_time = $GameTime
@onready var field = $World/Field
@onready var resident_selection = $ResidentSelection
var clock_label: Label
var phase_label: Label
var pause_button: Button
var speed_buttons: Array[Button] = []

func _ready() -> void:
	game_logger.setup(game_time)
	interactions.control = player_control
	for system in [social_world, ground_resources, logistics, production]:
		system.logger = game_logger
	$HUD/ResidentCard.bind_selection(resident_selection)
	$HUD/BuildingCard.bind_selection(resident_selection)
	_create_test_kitchen()
	_create_test_warehouse()
	_create_test_gatherer_hut()
	# Account for the elapsed work minute before residents choose their next action.
	add_child(production)
	production.setup(game_time, gatherer_hut_data, residents, world_locations, _production_position_2d)
	_create_test_residents()
	player_control.logger = game_logger
	player_control.setup(residents, buildings)
	$HUD/ResidentCard.bind_control(player_control)
	resident_selection.selection_changed.connect(_update_selection)
	production.work_assignment_provider = _committed_work_assignment
	for runtime in resident_runtimes:
		player_control.register_intents(runtime.data.id, runtime.intents)
		player_control.register_commands(runtime.data.id, runtime.commands)
		player_control.register_assignments(runtime.data.id, runtime.assignments)
		runtime.decision.work_available = _work_available.bind(runtime)
		runtime.decision.work_request = _request_work.bind(runtime)
		runtime.schedule.work_decision = runtime.decision.request_decision
	add_child(social_world)
	social_world.position_provider = _resident_position_2d
	for runtime in resident_runtimes:
		social_world.register(runtime)
		runtime.builder.position_provider = _production_position_2d
		runtime.builder.cargo_dropped.connect(_drop_cargo.bind(runtime))
		runtime.social.world = social_world
		runtime.assignments.bind_social_world()
		runtime.wander.target_provider = _wander_target_2d.bind(runtime.data.id)
		runtime.wander.target_available = _wander_available_2d.bind(runtime.data.id)
	_build_hud()
	interaction_menu = InteractionMenu.new()
	interaction_menu.service = interactions
	$HUD.add_child(interaction_menu)
	add_child(ground_resources)
	ground_resources.setup(game_time)
	ground_resources.added.connect(_show_ground_resource)
	ground_resources.removed.connect(_remove_ground_resource)
	_configure_logistics()
	if game_time.get_phase() == "День":
		for runtime in resident_runtimes:
			# Early schedule setup precedes work-source registration; hand ownership to AI.
			runtime.intents.clear_reason(&"day_work")
			runtime.decision.request_decision("startup_work")
	production.changed.connect(_update_production)
	gatherer_hut_data.resources.changed.connect(_on_hut_resources_changed)
	_update_production()
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
	_setup_construction()

func _build_hud() -> void:
	var panel = preload("res://scripts/prototype_hud.gd").new()
	panel.name = "DebugPanel"
	panel.position = Vector2(16, 16)
	$HUD.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text = "Village Sim"
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	header.add_child(title)
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 20)
	header.add_child(clock_label)
	phase_label = Label.new()
	phase_label.custom_minimum_size.x = 60
	header.add_child(phase_label)
	var collapse_button := Button.new()
	header.add_child(collapse_button)
	var extended := VBoxContainer.new()
	extended.name = "ExtendedContent"
	column.add_child(extended)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	extended.add_child(row)
	panel.configure(extended, collapse_button)
	pause_button = Button.new()
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_toggle_pause)
	row.add_child(pause_button)
	for multiplier in game_time.SUPPORTED_SPEEDS:
		var button := Button.new()
		button.text = "x%d" % multiplier
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(game_time.set_speed.bind(multiplier))
		row.add_child(button)
		speed_buttons.append(button)
	population_label = Label.new()
	population_label.text = "Жителей: %d" % residents.size()
	extended.add_child(population_label)
	production_label = Label.new()
	extended.add_child(production_label)
	warehouse_food_label = Label.new()
	extended.add_child(warehouse_food_label)
	food_label = Label.new()
	extended.add_child(food_label)
	logistics_label = Label.new()
	extended.add_child(logistics_label)
	var help := Label.new()
	help.text = "WASD / стрелки — камера\nПробел — пауза • 1 / 2 / 4 — скорость\nЛКМ — выбор • ПКМ по земле — приказ • ПКМ по объекту — действия"
	extended.add_child(help)
	var debug_help := Label.new()
	debug_help.text = "Shift+1 +1ч | Shift+2 +6ч | Shift+3 следующая фаза\nShift+4 +25 голода | Shift+5 усталость 100\nShift+6 голод 75 | Shift+7 голод 100\nShift+8 +1 еды в кухню | Shift+9 логистика"
	debug_help.add_theme_font_size_override("font_size", 14)
	extended.add_child(debug_help)
	_update_pause()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_SPACE:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event.shift_pressed:
		match event.physical_keycode:
			KEY_1: game_time.debug_skip_minutes(60)
			KEY_2: game_time.debug_skip_minutes(360)
			KEY_3: game_time.debug_next_phase()
			KEY_4: _debug_add_hunger()
			KEY_5: _debug_set_fatigue()
			KEY_6: _debug_set_hunger(75)
			KEY_7: _debug_set_hunger(100)
			KEY_8: kitchen_data.resources.add(ResourceType.Type.FOOD, 1)
			KEY_9: logistics.recalculate()
			_: return
	else:
		match event.physical_keycode:
			KEY_1: game_time.set_speed(1)
			KEY_2: game_time.set_speed(2)
			KEY_4: game_time.set_speed(4)
			_: return
	get_viewport().set_input_as_handled()

func _debug_add_hunger() -> void:
	var selected = resident_selection.selected_resident
	if selected != null:
		selected.hunger += 25

func _debug_set_fatigue() -> void:
	var selected = resident_selection.selected_resident
	if selected != null:
		selected.fatigue = 100

func _debug_set_hunger(value: int = 75) -> void:
	var selected = resident_selection.selected_resident
	if selected != null:
		selected.hunger = value

func _update_food(resource: ResourceType.Type, amount: int) -> void:
	if resource == ResourceType.Type.FOOD:
		food_label.text = "Еда в кухне: %d/%d" % [amount, kitchen_data.resources.get_capacity(ResourceType.Type.FOOD)]
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
		speed_buttons[index].set_pressed_no_signal(game_time.SUPPORTED_SPEEDS[index] == multiplier)

func _create_test_residents() -> void:
	var generator = ResidentGenerator.new(42, "settlement")
	residents.append(ResidentFactory.create(
		"resident_001", "Степан", 30, Profession.Type.PORTER,
		[preload("res://assets/traits/hardworking.tres"),
		preload("res://assets/traits/sociable.tres"),
		preload("res://assets/traits/stubborn.tres")],
		20, 35, 65, &"home_stepan", warehouse_data.id))
	var home_ids = [&"home_anna", &"home_fedor", &"home_marina"]
	for index in range(3):
		var data = generator.generate(["Анна", "Фёдор", "Марина"][index])
		data.home_location_id = home_ids[index]
		if index == 1:
			data.profession = Profession.Type.GATHERER
			data.work_location_id = gatherer_hut_data.id
		residents.append(data)
	var home_names = ["Дом Степана", "Дом Анны", "Дом Фёдора", "Дом Марины"]
	var home_positions = [Vector2(-300, -120), Vector2(-100, -200), Vector2(100, -200), Vector2(300, -120)]
	var start_positions = [Vector2(120, 80), Vector2(220, 100), Vector2(-100, 100), Vector2(0, 180)]
	for index in range(residents.size()):
		var data = residents[index]
		assert(find_resident(data.id) == data, "Resident IDs must be unique")
		var home_building = BuildingData.new(data.home_location_id, home_names[index], BuildingType.Type.HOME)
		home_building.position = home_positions[index]
		buildings.append(home_building)
		var home = WorldLocation.new(data.home_location_id, home_names[index])
		var home_view = LocationView.instantiate()
		home_view.name = String(home.id)
		$World.add_child(home_view)
		home_view.position = home_positions[index]
		home_view.building_data = home_building
		home_view.setup(home)
		world_locations.register(home, home_view)
		interactions.register_target(home.id, home.display_name, home, world_locations.get_position.bind(home.id))
		interaction_targets.register(home.id, home_view)
		var view = ResidentView2D.instantiate()
		view.z_index = 1 # Residents remain visible at buildings placed later in the world tree.
		view.name = "ResidentView_" + data.id
		view.setup(data)
		view.position = start_positions[index]
		view.selection_requested.connect(resident_selection.select)
		view.set_time_speed(game_time.speed_multiplier)
		game_time.speed_changed.connect(view.set_time_speed)
		$World.add_child(view)
		var runtime = ResidentRuntime.new()
		runtime.name = data.id
		$Residents.add_child(runtime)
		resident_runtimes.append(runtime)
		runtime.logger = game_logger
		runtime.setup(data, view, game_time, world_locations, buildings)
		interactions.register_target(StringName(data.id), data.resident_name, data, _resident_interaction_position.bind(data.id), [&"resident"])
		interaction_targets.register(StringName(data.id), view)

func _resident_interaction_position(resident_id: String) -> Vector2:
	return _resident_position_2d(resident_id) + Vector2(36, 0)

func _wander_available_2d(resident_id: String) -> bool:
	return field.FIELD.has_point(_resident_position_2d(resident_id))

func _wander_target_2d(rng: RandomNumberGenerator, resident_id: String):
	return WanderTarget.nearby(_resident_position_2d(resident_id), rng, field.FIELD)

func _resident_position_2d(resident_id: String) -> Vector2:
	var runtime = social_world.get_runtime(resident_id)
	return runtime.view.global_position if runtime != null else Vector2.ZERO

func _production_position_2d(resident_id: String) -> Variant:
	var runtime = social_world.get_runtime(resident_id)
	return runtime.view.global_position if runtime != null else null

func find_resident(resident_id: String) -> ResidentData:
	for data in residents:
		if data.id == resident_id:
			return data
	return null

func get_resident_runtime(data: ResidentData) -> ResidentRuntime:
	for runtime in resident_runtimes:
		if runtime.data == data:
			return runtime
	return null

func _update_selection() -> void:
	if is_instance_valid(interaction_menu): interaction_menu.hide()
	for runtime in resident_runtimes:
		if is_instance_valid(runtime.view): runtime.view.set_selected(runtime.data == resident_selection.selected_resident)
	for building in buildings:
		var view = world_locations.get_view(building.id)
		if view != null: view.set_selected(building == resident_selection.selected_building)

func _committed_work_assignment(resident_id: String) -> Dictionary:
	var runtime = get_resident_runtime(find_resident(resident_id))
	return runtime.decision.get_committed_work_assignment() if runtime != null and is_instance_valid(runtime.decision) else {}

func _work_available(runtime: ResidentRuntime) -> bool:
	match runtime.data.profession:
		Profession.Type.PORTER:
			return logistics.executor_available() and logistics.has_available_job(runtime.data.id)
		Profession.Type.BUILDER: return runtime.builder.has_work()
		Profession.Type.GATHERER: return production.can_work(runtime.data)
		_: return false

func _request_work(runtime: ResidentRuntime) -> bool:
	match runtime.data.profession:
		Profession.Type.PORTER: return _request_haul_work(runtime)
		Profession.Type.BUILDER: return runtime.builder.request_work()
		Profession.Type.GATHERER: return runtime.schedule.request_work()
		_: return false

func _configure_logistics() -> void:
	logistics.setup(warehouse_data, kitchen_data, null)
	logistics.add_production_source(gatherer_hut_data)
	for runtime in resident_runtimes: logistics.register_resident(runtime.data)
	logistics.cargo_dropped.connect(_drop_executor_cargo)
	logistics.job_cancelled.connect(_on_job_cancelled)
	logistics.changed.connect(_update_logistics)
	logistics.bind_world(game_time, world_locations)
	logistics.recalculate()

func _drop_executor_cargo(resource: ResourceType.Type, amount: int) -> void:
	var runtime = get_resident_runtime(logistics.executor_resident())
	if runtime != null: _drop_cargo(resource, amount, runtime)

func _on_job_cancelled(resident_id: String) -> void:
	var runtime = get_resident_runtime(find_resident(resident_id))
	if runtime != null: _on_haul_cancelled(resident_id, runtime)

func _request_haul_work(runtime: ResidentRuntime) -> bool:
	if not logistics.use_executor(runtime.data, game_time, world_locations, runtime.intents, runtime.schedule): return false
	logistics.recalculate()
	var job = logistics.claim_best_job(runtime.data.id)
	if job == null: return false
	if logistics.start_claimed_job(job, runtime.data.id): return true
	logistics.cancel_job(job)
	return false

func _on_haul_cancelled(resident_id: String, runtime: ResidentRuntime) -> void:
	if resident_id == runtime.data.id and is_instance_valid(runtime.decision):
		runtime.decision.call_deferred("request_decision", "job_cancelled")

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
		var hit_building: BuildingInstance = _building_hit(event.position)
		if hit_building != null: resident_selection.select_building(hit_building)
		else: resident_selection.clear()
	else:
		var selected = resident_selection.selected_resident
		if selected != null:
			var target_id: StringName = interaction_targets.hit(event.position)
			if not target_id.is_empty(): interaction_menu.open_for([selected.id], target_id, event.position)
			else:
				interaction_menu.hide()
				player_control.move_to(selected.id, field.to_global(field_point))
	get_viewport().set_input_as_handled()

func _create_test_kitchen() -> void:
	kitchen_data = BuildingData.new(&"communal_kitchen_01", "Общая кухня", BuildingType.Type.FOOD)
	kitchen_data.resources.set_capacity(ResourceType.Type.FOOD, Balance.KITCHEN_FOOD_CAPACITY)
	buildings.append(kitchen_data)
	# Same ID links two distinct data objects: building meaning and world place.
	var location = WorldLocation.new(kitchen_data.id, kitchen_data.display_name)
	var view = BuildingView2D.instantiate()
	view.name = "CommunalKitchen"
	view.setup(kitchen_data)
	view.position = Vector2(-280, 240)
	kitchen_data.position = view.position
	$World.add_child(view)
	world_locations.register(location, view)
	interactions.register_building(kitchen_data, world_locations.get_position.bind(location.id))
	interaction_targets.register(location.id, view)

func _update_warehouse_food(resource: ResourceType.Type, amount: int) -> void:
	if resource == ResourceType.Type.FOOD:
		warehouse_food_label.text = "Еда на складе: %d/20" % amount
		_update_logistics()

func _create_test_warehouse() -> void:
	warehouse_data = BuildingData.new(&"warehouse_01", "Склад", BuildingType.Type.STORAGE)
	warehouse_data.resources.set_capacity(ResourceType.Type.FOOD, 20)
	warehouse_data.resources.add(ResourceType.Type.FOOD, 10)
	warehouse_data.resources.set_capacity(ResourceType.Type.WOOD, 50)
	warehouse_data.resources.add(ResourceType.Type.WOOD, 50)
	buildings.append(warehouse_data)
	var location = WorldLocation.new(warehouse_data.id, warehouse_data.display_name)
	var view = BuildingView2D.instantiate()
	view.name = "Warehouse"
	view.setup(warehouse_data)
	view.position = Vector2(300, 240)
	warehouse_data.position = view.position
	$World.add_child(view)
	world_locations.register(location, view)
	interactions.register_building(warehouse_data, world_locations.get_position.bind(location.id))
	interaction_targets.register(location.id, view)

func _create_test_gatherer_hut() -> void:
	gatherer_hut_data = BuildingData.new(&"gatherer_hut_01", "Хижина собирателя", BuildingType.Type.GATHERER_HUT)
	gatherer_hut_data.resources.set_allowed_resource_types([ResourceType.Type.FOOD])
	gatherer_hut_data.resources.set_capacity(ResourceType.Type.FOOD, 5)
	buildings.append(gatherer_hut_data)
	var location = WorldLocation.new(gatherer_hut_data.id, gatherer_hut_data.display_name)
	var view = BuildingView2D.instantiate()
	view.name = "GathererHut"
	view.setup(gatherer_hut_data)
	view.position = Vector2(380, -240)
	gatherer_hut_data.position = view.position
	$World.add_child(view)
	world_locations.register(location, view)
	interactions.register_building(gatherer_hut_data, world_locations.get_position.bind(location.id))
	interaction_targets.register(location.id, view)

func _on_hut_resources_changed(_resource: ResourceType.Type, _amount: int) -> void:
	logistics.recalculate()
	_update_production()

func _update_production() -> void:
	production_label.text = "Хижина собирателя: FOOD %d/5\nproduction progress %d/%d" % [gatherer_hut_data.resources.get_amount(ResourceType.Type.FOOD), gatherer_hut_data.production_progress, Balance.GATHERER_WORK_MINUTES_PER_FOOD]

func _update_logistics() -> void:
	if logistics_label == null:
		return
	var source = warehouse_data.resources
	var destination = kitchen_data.resources
	var summary := "Склад: %d/%d FOOD • зарезервировано на вывоз: %d\nКухня: %d/%d FOOD • зарезервировано под доставку: %d" % [source.get_amount(ResourceType.Type.FOOD), source.get_capacity(ResourceType.Type.FOOD), source.get_reserved_out(ResourceType.Type.FOOD), destination.get_amount(ResourceType.Type.FOOD), destination.get_capacity(ResourceType.Type.FOOD), destination.get_reserved_in(ResourceType.Type.FOOD)]
	var job = logistics.current_job
	if job == null or not job.is_active():
		for offered_job in logistics.jobs:
			if offered_job.is_active():
				job = offered_job
				break
	if job == null or not job.is_active():
		summary += "\nЛогистика: нет активной доставки"
	elif find_resident(job.assigned_resident_id) != null:
		summary += "\nЛогистика: %s: доставить %d FOOD → %s" % [find_resident(job.assigned_resident_id).resident_name, job.amount, world_locations.get_location(job.destination_location_id).display_name]
		summary += " • " + preload("res://scripts/haul_job.gd").State.keys()[job.state]
	else:
		summary += "\nЛогистика: доступна доставка FOOD (приоритет %d)" % job.priority
	for active_job in logistics.jobs:
		if not active_job.is_active(): continue
		var source_name: String = world_locations.get_location(active_job.source_location_id).display_name
		var destination_name: String = world_locations.get_location(active_job.destination_location_id).display_name
		summary += "\n%s → %s • %d FOOD • priority: %.0f" % [source_name, destination_name, active_job.amount, active_job.priority]
	logistics_label.text = summary

func _drop_cargo(resource: ResourceType.Type, amount: int, runtime: ResidentRuntime) -> void:
	ground_resources.create_drop(resource, amount, runtime.view.global_position)

func _show_ground_resource(drop) -> void:
	var view = GroundView.new()
	$World.add_child(view)
	view.setup(drop)
	_ground_views[drop] = view
	var id := StringName("ground_%d" % _next_ground_id)
	_next_ground_id += 1
	_ground_ids[drop] = id
	interactions.register_target(id, ResourceType.display_name(drop.resource_type) + " на земле", drop, _ground_position.bind(drop), [&"ground_resource"])
	interaction_targets.register(id, view)

func _ground_position(drop: RefCounted) -> Vector2: return drop.world_position

func _remove_ground_resource(drop) -> void:
	var id: StringName = _ground_ids.get(drop, &"")
	interactions.remove_target(id)
	interaction_targets.remove(id)
	_ground_ids.erase(drop)
	var view = _ground_views.get(drop)
	if is_instance_valid(view):
		view.queue_free()
	_ground_views.erase(drop)

func _setup_construction() -> void:
	placement.setup(buildings)
	placement.logger = game_logger
	placement.placed.connect(_show_placed_building)
	construction_panel = preload("res://scripts/construction_panel.gd").new()
	$HUD.add_child(construction_panel)
	var definitions: Array = []
	for category in [BuildingType.Type.HOME, BuildingType.Type.STORAGE, BuildingType.Type.FOOD, BuildingType.Type.GATHERER_HUT]:
		definitions.append(BuildingDefinition.for_type(category))
	construction_panel.setup(definitions)
	construction_panel.definition_selected.connect(_select_building_definition)
	# Added last: unhandled world clicks reach this adapter before resident selection.
	placement_input = preload("res://scripts/building_placement_input.gd").new()
	add_child(placement_input)
	placement_input.setup(placement, field, $World)

func _select_building_definition(definition: BuildingDefinition) -> void:
	interaction_menu.hide()
	placement.select(definition)

func _show_placed_building(building: BuildingInstance) -> void:
	var view = BuildingView2D.instantiate()
	view.name = String(building.id)
	view.position = building.position
	$World.add_child(view)
	view.setup(building)
	world_locations.register(WorldLocation.new(building.id, building.display_name), view)
	# The same registry/view gains functionality after the one-way state transition.
	building.construction_changed.connect(_activate_completed_building.bind(building))
	for runtime in resident_runtimes: runtime.builder.register_building(building)

func _activate_completed_building(building: BuildingInstance) -> void:
	if not building.is_built(): return
	building.construction_changed.disconnect(_activate_completed_building.bind(building))
	match building.type:
		BuildingType.Type.STORAGE:
			building.resources.set_capacity(ResourceType.Type.FOOD, 20)
			building.resources.set_capacity(ResourceType.Type.WOOD, 50)
			logistics.add_warehouse(building)
		BuildingType.Type.FOOD:
			building.resources.set_capacity(ResourceType.Type.FOOD, 20)
			logistics.add_kitchen(building)
		BuildingType.Type.GATHERER_HUT:
			building.resources.set_allowed_resource_types([ResourceType.Type.FOOD])
			building.resources.set_capacity(ResourceType.Type.FOOD, 5)
			production.additional_buildings.append(building)
			logistics.add_production_source(building)
	building.resources.changed.connect(_on_hut_resources_changed)
	player_control.register_building(building)
	interactions.register_building(building, world_locations.get_position.bind(building.id))
	interaction_targets.register(building.id, world_locations.get_view(building.id))
	for runtime in resident_runtimes: runtime.needs.register_food_building(building)
	logistics.recalculate()


func _building_hit(screen_position: Vector2) -> BuildingInstance:
	# Exact resident hits have already consumed their click before Main.
	# Among buildings, later registry entries win (same order as world visuals).
	for index in range(buildings.size() - 1, -1, -1):
		var building := buildings[index]
		var view = world_locations.get_view(building.id)
		if view != null and view.selection_hit(screen_position): return building
	return null
