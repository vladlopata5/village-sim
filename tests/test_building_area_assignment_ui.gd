extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const D = preload("res://scripts/building_definition.gd")
const Building = preload("res://scripts/building_instance.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func press(button: Button) -> void:
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button); break
		parent = parent.get_parent()
	await settle()
	F.click(self,button)
func capture(label: String) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w5c1/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	root.size=Vector2i(1600,900)
	var world = F.create(self)
	await settle()
	var pc = world.player_control
	var ui = world.game_ui
	var panel = ui.info_panel
	var card = panel.building_details
	var area_card = panel.area_details
	var areas = world.work_areas_window
	var buildings = world.buildings_window
	var selection = world.resident_selection
	var hut = F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var quarry = F.building(world,T.QUARRY,Vector3(26,0,-20))
	var first = world.work_areas.create(C.to_sim(Vector3(20,0,22)),C.length_to_sim(7))
	var second = world.work_areas.create(C.to_sim(Vector3(-30,0,-8)),C.length_to_sim(10))
	pc.rename_work_area(first.id,"Дальний общий лес")
	pc.rename_work_area(second.id,"Северный лес")
	world._select_building_definition(D.for_type(T.LUMBERJACK_HUT))
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(22,0,22)})
	var site = world.buildings[-1]
	world._cancel_active_world_tool()
	check(not site.is_built(),"Construction fixture is a real unfinished hut")
	var actor = world.resident_runtimes[0]
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var worker = actor.get_node("Lumberjack")
	check(worker.request_work() and worker.kind==&"CHOP","An accepted CHOP exists throughout UI operations")
	var intent = actor.intents.current_intent
	var tree = worker.tree
	world._view_registered_building(hut.id)
	panel.select_tab(&"info")
	await settle()
	check(card.work_area_section.visible and "Стандартная" in card.work_area_label.text and "15.0" in card.work_area_label.text and not card.reset_area_button.visible,"Built hut exposes DEFAULT radius and assignment control")
	var requests: int = world.decision_dispatcher.requests
	var decisions: Array = world.resident_runtimes.map(func(runtime):return runtime.decision.decision_count)
	var routes: Array = []
	var original: Callable = world.logistics.sources.route_available
	world.logistics.sources.route_available=func(start,target): routes.append([start,target]); return original.call(start,target)
	var revision: int = world.navigation.revision
	var views: Array = []
	var assignments: Array = []
	areas.area_selected.connect(func(id):views.append(id))
	areas.assignment_selected.connect(func(id):assignments.append(id))
	await press(card.assign_area_button)
	await settle()
	check(areas.visible and areas.mode==areas.Mode.ASSIGN and hut.display_name in areas.mode_label.text and not areas.create_button.visible,"Building button opens Areas ASSIGN with a clear source caption and no creation shortcut")
	check(selection.selected_building==hut and panel.expanded and card.visible,"Source building card stays selected and expanded")
	check(not areas.get_global_rect().intersects(panel.get_global_rect()) and areas.get_global_rect().encloses(areas.close_button.get_global_rect()),"Area chooser fits beside the real blue card")
	await capture("01-building-choose-area")
	await F.row_click(self,areas,str(first.id))
	check(hut.work_area_override_id==first.id and world._work_updates.has(actor.data.id) and world._work_updates.size()==1,"Actual row assigns only the source hut and uses W5b addressed notification")
	check(selection.selected_building==hut and panel.expanded and not areas.visible and areas.mode==areas.Mode.VIEW and views.is_empty() and assignments==[first.id],"Success closes chooser, resets VIEW and never opens the target area's card")
	check("Пользовательская" in card.work_area_label.text and first.display_name in card.work_area_label.text and str(first.id) in card.work_area_label.text and card.reset_area_button.visible,"Source card immediately displays CUSTOM name and stable ID")
	await capture("02-building-custom-result")
	# VIEW and the existing W2 layer still use their original behavior.
	ui.open_window(&"areas")
	await F.row_click(self,areas,str(first.id))
	check(selection.selected_work_area==first and views==[first.id] and assignments.size()==1,"Reopened Areas VIEW opens a card without assigning again")
	check(hut.display_name in area_card.buildings_label.text and str(hut.id) in area_card.buildings_label.text,"Area card lists actual assigned buildings")
	ui.close_window()
	selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	check(world.work_highlight.circle.position.is_equal_approx(C.to_world(first.center)+Vector3(0,0.02,0)),"W2 reads the CUSTOM assignment created through UI")
	world._view_work_area(first.id)
	world._focus_work_area(first.center)
	var building_views: Array = []
	var building_assignments: Array = []
	buildings.building_selected.connect(func(id):building_views.append(id))
	buildings.assignment_selected.connect(func(id):building_assignments.append(id))
	await press(area_card.assign_building_button)
	await settle()
	check(buildings.visible and buildings.mode==buildings.Mode.ASSIGN and first.display_name in buildings.mode_label.text and not buildings.focus_button.visible,"Area button opens Buildings ASSIGN for the source area")
	check(selection.selected_work_area==first and world.work_highlight.circle.visible and panel.expanded,"Source area card and its contour remain visible")
	pc.rename_work_area(first.id,"Дальний общий лес — общий круг")
	check(first.display_name in buildings.mode_label.text and first.display_name in area_card.title.text,"Renaming the source updates the active assignment caption without losing its identity")
	check(buildings.rows[quarry.id].get_text(2)=="Можно назначить" and buildings.rows[site.id].get_text(2)=="Строится" and buildings.rows[world.warehouse_data.id].get_text(2)=="Нет рабочей области","Chooser distinguishes eligible built extractors, construction and unsupported types")
	await capture("03-area-choose-building")
	await F.row_click(self,buildings,str(world.warehouse_data.id))
	await F.row_click(self,buildings,str(site.id))
	check(building_views.is_empty() and building_assignments.is_empty() and selection.selected_work_area==first and buildings.mode==buildings.Mode.ASSIGN and world.warehouse_data.work_area_override_id.is_empty() and site.work_area_override_id.is_empty(),"Unsupported and unfinished rows never view or assign a building")
	await F.row_click(self,buildings,str(quarry.id))
	check(quarry.work_area_override_id==first.id and hut.work_area_override_id==first.id and pc.get_work_area_buildings(first.id).size()==2,"Both supported building types can share the original area")
	check(selection.selected_work_area==first and panel.expanded and not buildings.visible and buildings.mode==buildings.Mode.VIEW and building_views.is_empty() and building_assignments==[quarry.id],"Reverse assignment preserves the source card and emits only assignment")
	check(str(hut.id) in area_card.buildings_label.text and str(quarry.id) in area_card.buildings_label.text,"Area's building list updates without reopening")
	var paints: int = area_card.refresh_count
	var row_count: int = buildings.row_creation_count
	await settle()
	await settle()
	check(area_card.refresh_count==paints and buildings.row_creation_count==row_count,"Unchanged assignment UI does not recreate rows or repaint the area card every frame")
	await capture("04-area-assigned-buildings")
	world._view_work_area(second.id)
	check("нет назначений" in area_card.buildings_label.text,"Unused area shows an honest empty building list")
	await press(area_card.assign_building_button)
	await F.row_click(self,buildings,str(hut.id))
	check(hut.work_area_override_id==second.id and quarry.work_area_override_id==first.id and actor.data.work_location_id==hut.id,"Reverse assignment replaces one override and preserves worker membership")
	world._view_work_area(first.id)
	check(str(hut.id) not in area_card.buildings_label.text and str(quarry.id) in area_card.buildings_label.text,"Old area's list loses the reassigned building")
	world._view_registered_building(hut.id)
	await press(card.reset_area_button)
	check(hut.work_area_override_id.is_empty() and "Стандартная" in card.work_area_label.text and not card.reset_area_button.visible,"Card reset uses DEFAULT and updates controls immediately")
	await capture("05-building-default")
	selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	check(world.work_highlight.circle.position.is_equal_approx(C.to_world(hut.position)+Vector3(0,0.02,0)),"W2 returns to the standard building circle")
	# Cancellation via button, Esc and normal selection/quick-window changes.
	world._view_registered_building(hut.id)
	await press(card.assign_area_button)
	await press(areas.close_button)
	check(areas.mode==areas.Mode.VIEW and world._area_assignment_source==null and selection.selected_building==hut and panel.expanded and hut.work_area_override_id.is_empty(),"Closing chooser cancels, preserves source card and changes no assignment")
	world._view_work_area(first.id)
	await press(area_card.assign_building_button)
	F.key(self,KEY_ESCAPE)
	check(buildings.mode==buildings.Mode.VIEW and not buildings.visible and selection.selected_work_area==first and quarry.work_area_override_id==first.id,"Esc cancels reverse mode without changing the area or previous assignments")
	await press(area_card.assign_building_button)
	selection.select(actor.data)
	check(buildings.mode==buildings.Mode.VIEW and not buildings.visible and world._area_assignment_source==null,"Ordinary map selection invalidates the source and exits ASSIGN")
	world._view_registered_building(hut.id)
	await press(card.assign_area_button)
	F.click(self,ui.residents_button)
	check(world.settlement_panel.visible and areas.mode==areas.Mode.VIEW and world._area_assignment_source==null and selection.selected_building==hut,"Switching QUICK_WINDOW cancels hidden assignment without closing the source")
	ui.close_window()
	await press(card.assign_area_button)
	pc.unregister_building(hut.id)
	check(not areas.visible and areas.mode==areas.Mode.VIEW and world._area_assignment_source==null,"Removing the source building cancels selection immediately")
	areas.activate_row(second.id)
	check(hut.work_area_override_id.is_empty(),"Stale source cannot receive a deferred assignment")
	world._view_work_area(second.id)
	await press(area_card.assign_building_button)
	pc.remove_work_area(second.id)
	check(not buildings.visible and buildings.mode==buildings.Mode.VIEW and world._area_assignment_source==null and selection.selected_entity==null,"Removing the source area cancels selection and clears its obsolete card")
	buildings.activate_row(quarry.id)
	check(quarry.work_area_override_id==first.id,"Stale area cannot overwrite a valid current assignment")
	# Same ID with a different instance is not the source captured when opening.
	pc.register_building(hut)
	world._view_registered_building(hut.id)
	await press(card.assign_area_button)
	var replacement = Building.new(hut.id,hut.definition,hut.position)
	var index: int = world.buildings.find(hut)
	world.buildings[index]=replacement
	areas.activate_row(first.id)
	check(replacement.work_area_override_id.is_empty() and hut.work_area_override_id.is_empty() and areas.mode==areas.Mode.VIEW,"Source identity is checked beyond its saved ID")
	world.buildings[index]=hut
	world._view_registered_building(quarry.id)
	await press(card.assign_area_button)
	ui.open_window(&"buildings")
	await F.row_click(self,buildings,str(quarry.id))
	check(selection.selected_building==quarry and buildings.mode==buildings.Mode.VIEW and building_views.has(quarry.id),"Normal Buildings VIEW is restored after switching out of ASSIGN")
	ui.close_window()
	world._view_registered_building(world.warehouse_data.id)
	check(not card.work_area_section.visible and panel.building_details.available_tabs().has(&"storage"),"Warehouses retain storage tabs without work-area controls")
	world._view_registered_building(site.id)
	check(not card.work_area_section.visible and not site.is_built(),"Construction cards expose no assignment controls")
	check(actor.intents.current_intent==intent and worker.tree==tree and tree.reservation_owner_id==StringName(actor.data.id),"All UI assignments, resets and cancellations preserve accepted work and its claim")
	check(world.decision_dispatcher.requests==requests and world.resident_runtimes.map(func(runtime):return runtime.decision.decision_count)==decisions and routes.is_empty() and world.navigation.revision==revision,"UI performs no source routes, AI decisions or world/navigation changes")
	world.logistics.sources.route_available=original
	world.free()
	print("Building area assignment UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
