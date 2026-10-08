extends "res://scripts/main.gd"
## Shares Main's starter setup and simulation wiring; replaces presentation factories.
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
const Executor = preload("res://scripts/world_3d/resident_executor_3d.gd")
const BuildingView = preload("res://scripts/world_3d/building_view_3d.gd")
const ResidentView = preload("res://scripts/world_3d/resident_view_3d.gd")
var ready_for_play := false
var _clicks: Array[InputEventMouseButton] = []
func _ready() -> void:
	var map: RID = $World.get_world_3d().navigation_map
	# Do not start schedules until the static navigation asset is synchronized.
	for frame in range(120):
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point_owner(map, Vector3.ZERO).is_valid(): break
	world_locations = preload("res://scripts/world_3d/building_locations_3d.gd").new()
	world_locations.navigation_map = map
	super._ready()
	ready_for_play = true
func _create_resident_presentation(data: ResidentData, start: Vector2) -> Node:
	var executor = Executor.new()
	executor.name = "ResidentExecutor_" + data.id
	$World/ResidentViews.add_child(executor)
	executor.position = Coordinates.to_world(start)
	executor.setup(data)
	executor.set_time_speed(game_time.speed_multiplier)
	game_time.speed_changed.connect(executor.set_time_speed)
	executor.intent_failed.connect(_on_movement_failed.bind(data))
	return executor
func _create_building_presentation(building: BuildingInstance) -> Node:
	var view = BuildingView.new()
	view.name = String(building.id)
	$World/BuildingViews.add_child(view)
	view.position = Coordinates.to_world(building.position)
	view.setup(building)
	return view
func _register_interaction_view(_id: StringName, _view: Node) -> void:
	pass # Ray picking uses explicit entity references, not the 2D screen registry.
func _setup_construction() -> void:
	var status := Label.new()
	status.text = "3D migration: строительство/placement и runtime navigation updates пока недоступны"
	status.position = Vector2(16, 690)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(status)
func _show_ground_resource(_drop) -> void:
	pass # Physical resource data/lifetime remain; 3D drop visuals are deferred.
func _drop_cargo(resource: ResourceType.Type, amount: int, runtime: ResidentRuntime) -> void:
	ground_resources.create_drop(resource, amount, runtime.view.get_sim_position())
func _on_movement_failed(intent: RefCounted, data: ResidentData) -> void:
	var runtime = get_resident_runtime(data)
	if runtime == null or runtime.intents.current_intent != intent: return
	game_logger.info(GameLogger.AI, "%s: маршрут недоступен — %s" % [data.resident_name, intent.reason_id])
	if runtime.commands.active_command != null: runtime.commands.cancel_current()
	else: runtime.intents.abort_current(intent)
func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		resident_selection.clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_clicks.append(event)
		get_viewport().set_input_as_handled()
func _physics_process(_delta: float) -> void:
	for event in _clicks: handle_world_click(event.button_index, pick(event.position), event.position)
	_clicks.clear()
func pick(screen_position: Vector2) -> Dictionary:
	var camera: Camera3D = $World/Camera3D
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * 10000.0
	# Exact resident hits have stable priority over building/ground.
	for mask in [2, 5]:
		var query := PhysicsRayQueryParameters3D.create(origin, end, mask)
		var hit: Dictionary = $World.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): return hit
	return {}
func handle_world_click(button: int, hit: Dictionary, screen: Vector2 = Vector2.ZERO) -> void:
	var collider: Object = hit.get("collider")
	if button == MOUSE_BUTTON_LEFT:
		if collider is ResidentView: resident_selection.select(collider.resident_data)
		elif collider is BuildingView: resident_selection.select_building(collider.building_data)
		else: resident_selection.clear()
	elif button == MOUSE_BUTTON_RIGHT and resident_selection.selected_resident != null:
		var data = resident_selection.selected_resident
		if collider is ResidentView: interaction_menu.open_for([data.id], StringName(collider.resident_data.id), screen)
		elif collider is BuildingView: interaction_menu.open_for([data.id], collider.building_data.id, screen)
		elif collider == $World/Ground and hit.has("position"):
			interaction_menu.hide()
			player_control.move_to(data.id, Coordinates.to_sim(hit.position))
