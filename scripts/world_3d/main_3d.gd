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
var runtime_placement_blockers = preload("res://scripts/runtime_placement_blockers.gd").new()
var roads = preload("res://scripts/road_grid.gd").new()
var road_tool = preload("res://scripts/world_3d/road_tool_3d.gd").new()
var road_navigation = preload("res://scripts/world_3d/road_navigation_3d.gd").new()
var road_layer = preload("res://scripts/world_3d/road_layer_3d.gd").new()
var _road_button: Button
var _road_events: Array[Dictionary] = []
var _road_dragging := false
var building_ghost: Node3D
var forestry_area = preload("res://scripts/world_3d/forestry_area_3d.gd").new()
var _next_tree_id := 17
var _last_growth_minute := 0
var trees: Array = []
var tree_views: Dictionary = {}
var tree_locations = preload("res://scripts/world_3d/tree_locations_3d.gd").new()
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
	toggle.text = "Навигация"
	toggle.tooltip_text = "Сетка, препятствия и маршруты жителей"
	toggle.position = Vector2(16,590)
	toggle.toggled.connect(navigation_debug.set_enabled)
	toggle.toggled.connect(_set_work_area_debug)
	$HUD.add_child(toggle)
	resident_selection.selection_changed.connect(_update_navigation_debug)
	_pointer_position = get_viewport().get_mouse_position()
	_setup_forest()
	_setup_roads()
	ready_for_play = true
func _create_resident_presentation(data: ResidentData, start: Vector2) -> Node:
	var executor = Executor.new()
	executor.name = "ResidentExecutor_" + data.id
	$World/ResidentViews.add_child(executor)
	executor.position = Coordinates.to_world(start)
	executor.navigation = navigation
	executor.setup(data)
	var registered: bool = runtime_placement_blockers.register_circle(StringName(data.id), executor.get_world_position, Geometry.RESIDENT_RADIUS)
	assert(registered, "Each resident has one runtime placement blocker")
	executor.tree_exiting.connect(runtime_placement_blockers.unregister.bind(StringName(data.id)))
	executor.set_time_speed(game_time.speed_multiplier)
	game_time.speed_changed.connect(executor.set_time_speed)
	executor.intent_failed.connect(_on_movement_failed.bind(data))
	return executor
func _create_building_presentation(building: BuildingInstance) -> Node:
	var view = BuildingView.new()
	view.name = String(building.id)
	$World/BuildingViews.add_child(view)
	view.position = Coordinates.to_world(building.position)
	assert(view.position.is_equal_approx(build_grid.snap(view.position, building.definition.footprint_cells, building.quarter_turns)), "Building source center must already be footprint-aligned")
	view.setup(building)
	view.set_work_area_debug(navigation_debug.visible)
	var cells: Array = build_grid.footprint_cells(view.position, building.definition.footprint_cells, building.quarter_turns)
	var registered: bool = build_grid.occupy(building.id, cells)
	assert(registered, "Building registration must own a free footprint")
	navigation.add_blocker(building.id, Geometry.footprint(building))
	roads.edit(cells,true) # Actual footprint only; cancellation never restores roads.
	return view
func _register_interaction_view(_id: StringName, _view: Node) -> void:
	pass # Ray picking uses explicit entity references, not the 2D screen registry.
func _setup_construction() -> void:
	placement = preload("res://scripts/world_3d/building_placement_3d.gd").new()
	placement.grid = build_grid
	placement.runtime_blockers = runtime_placement_blockers
	placement.setup(buildings)
	placement.logger = game_logger
	placement.placed.connect(_show_building)
	construction_panel = preload("res://scripts/construction_panel.gd").new()
	$HUD.add_child(construction_panel)
	var definitions: Array = []
	for category in [BuildingType.Type.HOME, BuildingType.Type.STORAGE, BuildingType.Type.FOOD, BuildingType.Type.GATHERER_HUT, BuildingType.Type.LUMBERJACK_HUT, BuildingType.Type.SAWMILL]:
		definitions.append(BuildingDefinition.for_type(category))
	construction_panel.setup(definitions)
	construction_panel.definition_selected.connect(_select_building_definition)
	building_ghost = preload("res://scripts/world_3d/building_ghost_3d.gd").new()
	building_ghost.name = "BuildingGhost3D"
	$World.add_child(building_ghost)
	building_ghost.setup(placement)
	placement.changed.connect(building_ghost.refresh)
