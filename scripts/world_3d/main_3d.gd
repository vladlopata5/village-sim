extends "res://scripts/main.gd"
## Shares Main's simulation wiring; canonical Town Center starter; replaces presentation factories.
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
var work_areas = preload("res://scripts/work_areas.gd").new()
var work_area_tool = preload("res://scripts/world_3d/work_area_tool_3d.gd").new()
var area_confirm: Button
var forestry_area = preload("res://scripts/world_3d/forestry_area_3d.gd").new()
var _next_tree_id := 17
var _last_growth_minute := 0
var rocks: Array = []
var rock_views: Dictionary = {}
var _rock_receipts: Dictionary = {}
var rock_locations = preload("res://scripts/world_3d/natural_source_locations_3d.gd").new()
var trees: Array = []
var tree_views: Dictionary = {}
var tree_locations = preload("res://scripts/world_3d/tree_locations_3d.gd").new()
var legacy_reference_setup := false # Explicit historical integration fixture only.
var entrance_zones = preload("res://scripts/world_3d/building_entrance_zones_3d.gd").new()
var building_uses = preload("res://scripts/world_3d/building_use_3d.gd").new()
var settlement_panel: PanelContainer
var assignment_dialog: PanelContainer
var debug_spawn: RefCounted
var developer_panel: PanelContainer
var debug_spawn_marker: MeshInstance3D
@onready var game_ui: Control = $HUD/GameUI
var ready_for_play := false
var _clicks: Array[InputEventMouseButton] = []
var _pointer_position := Vector2.ZERO
var _tool_generation := 0
var _confirming_placement := false
func _ready() -> void:
	decision_dispatcher = preload("res://scripts/ai_decision_dispatcher.gd").new()
	decision_dispatcher.name = "AIDecisionDispatcher"
	add_child(decision_dispatcher)
	world_locations = preload("res://scripts/world_3d/building_locations_3d.gd").new()
	world_locations.navigation = navigation
	building_uses.navigation = navigation
	if not legacy_reference_setup: world_locations.uses = building_uses
	player_control.work_areas = work_areas
	super._ready()
	game_ui.cancel_world_tool = _cancel_active_world_tool
	game_ui.bind_context_menu(interaction_menu)
	interaction_menu.consume_dismiss_click = true
	game_ui.blocking_ui_changed.connect(_clear_world_input)
	$World/Camera3D.ui_input_context = game_ui.input_context
	$World.add_child(work_area_tool)
	area_confirm = Button.new()
	area_confirm.text = "Подтвердить область (Enter) • ПКМ/Esc: отмена"
	area_confirm.position = Vector2(12,170)
	area_confirm.hide()
	area_confirm.pressed.connect(_confirm_work_area)
	$HUD.add_child(area_confirm)
	game_ui.register_pointer_control(area_confirm)
	resident_card_view().work_area_requested.connect(_start_work_area)
	player_control.work_assignment_changed.connect(_work_assignment_updated)
	work_areas.changed.connect(_work_areas_updated)
	settlement_panel = preload("res://scenes/ui/residents_window.tscn").instantiate()
	$HUD.add_child(settlement_panel)
	game_ui.register_window(&"residents", settlement_panel)
	settlement_panel.set_canonical_layout()
	settlement_panel.setup(player_control,resident_selection)
	assignment_dialog=preload("res://scenes/ui/assignment_dialog.tscn").instantiate()
	game_ui.get_node("Windows").add_child(assignment_dialog)
	assignment_dialog.setup(player_control,resident_selection,game_ui)
	settlement_panel.assignment_requested.connect(assignment_dialog.open_for)
	settlement_panel.visibility_changed.connect(func():
		if not settlement_panel.visible: assignment_dialog.close())
	building_card_view().settlement_management_requested.connect(_open_residents)
	building_card_view().staffing_requested.connect(_open_residents)
	game_ui.update_population(residents.size())
	$World.add_child(navigation_debug)
	navigation_debug.setup(navigation)
	navigation.changed.connect(_on_navigation_changed)
	resident_selection.selection_changed.connect(_update_navigation_debug)
	_pointer_position = get_viewport().get_mouse_position()
	_setup_forest()
	_setup_rocks()
	_setup_roads()
	navigation.prepare_connectivity() # Once after all initial world registration.
	ready_for_play = true
	if OS.is_debug_build():
		debug_spawn=preload("res://scripts/debug_spawn_service.gd").new()
		debug_spawn.world=self
		developer_panel=preload("res://scripts/debug_panel.gd").new()
		$HUD.add_child(developer_panel)
		developer_panel.setup(debug_spawn)
		developer_panel.add_navigation_toggle(_set_navigation_debug,navigation_debug.visible)
		developer_panel.z_index=3
		developer_panel.escape_handler = game_ui.try_escape
		developer_panel.ui_input_context = game_ui.input_context
		game_ui.register_pointer_control(developer_panel)
		game_ui.blocking_ui_changed.connect(developer_panel._paused_clicks.clear)
		developer_panel.placement_started.connect(_start_debug_placement)
		developer_panel.placement_cancelled.connect(_debug_input_cancelled)
		debug_spawn_marker=MeshInstance3D.new()
		var marker_mesh := PlaneMesh.new()
		marker_mesh.size=Vector2(0.8,0.8)
		debug_spawn_marker.mesh=marker_mesh
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color=Color(1.0,0.8,0.1)
		marker_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		debug_spawn_marker.material_override=marker_material
		$World.add_child(debug_spawn_marker)
		debug_spawn_marker.hide()
		developer_panel.placement_cancelled.connect(debug_spawn_marker.hide)
