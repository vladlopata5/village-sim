extends Node
## Shared simulation assembly. Only Main3D is playable.
const GameLogger = preload("res://scripts/game_logger.gd")
var game_logger = GameLogger.new()
const ResidentData = preload("res://scripts/resident_data.gd")
const WorldLocation = preload("res://scripts/world_location.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const LogisticsController = preload("res://scripts/logistics_controller.gd")
const DropResult = preload("res://scripts/cargo_drop_result.gd")
const GroundResources = preload("res://scripts/ground_resources.gd")
var ground_resources = GroundResources.new()
var food_availability = preload("res://scripts/food_availability.gd").new()
var _ground_views: Dictionary = {}
var logistics = LogisticsController.new()
const Balance = preload("res://scripts/balance_config.gd")
const Production = preload("res://scripts/gatherer_production.gd")
var production = Production.new()
var gatherer_hut_data: BuildingInstance
var warehouse_data: BuildingData
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingDefinition = preload("res://scripts/building_definition.gd")
var buildings: Array[BuildingInstance] = []
var fallback_housing = preload("res://scripts/fallback_housing.gd").new()
var placement = preload("res://scripts/building_placement.gd").new()
var construction_panel: PanelContainer
var kitchen_data: BuildingInstance
const ResidentFactory = preload("res://scripts/resident_factory.gd")
const ResidentGenerator = preload("res://scripts/resident_generator.gd")
const ResidentRuntime = preload("res://scripts/resident_runtime.gd")
const WanderTarget = preload("res://scripts/wander_target.gd")
const SocialWorld = preload("res://scripts/social_world.gd")
var social_world = SocialWorld.new()
var social_events = preload("res://scripts/social_event_service.gd").new()
var social_feed: PanelContainer
const PlayerControl = preload("res://scripts/player_control.gd")
var player_control = PlayerControl.new()
const InteractionService = preload("res://scripts/interaction_service.gd")
const InteractionMenu = preload("res://scripts/interaction_menu.gd")
var interactions = InteractionService.new()
var interaction_menu: PanelContainer
var _ground_ids: Dictionary = {}
var residents: Array[ResidentData] = []
var resident_runtimes: Array[ResidentRuntime] = []
var decision_dispatcher: Node
@onready var game_time = $GameTime
@onready var field = $World/Field
@onready var resident_selection = $ResidentSelection

var world_locations: RefCounted
func _ready() -> void:
	game_logger.setup(game_time)
	interactions.control = player_control
	for system in [social_world, ground_resources, logistics, production]:
		system.logger = game_logger
	resident_card_view().bind_selection(resident_selection)
	building_card_view().bind_selection(resident_selection)
	fallback_housing.setup(buildings,world_locations)
	_create_starting_buildings()
	food_availability.setup(buildings, world_locations)
	# Account for the elapsed work minute before residents choose their next action.
	add_child(production)
	production.setup(game_time, gatherer_hut_data, residents, world_locations, _production_position_2d)
	_create_test_residents()
	player_control.logger = game_logger
	player_control.setup(residents, buildings)
	resident_card_view().bind_control(player_control)
	building_card_view().bind_control(player_control)
	resident_selection.selection_changed.connect(_update_selection)
	production.work_assignment_provider = _committed_work_assignment
	for runtime in resident_runtimes: _bind_resident_control(runtime)
	add_child(social_world)
	social_world.position_provider = _resident_position_2d
	for runtime in resident_runtimes: _bind_resident_social(runtime)
	add_child(social_events)
	social_events.logger = game_logger
	social_events.setup(social_world, game_time, buildings)
	social_feed = preload("res://scripts/social_feed.gd").new()
	social_feed.name = "SocialFeed"
	$HUD.add_child(social_feed)
	social_events.feed_message.connect(social_feed.add_message)
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
	game_time.phase_changed.connect(field.show_phase)
	field.show_phase(game_time.get_phase())
	_setup_construction()

func resident_card_view() -> Control: return $HUD/GameUI.resident_card
func building_card_view() -> Control: return $HUD/GameUI.building_card
func ui_input_context() -> RefCounted: return $HUD/GameUI.input_context
func _update_population() -> void: $HUD/GameUI.update_population(residents.size())

func _unhandled_key_input(event: InputEvent) -> void:
	var context = ui_input_context()
	if context != null and context.text_editing(): return
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

func _toggle_pause() -> void:
	game_time.toggle_pause()
	$HUD/GameUI.time_controls.refresh_pause()

func _create_test_residents() -> void:
	var generator = ResidentGenerator.new(42, "settlement")
	var starting_preferences := generator.generate_preferences()
	residents.append(ResidentFactory.create(
		"resident_001", "Степан", 30, Profession.Type.PORTER,
		generator.generate_traits(),
		20, 35, 65, _starting_home_id(0), warehouse_data.id, starting_preferences.liked, starting_preferences.disliked))
	for index in range(3):
		var data = generator.generate(["Анна", "Фёдор", "Марина"][index])
		data.home_location_id = _starting_home_id(index+1)
		if index == 1:
			data.profession = Profession.Type.GATHERER
			data.work_location_id = gatherer_hut_data.id if gatherer_hut_data != null else &""
		residents.append(data)
	# Source centers align physical footprint edges to BuildGrid 0.5 at world scale 1:25.
	var start_positions = [Vector2(120, 80), Vector2(220, 100), Vector2(-100, 100), Vector2(0, 180)]
	for index in range(residents.size()):
		var data = residents[index]
		assert(find_resident(data.id) == data, "Resident IDs must be unique")
		_create_starting_home(data,index)
		_create_resident_runtime(data,start_positions[index])

func _resident_interaction_position(resident_id: String) -> Vector2:
	return _resident_position_2d(resident_id) + Vector2(36, 0)

func _wander_available_2d(resident_id: String) -> bool:
	return field.FIELD.has_point(_resident_position_2d(resident_id))

func _wander_target_2d(rng: RandomNumberGenerator, resident_id: String):
	return WanderTarget.nearby(_resident_position_2d(resident_id), rng, field.FIELD)

func _resident_position_2d(resident_id: String) -> Vector2:
	var runtime = social_world.get_runtime(resident_id)
	return runtime.view.get_sim_position() if runtime != null else Vector2.ZERO

func _production_position_2d(resident_id: String) -> Variant:
	var runtime = social_world.get_runtime(resident_id)
	return runtime.view.get_sim_position() if runtime != null else null

func find_resident(resident_id: String) -> ResidentData:
	for data in residents:
		if data.id == resident_id:
			return data
	return null

func get_resident_runtime(data: ResidentData) -> ResidentRuntime:
	for runtime in resident_runtimes:
		if is_instance_valid(runtime) and runtime.data == data:
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
			return logistics.has_available_job(runtime.data.id)
		Profession.Type.BUILDER: return runtime.builder.has_work()
		Profession.Type.SAWYER: return runtime.self_logistics.has_work()
		Profession.Type.GATHERER: return runtime.self_logistics.has_work()
		_: return false

func _request_work(runtime: ResidentRuntime) -> bool:
	match runtime.data.profession:
		Profession.Type.PORTER: return _request_haul_work(runtime)
		Profession.Type.BUILDER: return runtime.builder.request_work()
		Profession.Type.SAWYER: return runtime.self_logistics.request_work()
		Profession.Type.GATHERER: return runtime.self_logistics.request_work()
		_: return false

func _configure_logistics() -> void:
	logistics.assignment_control = player_control
	player_control.building_unregistered.connect(logistics.remove_building)
	player_control.resident_unregistered.connect(_on_resident_unregistered)
	logistics.setup(warehouse_data, kitchen_data, null)
	if gatherer_hut_data != null: logistics.add_production_source(gatherer_hut_data)
	for runtime in resident_runtimes:
		_bind_resident_logistics(runtime)
	logistics.position_provider = _production_position_2d
	logistics.cargo_drop_handler = _drop_executor_cargo
	logistics.job_cancelled.connect(_on_job_cancelled)
	logistics.bind_world(game_time, world_locations)
	logistics.sources.bind_ground(ground_resources)
	logistics.sources.route_available = _resource_route_available
	logistics.sources.work_object_current = func(building): return building in buildings
	logistics.recalculate()

func _on_resident_unregistered(resident_id: String) -> void:
	if is_instance_valid(decision_dispatcher): decision_dispatcher.cancel(resident_id)
	logistics.unregister_resident(resident_id)

func _resource_route_available(_start: Vector2, _target: Vector2) -> bool: return true

func _drop_executor_cargo(resource: ResourceType.Type, amount: int, resident_id: String) -> int:
	var runtime = get_resident_runtime(find_resident(resident_id))
	return _drop_cargo(resource,amount,runtime) if runtime!=null else DropResult.Status.FAILED

func _on_job_cancelled(resident_id: String) -> void:
	var runtime = get_resident_runtime(find_resident(resident_id))
	if runtime != null: _on_haul_cancelled(resident_id, runtime)

func _request_haul_work(runtime: ResidentRuntime) -> bool:
	if not logistics.use_executor(runtime.data, game_time, world_locations, runtime.intents, runtime.schedule): return false
	var job = logistics.claim_best_job(runtime.data.id)
	if job == null: return false
	if logistics.start_claimed_job(job, runtime.data.id): return true
	logistics.cancel_job(job)
	return false

func _on_haul_cancelled(resident_id: String, runtime: ResidentRuntime) -> void:
	if resident_id == runtime.data.id and is_instance_valid(runtime.decision):
		runtime.decision.call_deferred("request_decision", "job_cancelled")

func _drop_cargo(_resource: ResourceType.Type, _amount: int, _runtime: ResidentRuntime) -> int:
	# The canonical presentation supplies geometry-aware placement.
	return DropResult.Status.FAILED

func _ground_position(drop: RefCounted) -> Vector2: return drop.world_position

func _remove_ground_resource(drop) -> void:
	var id: StringName = _ground_ids.get(drop, &"")
	interactions.remove_target(id)
	_ground_ids.erase(drop)
	var view = _ground_views.get(drop)
	if is_instance_valid(view):
		view.queue_free()
	_ground_views.erase(drop)

func _show_building(building: BuildingInstance) -> void:
	var view = _create_building_presentation(building)
	world_locations.register(WorldLocation.new(building.id, building.display_name), view)
	# The same registry/view gains functionality after the one-way state transition.
	building.construction_changed.connect(_activate_completed_building.bind(building))
	for runtime in resident_runtimes:
		runtime.recipe_work.register_building(building)
	if building.is_built(): _activate_completed_building(building)

func _activate_completed_building(building: BuildingInstance) -> void:
	if not building.is_built(): return
	building.construction_changed.disconnect(_activate_completed_building.bind(building))
	match building.type:
		BuildingType.Type.STORAGE:
			building.resources.set_capacity(ResourceType.Type.FOOD, 20)
			building.resources.set_capacity(ResourceType.Type.LOG, Balance.WAREHOUSE_LOG_CAPACITY)
			building.resources.set_capacity(ResourceType.Type.PLANK, Balance.WAREHOUSE_PLANK_CAPACITY)
			building.resources.set_capacity(ResourceType.Type.STONE, Balance.STORAGE_STONE_CAPACITY)
			logistics.add_warehouse(building)
		BuildingType.Type.FOOD:
			if kitchen_data == null:
				kitchen_data = building
			building.resources.set_capacity(ResourceType.Type.FOOD, 20)
			logistics.add_kitchen(building)
		BuildingType.Type.LUMBERJACK_HUT:
			building.resources.set_allowed_resource_types([ResourceType.Type.LOG])
			building.resources.set_capacity(ResourceType.Type.LOG,building.definition.local_resource_capacity)
			logistics.register_building(building)
		BuildingType.Type.QUARRY:
			building.resources.set_allowed_resource_types([ResourceType.Type.STONE])
			building.resources.set_capacity(ResourceType.Type.STONE,building.definition.local_resource_capacity)
			logistics.register_building(building)
		BuildingType.Type.SAWMILL:
			building.resources.set_allowed_resource_types([ResourceType.Type.LOG,ResourceType.Type.PLANK])
			building.resources.set_capacity(ResourceType.Type.LOG,Balance.SAWMILL_INPUT_CAPACITY)
			building.resources.set_capacity(ResourceType.Type.PLANK,Balance.SAWMILL_OUTPUT_CAPACITY)
			logistics.register_building(building)
		BuildingType.Type.GATHERER_HUT:
			building.resources.set_allowed_resource_types([ResourceType.Type.FOOD])
			building.resources.set_capacity(ResourceType.Type.FOOD, 5)
			if gatherer_hut_data == null:
				gatherer_hut_data = building
				production.building = building
			else: production.additional_buildings.append(building)
			logistics.add_production_source(building)
	player_control.register_building(building)
	interactions.register_building(building, world_locations.get_position.bind(building.id))
	for runtime in resident_runtimes: runtime.needs.register_food_building(building)
	logistics.recalculate()


# Presentation factories preserve the same starter data and controller wiring.
func _register_building_location(building: BuildingInstance, view: Node) -> void:
	world_locations.register(WorldLocation.new(building.id, building.display_name), view)
	interactions.register_building(building, world_locations.get_position.bind(building.id))
func _create_resident_runtime(data: ResidentData, start: Vector2) -> ResidentRuntime:
	var view = _create_resident_presentation(data, start)
	var runtime = ResidentRuntime.new()
	runtime.name = data.id
	$Residents.add_child(runtime)
	resident_runtimes.append(runtime)
	runtime.logger = game_logger
	runtime.food_availability = food_availability
	runtime.setup(data, view, game_time, world_locations, buildings, fallback_housing)
	interactions.register_target(StringName(data.id), data.resident_name, data, _resident_interaction_position.bind(data.id), [&"resident"])
	return runtime

func _bind_resident_control(runtime: ResidentRuntime) -> void:
	player_control.register_intents(runtime.data.id, runtime.intents)
	player_control.register_commands(runtime.data.id, runtime.commands)
	player_control.register_assignments(runtime.data.id, runtime.assignments)
	player_control.profession_changed.connect(runtime.builder.on_profession_changed)
	runtime.decision.work_available = _work_available.bind(runtime)
	runtime.decision.work_request = _request_work.bind(runtime)
	runtime.schedule.work_decision = runtime.decision.request_decision
	if is_instance_valid(decision_dispatcher):
		runtime.decision.bind_dispatcher(decision_dispatcher)
		runtime.decision.queued_work_valid = _queued_work_valid.bind(runtime)

func _queued_work_valid(runtime: ResidentRuntime) -> bool:
	# Registration identity and an already-owned haul are cheap guards, not a new eligibility policy.
	return player_control.get_resident(runtime.data.id) == runtime.data and get_resident_runtime(find_resident(runtime.data.id)) == runtime and logistics.get_job(runtime.data.id) == null

func _bind_resident_social(runtime: ResidentRuntime) -> void:
	social_world.register(runtime)
	runtime.recipe_work.position_provider = _production_position_2d
	runtime.builder.position_provider = _production_position_2d
	runtime.needs.position_provider = _food_position_2d
	runtime.needs.ground_position_provider = _production_position_2d
	runtime.builder.cargo_drop_handler = _drop_cargo.bind(runtime)
	runtime.social.world = social_world
	runtime.assignments.bind_social_world()
	runtime.wander.target_provider = _wander_target_2d.bind(runtime.data.id)
	runtime.wander.target_available = _wander_available_2d.bind(runtime.data.id)

func _bind_resident_logistics(runtime: ResidentRuntime) -> void:
	logistics.register_resident(runtime.data)
	logistics.use_executor(runtime.data, game_time, world_locations, runtime.intents, runtime.schedule)
	runtime.builder.bind_sources(logistics.sources)
	runtime.needs.bind_sources(logistics.sources)
	runtime.self_logistics.setup(runtime,self)

func _food_position_2d(resident_id: String) -> Variant:
	var runtime = get_resident_runtime(find_resident(resident_id))
	if runtime == null: return null
	# A new route exits an occupied interior before moving; use that same walkable origin.
	return runtime.view.get_drop_sim_position() if runtime.view.has_method("get_drop_sim_position") else _production_position_2d(resident_id)

# Scene assembly hooks: playable Main3D and isolated deterministic domain fixtures.
# There are no 2D presentation defaults.
func _build_hud() -> void: pass
func _setup_construction() -> void: pass
func _create_starting_buildings() -> void: pass
func _starting_home_id(_index: int) -> StringName: return &""
func _create_starting_home(_data: ResidentData, _index: int) -> void: pass
func _create_resident_presentation(_data: ResidentData, _start: Vector2) -> Node: return null
func _create_building_presentation(_building: BuildingInstance) -> Node: return null
func _show_ground_resource(_drop) -> void: pass

func _exit_tree() -> void:
	food_availability.dispose()