func _setup_roads() -> void:
	road_tool.roads=roads
	road_tool.build_grid=build_grid
	road_tool.runtime_blockers=runtime_placement_blockers
	road_layer.name="DirtRoadLayer"
	$World.add_child(road_layer)
	road_navigation.setup(roads,navigation)
	road_layer.setup(roads)
	_road_button=Button.new()
	_road_button.text="Грунтовая дорога"
	_road_button.tooltip_text="ЛКМ: рисовать • Shift+ЛКМ: стирать • ПКМ/Esc: выйти"
	_road_button.focus_mode=Control.FOCUS_NONE
	_road_button.toggle_mode=true
	_road_button.pressed.connect(_select_road_tool)
	construction_panel.building_buttons.add_child(_road_button)
func _select_road_tool() -> void:
	if road_tool.active:
		_cancel_road_tool()
		return
	placement.cancel()
	_clicks.clear()
	interaction_menu.hide()
	road_tool.select()
	_road_button.button_pressed=true
func _cancel_road_tool() -> void:
	road_tool.cancel()
	_road_dragging=false
	_road_events.clear()
	if _road_button!=null: _road_button.button_pressed=false
func _select_building_definition(definition: BuildingDefinition) -> void:
	_cancel_road_tool()
	super._select_building_definition(definition)
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
	if not road_tool.active: return
	# Release always ends a stroke, including releases consumed by a UI control.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		_road_dragging=false
		_road_events.append({"end":true})
	if event is InputEventMouseMotion and _road_dragging and get_viewport().gui_get_hovered_control()!=null:
		_road_events.append({"end":true}) # Never interpolate across a UI-covered gap.
func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play: return
	if road_tool.active:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			_cancel_road_tool()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
			_cancel_road_tool()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				_road_dragging=true
				_road_events.append({"screen":event.position,"erase":event.shift_pressed})
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and _road_dragging:
			_road_events.append({"screen":event.position,"erase":event.shift_pressed})
			get_viewport().set_input_as_handled()
		return
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
	if road_tool.active:
		for event in _road_events:
			if event.has("end"):
				road_tool.end_stroke()
				continue
			var hit := ground_pick(event.screen)
			if hit.has("position"): road_tool.paint(hit.position,event.erase)
			else: road_tool.end_stroke()
	_road_events.clear()
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
	if road_tool.active: return
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

func _wander_available_2d(resident_id: String) -> bool:
	var origin: Variant = _production_position_2d(resident_id)
	return origin is Vector2 and navigation.is_world_walkable(Coordinates.to_world(origin))
func _wander_target_2d(rng: RandomNumberGenerator, resident_id: String):
	var origin: Variant = _production_position_2d(resident_id)
	if not origin is Vector2: return null
	return WanderTarget.nearby(origin, rng, field.FIELD, _reachable_wander_target)
func _reachable_wander_target(origin: Vector2, target: Vector2) -> bool:
	return not navigation.find_path(Coordinates.to_world(origin), Coordinates.to_world(target)).is_empty()

func _setup_forest() -> void:
	tree_locations.navigation = navigation
	forestry_area.setup(self)
	_last_growth_minute = game_time.total_minutes
	game_time.minute_changed.connect(_grow_trees)
	# Explicit natural world positions, away from starter residents/building access points.
	for row in range(4):
		for column in range(4):
			var point := Vector3(-25.25-column*3.0,0,-13.25+row*3.0)
			var tree = preload("res://scripts/tree_data.gd").new(StringName("tree_%02d" % (row*4+column+1)),Coordinates.to_sim(point))
			_register_tree(tree)
	for runtime in resident_runtimes:
		var controller = preload("res://scripts/resident_lumberjack_controller.gd").new()
		controller.name = "Lumberjack"
		runtime.add_child(controller)
		controller.setup(runtime,game_time,trees,tree_locations,_deplete_tree)
		controller.world = self
		runtime.view.tree_exiting.connect(controller.abort.bind(false))