func _open_residents(role: int=-1) -> void:
	settlement_panel.preset_profession(role)
	game_ui.open_window(&"residents")
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
	if not legacy_reference_setup:
		building_uses.register(building,view)
		entrance_zones.register(building)
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
	placement.entrance_zones = entrance_zones if not legacy_reference_setup else null
	placement.runtime_blockers = runtime_placement_blockers
	placement.setup(buildings)
	placement.logger = game_logger
	placement.placed.connect(_show_building)
	construction_panel = preload("res://scenes/ui/action_panel.tscn").instantiate()
	$HUD.add_child(construction_panel)
	construction_panel.definition_selected.connect(_select_building_definition)
	construction_panel.road_selected.connect(_select_road_tool)
	construction_panel.collapse_changed.connect(_construction_collapsed)
	game_ui.info_panel.preview_close_requested.connect(_cancel_building_placement)
	resident_selection.selection_changed.connect(_selection_tool_changed)
	game_ui.mount_construction(construction_panel)
	building_ghost = preload("res://scripts/world_3d/building_ghost_3d.gd").new()
	building_ghost.name = "BuildingGhost3D"
	$World.add_child(building_ghost)
	building_ghost.setup(placement)
	placement.changed.connect(building_ghost.refresh)
	placement.changed.connect(_placement_ui_changed)
func _setup_roads() -> void:
	road_tool.roads=roads
	road_tool.build_grid=build_grid
	road_tool.runtime_blockers=runtime_placement_blockers
	road_layer.name="DirtRoadLayer"
	$World.add_child(road_layer)
	road_navigation.setup(roads,navigation)
	road_layer.setup(roads)
	_road_button=construction_panel.catalogue.tiles[&"dirt_road"]
func _sync_catalogue() -> void:
	construction_panel.catalogue.sync_tool(placement.selected_definition,road_tool.active)
func _placement_ui_changed() -> void:
	_sync_catalogue()
	if not placement.is_active() and not _confirming_placement: game_ui.info_panel.clear_type_preview()
func _construction_collapsed(collapsed: bool) -> void:
	if collapsed and (placement.is_active() or _confirming_placement or road_tool.active): _cancel_active_world_tool()
func _selection_tool_changed() -> void:
	if resident_selection.selected_entity!=null: _cancel_active_world_tool()
func _cancel_building_placement() -> void:
	# Also records cancellation while base confirm has cleared its definition.
	_tool_generation+=1
	placement.cancel()
	_clear_world_input()
	game_ui.info_panel.clear_type_preview()
	_sync_catalogue()
func _select_road_tool() -> void:
	if road_tool.active:
		_cancel_road_tool()
		return
	_cancel_debug_placement()
	_cancel_work_area()
	_cancel_building_placement()
	interaction_menu.hide()
	road_tool.select()
	_sync_catalogue()
func _cancel_road_tool() -> void:
	_tool_generation+=1
	road_tool.cancel()
	_clear_world_input()
	_sync_catalogue()
