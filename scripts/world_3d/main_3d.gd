extends "res://scripts/main.gd"
## Shares Main's starter setup and simulation wiring; replaces presentation factories.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Executor = preload("res://scripts/world_3d/resident_executor_3d.gd")
const BuildingView = preload("res://scripts/world_3d/building_view_3d.gd")
const ResidentView = preload("res://scripts/world_3d/resident_view_3d.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var navigation = preload("res://scripts/navigation_grid.gd").new()
var navigation_debug = preload("res://scripts/world_3d/navigation_grid_debug.gd").new()
var build_grid = preload("res://scripts/build_grid.gd").new()
var building_ghost: Node3D
var ready_for_play := false
var _clicks: Array[InputEventMouseButton] = []
var _pointer_position := Vector2.ZERO
func _ready() -> void:
	world_locations = preload("res://scripts/world_3d/building_locations_3d.gd").new()
	world_locations.navigation = navigation
	super._ready()
	$World.add_child(navigation_debug)
	navigation_debug.setup(navigation)
	navigation.changed.connect(_on_navigation_changed)
	var toggle := CheckButton.new()
	toggle.name = "NavigationDebugToggle"
	toggle.text = "Navigation debug: blocked / raw / smooth"
	toggle.position = Vector2(16,590)
	toggle.toggled.connect(navigation_debug.set_enabled)
	$HUD.add_child(toggle)
	resident_selection.selection_changed.connect(_update_navigation_debug)
	_pointer_position = get_viewport().get_mouse_position()
	ready_for_play = true
func _create_resident_presentation(data: ResidentData, start: Vector2) -> Node:
	var executor = Executor.new()
	executor.name = "ResidentExecutor_" + data.id
	$World/ResidentViews.add_child(executor)
	executor.position = Coordinates.to_world(start)
	executor.navigation = navigation
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
	var cells: Array = build_grid.footprint_cells(view.position, building.definition.footprint_cells, building.quarter_turns)
	var registered: bool = build_grid.occupy(building.id, cells)
	assert(registered, "Building registration must own a free footprint")
	navigation.add_blocker(building.id, Geometry.footprint(building))
	return view
func _register_interaction_view(_id: StringName, _view: Node) -> void:
	pass # Ray picking uses explicit entity references, not the 2D screen registry.
func _setup_construction() -> void:
	placement = preload("res://scripts/world_3d/building_placement_3d.gd").new()
	placement.grid = build_grid
	placement.setup(buildings)
	placement.logger = game_logger
	placement.placed.connect(_show_building)
	construction_panel = preload("res://scripts/construction_panel.gd").new()
	$HUD.add_child(construction_panel)
	var definitions: Array = []
	for category in [BuildingType.Type.HOME, BuildingType.Type.STORAGE, BuildingType.Type.FOOD, BuildingType.Type.GATHERER_HUT]:
		definitions.append(BuildingDefinition.for_type(category))
	construction_panel.setup(definitions)
	construction_panel.definition_selected.connect(_select_building_definition)
	building_ghost = preload("res://scripts/world_3d/building_ghost_3d.gd").new()
	building_ghost.name = "BuildingGhost3D"
	$World.add_child(building_ghost)
	building_ghost.setup(placement)
	placement.changed.connect(building_ghost.refresh)
func _process(_delta: float) -> void:
	if not ready_for_play or not placement.is_active(): return
	var hit := ground_pick(_pointer_position)
	placement.has_ground_position = not hit.is_empty()
	if hit.has("position"): placement.update_world_position(hit.position)
	building_ghost.refresh()
func ground_pick(screen_position: Vector2) -> Dictionary:
	var camera: Camera3D = $World/Camera3D
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 10000.0, 1)
	return $World.get_world_3d().direct_space_state.intersect_ray(query)
func cancel_construction(id: StringName) -> bool:
	# Lifecycle API for cancellation/tests; no demolition gameplay or new management UI.
	var building: BuildingInstance = player_control.get_building(id)
	if building == null or building.is_built(): return false
	buildings.erase(building)
	var activation := _activate_completed_building.bind(building)
	if building.construction_changed.is_connected(activation): building.construction_changed.disconnect(activation)
	for runtime in resident_runtimes: runtime.builder.unregister_building(building)
	if resident_selection.selected_building == building: resident_selection.clear()
	var view: Node = world_locations.get_view(id)
	world_locations.unregister(id)
	if is_instance_valid(view):
		view.collision_layer = 0
		view.queue_free()
	build_grid.release(id)
	navigation.remove_blocker(id)
	game_logger.info(GameLogger.BUILDING, "стройка отменена — %s" % id)
	return true
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
func _input(event: InputEvent) -> void:
	# Observe pointer motion without consuming UI clicks; placement ray follows this viewport position.
	if event is InputEventMouse: _pointer_position = event.position
func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play: return
	if event is InputEventKey and event.pressed and not event.echo and placement.is_active() and event.keycode == KEY_R:
		placement.rotate()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if placement.is_active(): placement.cancel()
		else: resident_selection.clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_clicks.append(event)
		get_viewport().set_input_as_handled()
func _physics_process(_delta: float) -> void:
	for event in _clicks: handle_world_click(event.button_index, ground_pick(event.position) if placement.is_active() else pick(event.position), event.position)
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
	if placement.is_active():
		if button == MOUSE_BUTTON_RIGHT: placement.cancel()
		elif button == MOUSE_BUTTON_LEFT:
			placement.has_ground_position = hit.has("position")
			if hit.has("position"): placement.update_world_position(hit.position)
			placement.confirm()
		building_ghost.refresh()
		return
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

func _update_navigation_debug() -> void:
	var data = resident_selection.selected_resident
	var runtime = get_resident_runtime(data) if data != null else null
	navigation_debug.bind_movement(runtime.view.movement if runtime != null else null)

func _on_navigation_changed(_revision: int) -> void:
	# Reuse local availability events; cached logistics offers must see new locations.
	logistics.recalculate()