func _tree_world_position(tree: RefCounted) -> Vector3: return Coordinates.to_world(tree.position)
func tree_footprint(tree: RefCounted) -> Rect2:
	var point := Coordinates.world_plane(_tree_world_position(tree))
	return Rect2(point-Vector2.ONE*tree.physical_radius,Vector2.ONE*tree.physical_radius*2.0)
func _deplete_tree(tree: RefCounted) -> void:
	if not tree_views.has(tree.id): return # Exactly-once world removal/yield.
	navigation.remove_traversal_modifier(tree.id)
	runtime_placement_blockers.unregister(tree.id)
	var view: Node = tree_views[tree.id]
	view.queue_free()
	tree_views.erase(tree.id)
	for index in range(tree.yield_amount):
		var offset := Vector2.from_angle(index*TAU/maxi(tree.yield_amount,1))*0.35
		ground_resources.create_drop(tree.yield_resource_type,1,tree.position+offset*Coordinates.SIM_UNITS_PER_WORLD_UNIT)
func _work_available(runtime: ResidentRuntime) -> bool:
	if runtime.data.profession == Profession.Type.LUMBERJACK:
		var controller = runtime.get_node_or_null("Lumberjack")
		return controller != null and controller.has_work()
	return super._work_available(runtime)
func _request_work(runtime: ResidentRuntime) -> bool:
	if runtime.data.profession == Profession.Type.LUMBERJACK:
		var controller = runtime.get_node_or_null("Lumberjack")
		return controller != null and controller.request_work()
	return super._request_work(runtime)
func _show_ground_resource(drop) -> void:
	var view = preload("res://scripts/world_3d/ground_resource_view_3d.gd").new()
	$World.add_child(view)
	view.setup(drop)
	_ground_views[drop] = view
	var id: StringName = drop.id
	_ground_ids[drop] = id
	interactions.register_target(id,ResourceType.display_name(drop.resource_type)+" на земле",drop,_ground_position.bind(drop),[&"ground_resource"])

func _register_tree(tree: RefCounted) -> void:
	trees.append(tree)
	var view = preload("res://scripts/world_3d/tree_view_3d.gd").new()
	$World.add_child(view)
	view.setup(tree)
	tree_views[tree.id] = view
	_refresh_tree_blocker(tree)
func _refresh_tree_blocker(tree: RefCounted) -> void:
	navigation.set_traversal_modifier(tree.id,tree_footprint(tree),preload("res://scripts/balance_config.gd").TREE_TRAVERSAL_SPEED_MULTIPLIER)
	runtime_placement_blockers.unregister(tree.id)
	runtime_placement_blockers.register_circle(tree.id,_tree_world_position.bind(tree),tree.physical_radius,true)
func spawn_sapling(position: Vector2) -> RefCounted:
	var tree = preload("res://scripts/tree_data.gd").new(StringName("tree_%02d" % _next_tree_id),position)
	_next_tree_id += 1
	tree.make_sapling()
	_register_tree(tree)
	game_logger.info(GameLogger.PRODUCTION,"Посажен саженец — %s" % tree.id)
	return tree
func _grow_trees(now: int) -> void:
	var minutes := maxi(now-_last_growth_minute,0)
	_last_growth_minute = now
	for tree in trees:
		if tree.grow(minutes):
			_refresh_tree_blocker(tree)
			game_logger.info(GameLogger.PRODUCTION,"Саженец вырос — %s" % tree.id)

func _set_work_area_debug(enabled: bool) -> void:
	for view in $World/BuildingViews.get_children(): view.set_work_area_debug(enabled)

func _resource_route_available(start: Vector2, target: Vector2) -> bool:
	return not navigation.find_path(Coordinates.to_world(start),Coordinates.to_world(target)).is_empty()