func _select_building_definition(definition: BuildingDefinition) -> void:
	if placement.selected_definition==definition:
		_cancel_building_placement()
		return
	# Capture only presentation state before synchronous cancellation/selection callbacks.
	var expansion: bool=game_ui.info_panel.expanded
	_cancel_debug_placement()
	_cancel_work_area()
	_cancel_road_tool()
	_cancel_building_placement()
	interaction_menu.hide()
	resident_selection.clear()
	placement.select(definition)
	game_ui.info_panel.show_type_preview(definition,construction_panel.catalogue.description(definition),expansion)
func _confirm_building_placement() -> BuildingInstance:
	var definition: BuildingDefinition=placement.selected_definition
	var turns: int=placement.quarter_turns
	var point: Vector3=placement.world_position
	var generation := _tool_generation
	_confirming_placement=true
	var building: BuildingInstance=placement.confirm() # Exactly one domain confirmation.
	_confirming_placement=false
	if building!=null and generation==_tool_generation and not placement.is_active():
		_tool_generation+=1
		_clear_world_input()
		placement.select(definition)
		placement.set_orientation(turns)
		placement.update_world_position(point)
		building_ghost.refresh()
	if not placement.is_active(): game_ui.info_panel.clear_type_preview()
	_sync_catalogue()
	return building
func _process(_delta: float) -> void:
	if debug_spawn_marker!=null:
		debug_spawn_marker.hide()
		if developer_panel.active() and get_viewport().gui_get_hovered_control()==null:
			var debug_hit := ground_pick(_pointer_position)
			if debug_hit.has("position"):
				debug_spawn_marker.global_position=debug_hit.position+Vector3(0,0.03,0)
				debug_spawn_marker.show()
	if work_area_tool.active() and not work_area_tool.locked:
		var area_hit := ground_pick(_pointer_position)
		if area_hit.has("position"): work_area_tool.update_world(area_hit.position)
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
	player_control.unregister_building(id)
	var activation := _activate_completed_building.bind(building)
	if building.construction_changed.is_connected(activation): building.construction_changed.disconnect(activation)
	for runtime in resident_runtimes: runtime.builder.unregister_building(building)
	if resident_selection.selected_building == building: resident_selection.clear()
	var view: Node = world_locations.get_view(id)
	building_uses.unregister(id)
	entrance_zones.release(id)
	world_locations.unregister(id)
	if is_instance_valid(view):
		view.collision_layer = 0
		view.queue_free()
	build_grid.release(id)
	navigation.remove_blocker(id)
	game_logger.info(GameLogger.BUILDING, "стройка отменена — %s" % id)
	return true
func _drop_cargo(resource: ResourceType.Type, amount: int, runtime: ResidentRuntime) -> void:
	ground_resources.create_drop(resource, amount, runtime.view.get_drop_sim_position())
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
	if event is InputEventMouseMotion and _road_dragging and game_ui.input_context.pointer_blocked(event.position):
		_road_events.append({"end":true}) # Never interpolate across a UI-covered gap.
func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_play: return
	if event is InputEventKey and game_ui.input_context.text_editing(): return
	if event is InputEventMouse and game_ui.input_context.pointer_blocked(event.position):
		get_viewport().set_input_as_handled()
		return
	if developer_panel!=null and developer_panel.active():
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			_queue_world_click(event)
			get_viewport().set_input_as_handled()
		return
	if work_area_tool.active():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: _cancel_work_area()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER: _confirm_work_area()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT: _cancel_work_area()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _queue_world_click(event)
		else: return
		get_viewport().set_input_as_handled()
		return
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
		if placement.is_active(): _cancel_building_placement()
		else: resident_selection.clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_queue_world_click(event)
		get_viewport().set_input_as_handled()
func _physics_process(_delta: float) -> void:
	if road_tool.active:
		for event in _road_events:
			if event.has("end"):
				road_tool.end_stroke()
				continue
			if game_ui.input_context.pointer_blocked(event.screen):
				road_tool.end_stroke()
				continue
			var hit := ground_pick(event.screen)
			if hit.has("position"): road_tool.paint(hit.position,event.erase)
			else: road_tool.end_stroke()
	_road_events.clear()
	var pending := _clicks.duplicate()
	_clicks.clear()
	for event in pending:
		if event.get_meta("tool_generation",-1)!=_tool_generation: continue
		if not game_ui.input_context.pointer_blocked(event.position):
			handle_world_click(event.button_index, ground_pick(event.position) if placement.is_active() or work_area_tool.active() or (developer_panel!=null and developer_panel.active()) else pick(event.position), event.position)
