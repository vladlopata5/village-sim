extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd")
const Instance = preload("res://scripts/building_instance.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var checks := 0
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
	var selection = scene.resident_selection
	var card = scene.get_node("HUD/BuildingCard")
	var resident_card = scene.get_node("HUD/ResidentCard")
	var actor = scene.resident_runtimes[0]
	var kitchen = scene.kitchen_data
	var kitchen_view = scene.world_locations.get_view(kitchen.id)
	var warehouse = scene.warehouse_data
	var warehouse_view = scene.world_locations.get_view(warehouse.id)
	var hut = scene.gatherer_hut_data
	var hut_view = scene.world_locations.get_view(hut.id)
	scene.get_node("HUD/DebugPanel").set_collapsed(true)
	await process_frame
	await process_frame
	check(selection.selected_entity == null and not card.visible, "Initially no selected entity or building card")
	selection.select(actor.data)
	click(screen(scene, kitchen.position))
	check(selection.selected_entity == kitchen and selection.selected_building == kitchen and selection.selected_resident == null, "Real built building click selects one simulation entity and clears resident")
	check(card.visible and not resident_card.visible and kitchen_view.selected and not actor.view.selected, "Building card and outline replace resident card/highlight")
	check(card.name_label.text == "Общая кухня" and card.id_label.text == "ID: communal_kitchen_01", "Name and concrete stable ID displayed")
	check(card.state_label.text == "Состояние: Построено" and card.type_label.text == "Тип: Кухня", "Built state and type are readable")
	check(card.resources_label.text == "FOOD: 0 / 20", "Empty kitchen displays configured capacity")
	kitchen.resources.add(FOOD, 7)
	check(card.resources_label.text == "FOOD: 7 / 20", "Resource signal updates card immediately")
	await process_frame
	await process_frame
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		click(card.name_label.get_global_rect().get_center(), button)
		check(selection.selected_building == kitchen and scene.resident_runtimes.all(func(runtime): return runtime.commands.active_command == null) and not scene.interaction_menu.visible, "BuildingCard consumes clicks without world selection/commands/menu")
	# Close first, so warehouse footprint is not behind the right card.
	click(card.close_button.get_global_rect().get_center())
	check(selection.selected_entity == null and not card.visible and not kitchen_view.selected, "Close clears selection/card/outline, keeps building")
	click(screen(scene, warehouse.position))
	check(selection.selected_building == warehouse and warehouse_view.selected and not kitchen_view.selected, "Warehouse selection replaces previous building outline")
	check(card.resources_label.text == "FOOD: 10 / 20" and card.type_label.text == "Тип: Склад", "Warehouse local resources displayed")
	click(screen(scene, hut.position))
	check(selection.selected_building == hut and hut_view.selected and not warehouse_view.selected, "Switching building clears old highlight")
	hut.production_progress = 17
	await process_frame
	check(card.production_section.visible and "17 / 30" in card.production_label.text and "FOOD" in card.production_label.text, "Gatherer shows actual production progress/resource")
	var old_text: String = card.resources_label.text
	warehouse.resources.try_take(FOOD, 1)
	check(card.resources_label.text == old_text, "Previously selected building resource updates do not alter current card")
	var node_count: int = card.get_node("Margin/Column/Scroll/Content").get_child_count()
	card._process(0.0)
	card._process(0.0)
	check(card.get_node("Margin/Column/Scroll/Content").get_child_count() == node_count, "Live refresh reuses existing UI nodes")
	var home = scene.buildings[4]
	var home_view = scene.world_locations.get_view(home.id)
	click(screen(scene, home.position + Vector2(28, 18)))
	check(selection.selected_building == home and home_view.selected, "Starting home selectable throughout its footprint, beyond marker circle")
	check(card.type_label.text == "Тип: Дом" and card.resources_label.text == "Ресурсов нет" and not card.production_section.visible and not card.construction_section.visible, "Home shows basic info without invented housing stats")
	click(screen(scene, actor.view.global_position))
	check(selection.selected_resident == actor.data and selection.selected_building == null and not card.visible and resident_card.visible and not home_view.selected, "Resident click replaces building selection and restores ResidentCard")
	# New construction visual is later than residents in the world tree.
	scene.placement.select(Definition.for_type(Types.Type.GATHERER_HUT))
	scene.placement.update_position(Vector2(-500, 80))
	var construction = scene.placement.confirm()
	var construction_view = scene.world_locations.get_view(construction.id)
	click(screen(scene, construction.position))
	check(selection.selected_building == construction and construction_view.selected and card.visible, "Under-construction building selects and highlights")
	check(card.state_label.text == "Состояние: Строится" and card.construction_section.visible and not card.production_section.visible, "Construction card shows state and construction section")
	check("Древесина: 0 / 10" in card.construction_materials.text and construction.production_progress == 0 and construction.resources.get_capacity(FOOD) == 0, "Construction card uses real requirements without changing output storage")
	construction.add_delivered_material(preload("res://scripts/resource_type.gd").Type.WOOD, 10)
	construction.add_construction_work(180)
	construction.complete_construction()
	check(card.state_label.text == "Состояние: Построено" and not card.construction_section.visible and card.production_section.visible, "Construction signal updates completed state")
	var original_position: Vector2 = actor.view.global_position
	actor.view.global_position = construction.position
	click(screen(scene, construction.position))
	check(selection.selected_resident == actor.data and selection.selected_building == null, "Exact resident hit wins even over later placed construction view")
	actor.view.global_position = original_position
	selection.select_building(construction)
	click(screen(scene, Vector2(0, 280)))
	check(selection.selected_entity == null and not card.visible and not construction_view.selected, "Empty ground clears unified selection")
	selection.select_building(kitchen)
	var count_before: int = scene.buildings.size()
	scene.placement.select(Definition.for_type(Types.Type.HOME))
	click(screen(scene, construction.position))
	check(selection.selected_building == kitchen and scene.buildings.size() == count_before and scene.placement.is_active(), "Invalid placement over construction never selects it")
	click(screen(scene, Vector2(-500, 230)))
	check(selection.selected_building == kitchen and not scene.placement.is_active() and scene.buildings.size() == count_before + 1, "Valid placement does not alter current selection")
	click(scene.construction_panel.collapse_button.get_global_rect().get_center())
	check(selection.selected_building == kitchen, "Construction panel click preserves building selection")
	selection.select(actor.data)
	click(screen(scene, kitchen.position), MOUSE_BUTTON_RIGHT)
	check(selection.selected_resident == actor.data and scene.interaction_menu.visible and actor.commands.active_command == null, "RMB object interaction remains separate from LMB selection")
	scene.interaction_menu.hide()
	var camera = scene.get_node("World/Camera2D")
	camera.position = Vector2(80, 40)
	camera.force_update_scroll()
	paused = true
	click(screen(scene, kitchen.position))
	check(selection.selected_building == kitchen and card.visible, "Building selection works with camera movement and pause")
	click(card.close_button.get_global_rect().get_center())
	check(selection.selected_entity == null and not card.visible, "Close works on pause")
	paused = false
	scene.free()
	print("Building selection: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
