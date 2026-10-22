extends "res://tests/test_textile_production.gd"
const CatalogData=preload("res://scripts/ui/construction_catalog_data.gd")
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
var observer: Callable
func observe(world: Node,label: String) -> void:
	if observer.is_valid():await observer.call(world,label)
func ui_click(world: Node,control: Control) -> void:
	await process_frame;await process_frame
	world.building_card_view()._widget("Scroll").ensure_control_visible(control)
	await process_frame;await process_frame
	check(control.is_visible_in_tree(),"Target control visible before actual click")
	F.click(self,control);await process_frame;await process_frame
func run() -> void:
	root.size=Vector2i(1600,900)
	var world=F.create(self)
	var entries: Array=CatalogData.categories()[0].entries
	for type in [T.CLAY_HUT,T.POTTERY_WORKSHOP]:check(entries.any(func(entry):return entry.definition.type==type),"Both CL1 types present in existing production catalog")
	check(preload("res://scripts/resident_profession.gd").display_name(P.CLAY_DIGGER)=="Глинокоп" and preload("res://scripts/resident_profession.gd").display_name(P.POTTER)=="Гончар","New roles have explicit localized names")
	world.construction_panel.set_collapsed(false)
	var catalog=world.construction_panel.catalogue
	catalog.select_category(&"production")
	for type in [T.CLAY_HUT,T.POTTERY_WORKSHOP]:
		await process_frame;await process_frame
		var tile: Button=catalog.tile_for_type(type)
		catalog._scroll.ensure_control_visible(tile)
		await process_frame;await process_frame
		F.click(self,tile)
		check(world.placement.is_active() and world.placement.selected_definition.type==type,"Actual scrolled catalog tile selects correct CL1 construction tool")
		world._cancel_active_world_tool()
	world.construction_panel.set_collapsed(true)
	var camera: Camera3D=world.get_node("World/Camera3D")
	camera.set_process(false);camera.set_physics_process(false);camera.position=Vector3(-20,26,42);camera.look_at(Vector3(-20,0,16))
	var panel=world.developer_panel
	F.key(self,KEY_F10);await process_frame
	check(panel.visible,"Real F10 opens developer panel")
	panel._tabs.current_tab=1;await process_frame;await process_frame
	var buttons: Array=panel._tabs.get_child(1).get_children().filter(func(node):return node is Button and node.text=="Создать залежь глины")
	check(buttons.size()==1,"Existing Resources tab exposes one natural clay tool")
	F.click(self,buttons[0]);await process_frame
	check(panel.placement_kind==&"clay_deposit","Real button enters natural deposit placement")
	var screen: Vector2=camera.unproject_position(Vector3(-20,0,16))
	check(not panel.get_global_rect().has_point(screen),"World target lies outside developer panel")
	var before: int=world.rocks.size()
	F.click_at(self,screen);await physics_frame;await process_frame
	check(world.rocks.size()==before+1 and not panel.active() and panel.status.text.contains("10 единиц"),"Real world click creates finite clay and finishes placement")
	await observe(world,"ui-f10-clay")
	F.key(self,KEY_F10);await process_frame
	var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16))
	var pottery=F.building(world,T.POTTERY_WORKSHOP,Vector3(5,0,16))
	world.resident_selection.select_building(hut);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(&"info")
	var card=world.building_card_view()
	check(card.staffing_buttons.has(P.CLAY_DIGGER) and card.staffing_buttons.has(P.PORTER) and card.resources_label.text.contains("Глина: 0 / 12") and card.work_area_section.visible,"Hut card exposes actual staffing, clay buffer and building area")
	check(not card.upgrade_section.visible,"No unsupported upgrade button")
	await observe(world,"ui-clay-hut")
	world.resident_selection.select_building(pottery);world.game_ui.info_panel.select_tab(&"production");await process_frame
	var view=card.recipe_views[&"fire_brick"]
	check(view.title.text=="Кирпич" and view.composition.text.contains("Глина ×1 → Кирпич ×1") and view.composition.text.contains("30 рабочих минут") and view.composition.text.contains("Топливо ×1"),"Recipe UI reads exact generic recipe/fuel contract")
	check(card.staffing_buttons.has(P.POTTER) and card.staffing_buttons.has(P.PORTER),"Pottery staffing includes both existing worker/courier roles")
	view.mode.select(B.ProductionMode.ORDER);view.mode.item_selected.emit(B.ProductionMode.ORDER);view.amount.text="2";view.amount.text_changed.emit("2")
	await ui_click(world,view.apply_button)
	check(pottery.get_recipe_mode(&"fire_brick")==B.ProductionMode.ORDER and pottery.get_order_remaining(&"fire_brick")==2,"Actual Apply click uses common player recipe command")
	await observe(world,"ui-pottery-recipe")
	world.game_ui.info_panel.select_tab(&"info");await process_frame
	check(card.resources_label.text.contains("Глина: 0 / 10") and card.resources_label.text.contains("Кирпич: 0 / 10") and card.consumable_rows[&"fuel"].label.text.contains("0 / 20"),"Physical stocks and separate numerical fuel are shown")
	await observe(world,"ui-pottery-stocks")
	world.resident_selection.select_building(world.warehouse_data);world.game_ui.info_panel.select_tab(&"storage");await process_frame
	check(card.storage_rows.has(C.CLAY) and card.storage_rows.has(C.BRICK),"Warehouse category quota editor includes both new physical goods")
	await observe(world,"ui-warehouse-clay-brick")
	world.free();await process_frame
	print("Clay UI: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