func _queue_world_click(event: InputEventMouseButton) -> void:
	var queued: InputEventMouseButton=event.duplicate()
	queued.set_meta("tool_generation",_tool_generation)
	_clicks.append(queued)
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
	if developer_panel!=null and developer_panel.active():
		if button==MOUSE_BUTTON_RIGHT: developer_panel.cancel_placement()
		elif button==MOUSE_BUTTON_LEFT:
			if hit.has("position"): developer_panel.confirm_world(hit.position)
			else: developer_panel._show_result(debug_spawn.rejected("Нет попадания по земле внутри карты"))
		if not developer_panel.active(): debug_spawn_marker.hide()
		return
	if work_area_tool.active():
		if button == MOUSE_BUTTON_RIGHT: _cancel_work_area()
		elif button == MOUSE_BUTTON_LEFT and hit.has("position"):
			work_area_tool.update_world(hit.position)
			work_area_tool.locked = true
			area_confirm.show()
		return
	if road_tool.active: return
	if placement.is_active():
		if button == MOUSE_BUTTON_RIGHT: _cancel_building_placement()
		elif button == MOUSE_BUTTON_LEFT:
			placement.has_ground_position = hit.has("position")
			if hit.has("position"): placement.update_world_position(hit.position)
			_confirm_building_placement()
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

func _set_navigation_debug(enabled: bool) -> void:
	navigation_debug.set_enabled(enabled)
	_set_work_area_debug(enabled)
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
	for runtime in resident_runtimes: _bind_lumberjack(runtime)
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
	if runtime.data.profession in [Profession.Type.LUMBERJACK,Profession.Type.MINER]:
		var controller = runtime.get_node_or_null("Miner" if runtime.data.profession == Profession.Type.MINER else "Lumberjack")
		return controller != null and controller.has_work()
	return super._work_available(runtime)
func _request_work(runtime: ResidentRuntime) -> bool:
	if runtime.data.profession in [Profession.Type.LUMBERJACK,Profession.Type.MINER]:
		var controller = runtime.get_node_or_null("Miner" if runtime.data.profession == Profession.Type.MINER else "Lumberjack")
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
	var from_world := Coordinates.to_world(start)
	var to_world := Coordinates.to_world(target)
	return navigation.can_reach_point(from_world,to_world) and not navigation.find_path(from_world,to_world).is_empty()

func _create_starting_buildings() -> void:
	if legacy_reference_setup:
		_create_test_kitchen()
		_create_test_warehouse()
		_create_test_gatherer_hut()
		return
	warehouse_data = BuildingData.new(&"town_center", "Городской центр", BuildingType.Type.TOWN_CENTER)
	warehouse_data.position = Vector2(300,237.5)
	for resource in ResourceType.Type.values():
		warehouse_data.resources.set_capacity(resource,Balance.TOWN_CENTER_RESOURCE_CAPACITY)
	warehouse_data.resources.add(ResourceType.Type.PLANK,Balance.TOWN_CENTER_STARTING_PLANK)
	warehouse_data.resources.add(ResourceType.Type.FOOD,Balance.TOWN_CENTER_STARTING_FOOD)
	buildings.append(warehouse_data)
	var view = _create_building_presentation(warehouse_data)
	_register_building_location(warehouse_data,view)
func _starting_home_id(index: int) -> StringName:
	return super._starting_home_id(index) if legacy_reference_setup else &""
func _create_starting_home(data: ResidentData, index: int) -> void:
	if legacy_reference_setup: _create_legacy_home(data,index)

func _start_work_area(resident_id: String) -> void:
	_cancel_debug_placement()
	var resident = player_control.get_resident(resident_id)
	if resident == null or resident.profession not in [Profession.Type.LUMBERJACK,Profession.Type.MINER]: return
	_cancel_building_placement()
	_cancel_road_tool()
	interaction_menu.hide()
	_clicks.clear()
	area_confirm.hide()
	work_area_tool.start(resident_id,preload("res://scripts/balance_config.gd").FREE_WORK_AREA_RADIUS)
func _cancel_work_area() -> void:
	_tool_generation+=1
	_clear_world_input()
	work_area_tool.cancel()
	if area_confirm != null: area_confirm.hide()
	_clicks.clear()
