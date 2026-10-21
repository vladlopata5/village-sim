extends "res://tests/test_building_area_assignment_ui.gd"
var observer: Callable
func observe(world: Node,label: String) -> void:
	if observer.is_valid():await observer.call(world,label)
func ordinary_opening() -> void:
	root.size=Vector2i(1600,900)
	var world=F.create(self);var ui=world.game_ui;var areas=world.work_areas_window;var selection=world.resident_selection
	var panel=ui.info_panel;var card=panel.building_details
	var first=world.work_areas.create(C.to_sim(Vector3(-16,0,10)),C.length_to_sim(4))
	var second=world.work_areas.create(C.to_sim(Vector3(20,0,10)),C.length_to_sim(6))
	var buildings: Array=[]
	for type in [T.FARM,T.LUMBERJACK_HUT,T.QUARRY,T.GATHERER_HUT,T.SHEPHERD_HUT]:buildings.append(F.building(world,type,Vector3(-42+buildings.size()*14,0,30)))
	await settle()
	var identity: int=areas.get_instance_id()
	var connections: Array=[areas.context_requested.get_connections().size(),areas.area_selected.get_connections().size(),areas.create_requested.get_connections().size()]
	for building in buildings:
		world._view_registered_building(building.id);panel.select_tab(&"info")
		await press(card.assign_area_button)
		check(areas.visible and areas.create_button.visible and areas.close_button.text=="Закрыть" and not areas.has_method("begin_assignment"),"All five building cards open ordinary Areas with creation")
		check(areas.get_instance_id()==identity and selection.selected_building==building and world._area_assignment_source==null,"One component, source card preserved, no captured assignment mode")
		await observe(world,"01-building-ordinary-areas")
		await F.row_click(self,areas,str(first.id))
		check(world.area_departure_dialog.visible and not world.area_departure_dialog.confirm_button.disabled and building.work_area_override_id.is_empty(),"Normal row uses existing eligible building confirmation")
		await press(world.area_departure_dialog.confirm_button)
		check(building.work_area_override_id==first.id and selection.selected_building==building and not areas.visible,"Real assignment applies only to currently selected building")
		F.click(self,world.construction_panel.buttons[&"areas"]);await settle()
		check(areas.visible and areas.create_button.visible and areas.create_button.visible and selection.selected_building==building,"Green button opens the same interface with the same source")
		await press(areas.close_button)
	check(connections==[areas.context_requested.get_connections().size(),areas.area_selected.get_connections().size(),areas.create_requested.get_connections().size()],"Repeated opening and assignments add no subscriptions")
	# A normal window follows current selection; there is no stale building captured at open.
	world._view_registered_building(buildings[0].id);await press(card.assign_area_button)
	world._view_registered_building(buildings[1].id)
	check(areas.visible and selection.selected_building==buildings[1],"Normal window remains usable when selected building changes")
	await F.row_click(self,areas,str(second.id));await press(world.area_departure_dialog.confirm_button)
	check(buildings[0].work_area_override_id==first.id and buildings[1].work_area_override_id==second.id,"Area never goes to previous card's building")
	# Create through the building button, then perform normal explicit assignment.
	var farm=buildings[0];world._view_registered_building(farm.id);await press(card.assign_area_button)
	var before: int=world.work_areas.all().size()
	await press(areas.create_button)
	check(world.work_area_tool.active() and world.work_area_tool.resident_id.is_empty() and selection.selected_building==farm,"Create from building opens ordinary independent preview")
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-18,0,18)})
	await press(world.area_confirm);await settle()
	var created=world.work_areas.all()[-1]
	check(world.work_areas.all().size()==before+1 and areas.visible and areas.create_button.visible and selection.selected_building==farm and farm.work_area_override_id==first.id,"Creation preserves source and previous assignment without autoassign")
	await observe(world,"02-created-from-building")
	await F.row_click(self,areas,str(created.id));await press(world.area_departure_dialog.confirm_button)
	check(farm.work_area_override_id==created.id,"New area can be assigned using normal procedure")
	# Inspect the same row to reach unchanged editing/deletion controls.
	await press(card.assign_area_button);await F.row_click(self,areas,str(created.id))
	await press(world.area_departure_dialog.view_button)
	var details=panel.area_details
	check(selection.selected_work_area==created and details.edit_button.visible and details.delete_button.visible,"Normal inspection exposes existing edit and delete")
	await press(details.edit_button)
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-17,0,19)})
	world.area_radius_input.text="4";world.area_radius_input.text_changed.emit("4")
	await press(world.area_confirm)
	check(created.center==C.to_sim(Vector3(-17,0,19)) and is_equal_approx(C.length_to_world(created.radius),4) and farm.work_area_override_id==created.id,"Existing edit changes live geometry while retaining assignment")
	await observe(world,"03-edited-area")
	await press(details.delete_button);await press(world.work_area_dialog.confirm_button)
	check(world.work_areas.get_area(created.id)==null and farm.work_area_override_id.is_empty(),"Existing delete removes area and restores building DEFAULT")
	# No selection: ordinary row opens the area card; unsupported building: no assignment.
	selection.clear();F.click(self,world.construction_panel.buttons[&"areas"]);await settle()
	if not areas.visible:F.click(self,world.construction_panel.buttons[&"areas"]);await settle()
	await F.row_click(self,areas,str(second.id))
	check(selection.selected_work_area==second and not world.area_departure_dialog.visible,"No source selection opens ordinary area card")
	world._view_registered_building(world.warehouse_data.id);ui.open_window(&"areas")
	await F.row_click(self,areas,str(first.id))
	check(not world.area_departure_dialog.visible and selection.selected_work_area==first and world.warehouse_data.work_area_override_id.is_empty(),"Unsupported building context opens the area card without an invalid offer")
	await press(world.area_departure_dialog.cancel_button);ui.close_window()
	check(connections==[areas.context_requested.get_connections().size(),areas.area_selected.get_connections().size(),areas.create_requested.get_connections().size()],"Create/edit/delete retain single wiring and no conflicting assignment window")
	world.free()
func run() -> void:
	await ordinary_opening()
	print("UX3 ordinary area opening: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
