extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Logistics = preload("res://scripts/logistics_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ControlAPI = preload("res://scripts/player_control.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
func screen(scene: Node, point: Vector2) -> Vector2:
	return scene.field.get_global_transform_with_canvas() * scene.field.to_local(point)
func _run() -> void:
	var scene = Setup.make_scene(self)
	var panel = scene.construction_panel
	var placement = scene.placement
	var adapter = scene.placement_input
	var actor = scene.resident_runtimes[1]
	var card = scene.get_node("HUD/ResidentCard")
	var hud = scene.get_node("HUD/DebugPanel")
	var lines: Array[String] = []
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	scene.resident_selection.select(actor.data)
	hud.set_collapsed(true)
	await process_frame
	await process_frame
	check(panel.name == "ConstructionPanel" and not panel.collapsed and panel.building_buttons.is_visible_in_tree(), "Construction panel exists and expanded by default")
	check(panel.building_buttons.get_child_count() == 4, "All four existing building types supported")
	check(not panel.get_global_rect().intersects(card.get_global_rect()), "Bottom panel avoids resident card")
	var original_time: int = scene.game_time.total_minutes
	click(panel.collapse_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(panel.collapsed and not panel.building_buttons.visible and panel.collapse_button.is_visible_in_tree(), "Collapse keeps compact header")
	check(scene.game_time.total_minutes == original_time and scene.resident_selection.selected_resident == actor.data, "Collapse changes only UI")
	click(panel.collapse_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(not panel.collapsed and panel.building_buttons.visible, "Expand restores building buttons")
	var initial_count: int = scene.buildings.size()
	check(initial_count == 7 and scene.buildings.all(func(building): return building is Instance and building.is_built()), "All three buildings and four homes are BUILT instances in one registry")
	for building in scene.buildings:
		check(building.position == scene.world_locations.get_position(building.id), "Initial instance position matches world location")
	click(panel.building_buttons.get_child(2).get_global_rect().get_center())
	check(placement.is_active() and placement.selected_definition.type == Types.Type.FOOD and adapter.ghost != null, "Real button selects kitchen and creates ghost")
	check(not adapter.ghost is Instance and scene.buildings.size() == initial_count, "Preview creates no building instance")
	check(scene.resident_selection.selected_resident == actor.data, "Panel click preserves resident selection")
	click(panel.building_buttons.get_child(0).get_global_rect().get_center())
	check(placement.selected_definition.type == Types.Type.HOME and adapter.ghost.definition == placement.selected_definition, "Choosing another type updates preview")
	var point := Vector2(-500, 100)
	var motion := InputEventMouseMotion.new()
	motion.position = screen(scene, point)
	root.push_input(motion, true)
	adapter.refresh()
	check(adapter.ghost.global_position.is_equal_approx(point), "Ghost follows cursor in world coordinates")
	placement.update_position(scene.kitchen_data.position)
	check(not placement.can_place(), "Existing built building overlap invalid")
	check(placement.confirm() == null and scene.buildings.size() == initial_count and placement.is_active(), "Invalid confirm creates nothing and retains mode")
	placement.update_position(Vector2(-500, 100))
	check(placement.can_place(), "Non-overlapping position valid")
	placement.update_position(scene.buildings[3].position)
	check(not placement.can_place(), "Starting home also blocks placement")
	click(screen(scene, actor.view.global_position), MOUSE_BUTTON_RIGHT)
	check(actor.commands.active_command == null and not scene.interaction_menu.visible and placement.is_active(), "Placement RMB cannot issue command or context menu")
	# Put the other resident over a built footprint: click must neither select nor place.
	var other = scene.resident_runtimes[2]
	other.view.global_position = scene.kitchen_data.position
	click(screen(scene, other.view.global_position))
	check(scene.resident_selection.selected_resident == actor.data and scene.buildings.size() == initial_count and placement.is_active(), "Placement LMB invalid blocks resident selection")
	click(card.name_label.get_global_rect().get_center())
	check(scene.buildings.size() == initial_count and placement.is_active(), "Resident card blocks placement world clicks")
	click(screen(scene, point))
	check(scene.buildings.size() == initial_count + 1 and not placement.is_active() and adapter.ghost == null, "Valid world click creates exactly one instance and removes preview")
	var placed: Instance = scene.buildings.back()
	check(placed.state == Instance.State.UNDER_CONSTRUCTION and placed.position.is_equal_approx(point), "New instance has actual world position and UNDER_CONSTRUCTION state")
	check(scene.world_locations.get_position(placed.id) == point and scene.get_node("World/" + String(placed.id)).get_node("Caption").text.ends_with("— строится"), "Placed instance has world location and construction visual")
	check(scene.resident_selection.selected_resident == actor.data, "Successful placement also preserves selection")
	placement.select(Definition.for_type(Types.Type.STORAGE))
	placement.update_position(point)
	check(not placement.can_place(), "Under-construction footprint blocks next placement")
	placement.update_position(Vector2(-700, 100))
	var second = placement.confirm()
	check(second != null and second.id != placed.id and scene.buildings.count(second) == 1, "Consecutive placements have unique stable IDs")
	placement.select(Definition.for_type(Types.Type.GATHERER_HUT))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	check(not placement.is_active() and placement.selected_definition == null and adapter.ghost == null, "Escape cancels and deletes ghost")
	click(screen(scene, Vector2(-600, 180)), MOUSE_BUTTON_RIGHT)
	check(actor.commands.active_command != null, "Normal world command restored after Escape")
	# State guards must work even if a caller configures storage on a construction instance.
	var kitchen := Instance.new(&"not_built_kitchen", Definition.for_type(Types.Type.FOOD), Vector2.ZERO, Instance.State.UNDER_CONSTRUCTION)
	kitchen.resources.set_capacity(FOOD, 20)
	kitchen.resources.add(FOOD, 3)
	scene.buildings.append(kitchen)
	check(actor.needs.get_food_target(kitchen.id) == null, "Unbuilt kitchen excluded from EAT target lookup")
	check(scene.interactions.get_interactions([actor.data.id], placed.id).is_empty(), "Construction instance has no normal interactions")
	scene.interactions.register_building(kitchen, func(): return Vector2.ZERO)
	check(scene.interactions.get_interactions([actor.data.id], kitchen.id).is_empty(), "Interaction registration itself rejects construction instances")
	var logistics = Logistics.new()
	logistics.setup(scene.warehouse_data, kitchen, null)
	logistics.recalculate()
	check(logistics.jobs.is_empty() and kitchen.resources.get_reserved_in(FOOD) == 0, "Unbuilt destination cannot receive logistics job or reservation")
	logistics.setup(second, scene.kitchen_data, null)
	second.resources.set_capacity(FOOD, 20)
	second.resources.add(FOOD, 3)
	logistics.recalculate()
	check(logistics.jobs.is_empty() and second.resources.get_reserved_out(FOOD) == 0, "Unbuilt source cannot generate logistics job")
	var control = ControlAPI.new()
	control.setup(scene.residents, [second])
	check(not control.assign_workplace(actor.data.id, second.id) and not control.assign_profession(actor.data.id, Profession.Type.PORTER), "Construction storage cannot accept employment")
	var hut := Instance.new(scene.gatherer_hut_data.id, scene.gatherer_hut_data.definition, scene.gatherer_hut_data.position, Instance.State.UNDER_CONSTRUCTION)
	hut.resources.set_capacity(FOOD, 5)
	scene.production.building = hut
	var gatherer = scene.resident_runtimes[2]
	gatherer.data.profession = Profession.Type.GATHERER
	gatherer.data.work_location_id = hut.id
	gatherer.data.activity = Activity.Type.WORKING
	gatherer.view.global_position = hut.position
	hut.production_progress = 12
	scene.production._on_minute(400)
	check(not scene.production.can_work(gatherer.data) and hut.production_progress == 12 and hut.resources.get_amount(FOOD) == 0, "Construction hut neither offers work nor produces even with WORKING resident")
	hut.add_delivered_material(preload("res://scripts/resource_type.gd").Type.WOOD, hut.get_required_amount(preload("res://scripts/resource_type.gd").Type.WOOD))
	hut.add_construction_work(hut.definition.construction_work_required)
	hut.complete_construction()
	scene.production._on_minute(401)
	check(hut.production_progress == 13, "Same instance resumes ordinary production when BUILT")
	check(lines.any(func(line): return "[BUILDING] выбран тип здания" in line) and lines.any(func(line): return "state=UNDER_CONSTRUCTION" in line) and lines.any(func(line): return "placement отменён" in line), "Building INFO covers selection, confirmation and cancellation")

	var hungry = scene.resident_runtimes[0]
	hungry.data.hunger = 60
	check(not hungry.needs.try_eat(2000) and kitchen.resources.get_reserved_out(FOOD) == 0, "Autonomous eat never reserves food in construction kitchen")
	var camera = scene.get_node("World/Camera2D")
	camera.position = Vector2(100, 50)
	camera.force_update_scroll()
	paused = true
	placement.select(Definition.for_type(Types.Type.HOME))
	var shifted_point := Vector2(-450, 200)
	motion.position = screen(scene, shifted_point)
	root.push_input(motion, true)
	adapter.refresh()
	check(adapter.ghost.global_position.is_equal_approx(shifted_point), "Cursor world transform respects moved camera on pause")
	var before_paused_placement: int = scene.buildings.size()
	click(screen(scene, shifted_point))
	check(scene.buildings.size() == before_paused_placement + 1 and not placement.is_active(), "Placement remains usable on pause")
	check(scene.game_time.total_minutes == original_time, "Paused placement does not advance simulation")
	paused = false
	var collision_registry: Array = [Instance.new(&"building_0001", Definition.for_type(Types.Type.HOME), Vector2(1000, 0))]
	var isolated_placement = load("res://scripts/building_placement.gd").new()
	isolated_placement.setup(collision_registry)
	isolated_placement.select(Definition.for_type(Types.Type.HOME))
	var collision_free = isolated_placement.confirm()
	check(collision_free.id == &"building_0002" and collision_registry.size() == 2, "Stable ID allocator skips IDs already in shared registry")
	scene.free()
	print("Building placement: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