func _confirm_work_area() -> void:
	if not work_area_tool.active() or not work_area_tool.locked: return
	var resident = player_control.get_resident(work_area_tool.resident_id)
	if resident == null or resident.profession not in [Profession.Type.LUMBERJACK,Profession.Type.MINER]:
		_cancel_work_area()
		return
	var area = work_areas.create(work_area_tool.preview.center,work_area_tool.preview.radius)
	if area != null and not player_control.assign_work_area(resident.id,area.id): work_areas.remove(area.id)
	_cancel_work_area()
var _work_updates: Dictionary = {}
func _work_assignment_updated(id: String) -> void:
	decision_dispatcher.cancel(id)
	if _work_updates.has(id): return
	_work_updates[id] = true
	_flush_work_update.call_deferred(id)
func _flush_work_update(id: String) -> void:
	_work_updates.erase(id)
	for runtime in resident_runtimes:
		if is_instance_valid(runtime) and is_instance_valid(runtime.decision) and runtime.data.id == id and not runtime.intents.has_current_action(): runtime.decision.request_decision("work_assignment")
func _work_areas_updated() -> void:
	for runtime in resident_runtimes:
		if not runtime.data.work_area_id.is_empty(): _work_assignment_updated(runtime.data.id)

func _setup_rocks() -> void:
	rock_locations.navigation = navigation
	# World units; isolated from starter portal and existing forest fixtures.
	var points := [Vector3(22.25,0,-6.25),Vector3(26.25,0,-6.25),Vector3(30.25,0,-6.25),Vector3(34.25,0,-6.25),Vector3(38.25,0,-6.25),Vector3(22.25,0,-11.25),Vector3(26.25,0,-11.25),Vector3(30.25,0,-11.25),Vector3(34.25,0,-11.25),Vector3(38.25,0,-11.25)]
	for index in points.size():
		_register_rock(preload("res://scripts/rock_data.gd").new(StringName("rock_%02d" % (index+1)),Coordinates.to_sim(points[index])))
	for runtime in resident_runtimes: _bind_miner(runtime)
func _rock_world_position(rock: RefCounted) -> Vector3:
	return Coordinates.to_world(rock.position)
func _register_rock(rock: RefCounted) -> void:
	rocks.append(rock)
	var view = preload("res://scripts/world_3d/rock_view_3d.gd").new()
	$World.add_child(view)
	view.setup(rock)
	rock_views[rock.id] = view
	var center := Coordinates.world_plane(_rock_world_position(rock))
	navigation.add_blocker(rock.id,Rect2(center-Vector2.ONE*rock.physical_radius,Vector2.ONE*rock.physical_radius*2.0))
	runtime_placement_blockers.register_circle(rock.id,_rock_world_position.bind(rock),rock.physical_radius,true)
func _complete_rock_cycle(rock: RefCounted, receipt: int, worker_position: Vector2) -> void:
	var key := "%s:%d" % [rock.id,receipt]
	if receipt <= 0 or receipt > rock.completed_cycles or _rock_receipts.has(key): return
	# Mark before emitting Ground added/navigation signals (which can reenter).
	_rock_receipts[key] = true
	assert(rock_locations.is_available(worker_position),"Mining yield must be on walkable ground")
	ground_resources.create_drop(ResourceType.Type.STONE,1,worker_position)
	if rock.stock > 0: return
	rocks.erase(rock)
	var view: Node = rock_views.get(rock.id)
	rock_views.erase(rock.id)
	if is_instance_valid(view):
		view.collision_layer = 0
		view.queue_free()
	runtime_placement_blockers.unregister(rock.id)
	navigation.remove_blocker(rock.id)

func _bind_lumberjack(runtime: ResidentRuntime) -> void:
	var controller = preload("res://scripts/resident_lumberjack_controller.gd").new()
	controller.name = "Lumberjack"
	runtime.add_child(controller)
	controller.setup(runtime,game_time,trees,tree_locations,_deplete_tree)
	controller.world = self
	runtime.view.tree_exiting.connect(controller.abort.bind(false))

func _bind_miner(runtime: ResidentRuntime) -> void:
	var controller = preload("res://scripts/resident_miner_controller.gd").new()
	controller.name = "Miner"
	runtime.add_child(controller)
	controller.world = self
	controller.setup(runtime,game_time,rocks,rock_locations,_complete_rock_cycle)
	runtime.view.tree_exiting.connect(controller.abort.bind(false))

func register_spawned_resident(data: ResidentData, point: Vector3) -> ResidentRuntime:
	# Same production wiring as starter residents; data owns no duplicated position.
	if find_resident(data.id)!=null: return null
	residents.append(data)
	var runtime := _create_resident_runtime(data,Coordinates.to_sim(point))
	_bind_resident_control(runtime)
	_bind_resident_social(runtime)
	_bind_resident_logistics(runtime)
	_bind_lumberjack(runtime)
	_bind_miner(runtime)
	social_events.register(runtime)
	player_control.setup(residents,buildings)
	_update_population()
	return runtime

func _start_debug_placement() -> void:
	_cancel_work_area()
	_cancel_road_tool()
	_cancel_building_placement()
	_clear_world_input()
	interaction_menu.hide()
func _debug_input_cancelled() -> void:
	_tool_generation+=1
	_clear_world_input()
func _cancel_debug_placement() -> void:
	if developer_panel!=null and developer_panel.active(): developer_panel.cancel_placement()

# Presentation hooks: canonical HUD has real time controls, no hidden telemetry.
func resident_card_view() -> Control: return game_ui.resident_card
func building_card_view() -> Control: return game_ui.building_card
func ui_input_context() -> RefCounted: return game_ui.input_context
func _build_hud() -> void:
	game_ui.time_controls.setup(game_time, _toggle_pause)
	clock_label = game_ui.time_controls.clock_label
	pause_button = game_ui.time_controls.pause_button
	speed_buttons = game_ui.time_controls.speed_buttons
	game_ui.mount_messages(social_feed)
	game_ui.info_panel.setup(game_time,resident_selection,player_control,logistics.get_job,_ui_visitors,_ui_natural_progress)
	building_uses.slots_changed.connect(_ui_slots_changed)
func _update_clock(_minutes: int) -> void: game_ui.time_controls.request_clock_refresh()
func _update_pause() -> void: game_ui.time_controls.refresh_pause()
func _update_population() -> void: game_ui.update_population(residents.size())
func _update_phase(_phase: String) -> void: pass
func _show_missing_kitchen() -> void: pass
func _update_production() -> void: pass
func _update_logistics() -> void: pass
func _update_food(_resource: ResourceType.Type, _amount: int) -> void: pass
func _update_warehouse_food(_resource: ResourceType.Type, _amount: int) -> void: pass
func _clear_world_input() -> void:
	_clicks.clear()
	_road_events.clear()
	_road_dragging = false
	road_tool.end_stroke()
func _cancel_active_world_tool() -> bool:
	if developer_panel != null and developer_panel.active():
		_cancel_debug_placement()
	elif work_area_tool.active(): _cancel_work_area()
	elif road_tool.active: _cancel_road_tool()
	elif placement.is_active() or _confirming_placement: _cancel_building_placement()
	else: return false
	_clear_world_input()
	return true

func _ui_visitors(building_id: StringName) -> Array:
	var view = building_uses.view(building_id)
	if view == null: return []
	var slot = preload("res://scripts/world_3d/building_slot_3d.gd")
	return view.get_markers(slot).filter(func(marker): return marker.purpose != slot.Purpose.CONSTRUCTION and not marker.occupant.is_empty()).map(func(marker): return {"id":marker.occupant,"purpose":marker.purpose})
func _ui_slots_changed(id: StringName, _purpose: int) -> void:
	if resident_selection.selected_building != null and resident_selection.selected_building.id == id: building_card_view()._refresh()

func _ui_natural_progress(building_id: StringName) -> PackedStringArray:
	# Read captured active contexts, never call work availability/path selection.
	var lines := PackedStringArray()
	for runtime in resident_runtimes:
		if not is_instance_valid(runtime): continue
		var forestry = runtime.get_node_or_null("Lumberjack")
		if forestry != null and forestry.hut != null and forestry.hut.id == building_id:
			if forestry.kind == &"CHOP" and forestry.tree != null:
				lines.append("%s • рубка: %d / %d мин" % [runtime.data.resident_name,forestry.tree.work_done,forestry.tree.work_required])
			elif forestry.kind == &"PLANT":
				lines.append("%s • посадка: %d / %d мин" % [runtime.data.resident_name,forestry.work_minutes,Balance.TREE_PLANTING_MINUTES])
		var miner = runtime.get_node_or_null("Miner")
		if miner != null and miner.committed_context != null and miner.committed_context.workplace != null and miner.committed_context.workplace.id == building_id and miner.rock != null:
			lines.append("%s • добыча: %d / %d мин" % [runtime.data.resident_name,miner.rock.work_done,miner.rock.work_required])
	return lines
