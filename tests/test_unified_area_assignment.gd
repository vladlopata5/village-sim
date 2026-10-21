extends "res://tests/test_resident_area_assignment_ui.gd"
const D=preload("res://scripts/building_definition.gd")
const Building=preload("res://scripts/building_instance.gd")
const Area=preload("res://scripts/work_area.gd")
var observer: Callable
var events: Array=[]
func observe(scene: Node, label: String) -> void:
	if observer.is_valid(): await observer.call(scene,label)
func clean_offer(scene: Node) -> bool:
	return scene._area_assignment_source==null and scene._resident_area_offer.is_empty() and scene._building_area_offer.is_empty() and not scene.area_departure_dialog.visible
func select_source(scene: Node, direction: String, building: RefCounted, resident: RefCounted, area: RefCounted) -> void:
	if direction=="A": scene._view_registered_building(building.id)
	elif direction=="B":
		scene.resident_selection.select(resident)
		scene.game_ui.info_panel.set_expanded(true)
		scene.game_ui.info_panel.select_tab(&"work")
	else: scene._view_work_area(area.id)
func list_for(scene: Node, direction: String) -> Control:
	if direction=="C": return scene.buildings_window
	if direction=="D": return scene.settlement_panel
	return scene.work_areas_window
func open_list(scene: Node, direction: String, path: String) -> void:
	await settle()
	var key: StringName=&"buildings" if direction=="C" else (&"residents" if direction=="D" else &"areas")
	var button: Button
	if direction=="A": button=scene.building_card_view().assign_area_button
	elif direction=="B": button=scene.resident_card_view().area_button
	elif direction=="C": button=scene.game_ui.info_panel.area_details.assign_building_button
	else: button=scene.game_ui.info_panel.area_details.assign_resident_button
	if path=="green": F.click(self,scene.construction_panel.buttons[key])
	else:
		if path=="already": scene.game_ui.open_window(key)
		await press(button)
		if path=="reopen":
			await press(list_for(scene,direction).close_button)
			await press(button)
	await settle()
func row(scene: Node, direction: String, building: RefCounted, resident: RefCounted, area: RefCounted) -> void:
	var id: String=str(building.id) if direction=="C" else (resident.id if direction=="D" else str(area.id))
	await F.row_click(self,list_for(scene,direction),id)
func setup_scene() -> Dictionary:
	var scene=F.create(self)
	var hut=F.building(scene,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var farm=F.building(scene,T.FARM,Vector3(-38,0,30))
	var area=scene.work_areas.create(C.to_sim(Vector3(12,0,18)),C.length_to_sim(8))
	var actor=scene.resident_runtimes[0]
	scene.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	return {"scene":scene,"hut":hut,"farm":farm,"area":area,"actor":actor}
func run() -> void:
	root.size=Vector2i(1600,900)
	var f=setup_scene();var scene=f.scene;var pc=scene.player_control
	var area=f.area;var actor=f.actor;var farm=f.farm;var hut=f.hut
	pc.assign_building_work_area(hut.id,area.id)
	pc.building_work_area_changed.connect(func(id): events.append(["building",id]))
	pc.work_assignment_changed.connect(func(id): events.append(["resident",id]))
	var connection_counts: Array=[scene.work_areas_window.context_requested.get_connections().size(),scene.buildings_window.context_requested.get_connections().size(),scene.settlement_panel.context_requested.get_connections().size()]
	for direction in ["A","B","C","D"]:
		for path in ["green","card","reopen","already"]:
			scene.game_ui.close_window()
			pc.reset_building_work_area(farm.id)
			pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
			select_source(scene,direction,farm,actor.data,area)
			await open_list(scene,direction,path)
			var window=list_for(scene,direction)
			var source=scene.resident_selection.selected_entity
			check(window.visible and window.close_button.text=="Закрыть" and not window.has_method("begin_assignment"),"%s/%s: same ordinary window without a special mode"%[direction,path])
			check(clean_offer(scene),"Opening alone never captures a pair")
			if direction in ["A","B"]: check(scene.work_areas_window.create_button.visible,"Creation remains available through every opening")
			if direction=="C": check(scene.buildings_window.focus_button.visible,"Ordinary building focus remains present")
			var before_events: int=events.size()
			await row(scene,direction,farm,actor.data,area)
			check(scene.area_departure_dialog.visible and scene.resident_selection.selected_entity==source and events.size()==before_events,"Row offers the pair without selection or domain mutation")
			if direction in ["B","D"]: check(hut.display_name in scene.area_departure_dialog.warning.text,"Personal area warns before leaving the current workplace")
			if path=="green": await observe(scene,direction+"-offer")
			await press(scene.area_departure_dialog.cancel_button)
			check(clean_offer(scene) and window.visible and events.size()==before_events,"Cancel discards only the proposal and retains ordinary browsing")
			await row(scene,direction,farm,actor.data,area)
			await press(scene.area_departure_dialog.confirm_button)
			check(clean_offer(scene) and not window.visible and scene.resident_selection.selected_entity==source,"Successful confirmation clears all proposal state and keeps the source card")
			check(events.size()==before_events+1,"Changed assignment emits its single existing domain event")
			if direction in ["A","C"]:
				check(farm.work_area_override_id==area.id and actor.data.work_location_id==hut.id and actor.data.work_area_id.is_empty(),"Building pair changes only its override")
			else:
				check(actor.data.work_area_id==area.id and actor.data.work_location_id.is_empty() and hut.work_area_override_id==area.id and farm.work_area_override_id.is_empty(),"Personal pair never modifies the building area")
			scene.area_departure_dialog.confirmed.emit()
			check(events.size()==before_events+1,"Late duplicate confirmation cannot mutate again")
			if path=="green": await observe(scene,direction+"-result")
		# Inspecting the clicked object never commits the proposed link.
		pc.reset_building_work_area(farm.id);pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
		select_source(scene,direction,farm,actor.data,area);await open_list(scene,direction,"card")
		var count: int=events.size()
		await row(scene,direction,farm,actor.data,area)
		var target: RefCounted=farm if direction=="C" else (actor.data if direction=="D" else area)
		await press(scene.area_departure_dialog.view_button)
		check(scene.resident_selection.selected_entity==target and clean_offer(scene) and events.size()==count,"Inspect opens the clicked target card without assignment in "+direction)
		scene.game_ui.info_panel._close();scene.area_departure_dialog.confirmed.emit()
		check(clean_offer(scene) and events.size()==count,"Closing inspected card cannot revive an offer")
	check(connection_counts==[scene.work_areas_window.context_requested.get_connections().size(),scene.buildings_window.context_requested.get_connections().size(),scene.settlement_panel.context_requested.get_connections().size()],"Every repeated opening retains single signal wiring")
	await ordinary_checks(scene,actor,hut,farm,area)
	scene.free();await process_frame
	for mutation in ["selection","card_close","window_close","escape","switch","geometry","source_remove","target_remove","building_source_remove","building_target_remove","resident_source_remove","source_building_identity","building_geometry","building_inactive","building_identity","resident_identity","area_identity","profession","workplace","close_callback","inspect_callback"]:
		await stale_check(mutation)
	print("Unified area assignment: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func ordinary_checks(scene: Node, actor: Node, hut: RefCounted, farm: RefCounted, area: RefCounted) -> void:
	var pc=scene.player_control;var selection=scene.resident_selection
	for direction in ["A","B","C","D"]:
		selection.clear();await open_list_without_card(scene,direction)
		await row(scene,direction,farm,actor.data,area)
		var target: RefCounted=farm if direction=="C" else (actor.data if direction=="D" else area)
		check(selection.selected_entity==target and clean_offer(scene),"No context opens the ordinary card in "+direction)
		if direction=="C": await observe(scene,"ordinary-building-card")
	# Unsupported context/recipient retains inspection, never an invalid offer.
	scene._select_building_definition(D.for_type(T.LUMBERJACK_HUT))
	scene.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(22,0,22)})
	var site=scene.buildings[-1]
	scene._cancel_active_world_tool()
	check(not site.is_built(),"Unfinished recipient fixture is a real construction")
	for target in [scene.warehouse_data,site]:
		scene._view_work_area(area.id);scene.game_ui.open_window(&"buildings")
		await F.row_click(self,scene.buildings_window,str(target.id))
		check(selection.selected_building==target and clean_offer(scene),"Unsupported reverse building is inspectable")
	pc.assign_profession(scene.residents[1].id,P.MINER)
	scene._view_work_area(area.id);scene.game_ui.open_window(&"residents");await settle()
	await F.row_click(self,scene.settlement_panel,scene.residents[1].id)
	check(scene.area_departure_dialog.visible,"Free miner supports a confirmed personal area")
	await press(scene.area_departure_dialog.confirm_button)
	check(scene.residents[1].work_area_id==area.id,"Free miner assignment is committed")
	for role in [P.GATHERER,P.FARMER,P.SHEPHERD,P.COOK]:
		pc.assign_profession(scene.residents[2].id,role)
		scene._view_work_area(area.id);scene.game_ui.open_window(&"residents");await settle()
		await F.row_click(self,scene.settlement_panel,scene.residents[2].id)
		check(selection.selected_resident==scene.residents[2] and clean_offer(scene) and scene.residents[2].work_area_id.is_empty(),"Building-area profession only opens a card")
		if role==P.GATHERER: await observe(scene,"unsupported-resident-card")
		scene.game_ui.open_window(&"areas");await F.row_click(self,scene.work_areas_window,str(area.id))
		check(selection.selected_work_area==area and clean_offer(scene),"Unsupported personal context only inspects the area")
	# Selection is live until a row, regardless of the button used to open.
	select_source(scene,"B",farm,actor.data,area);await open_list(scene,"B","card")
	scene._view_registered_building(farm.id)
	await row(scene,"A",farm,actor.data,area)
	check(not scene._building_area_offer.is_empty() and scene._resident_area_offer.is_empty(),"Pre-row source change uses the current building rather than an opening-time resident")
	await press(scene.area_departure_dialog.cancel_button);scene.game_ui.close_window()
	# Quick existing choice uses the same confirmation without a list mode.
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK);select_source(scene,"B",farm,actor.data,area)
	scene.resident_card_view()._choose_area(1)
	check(scene.area_departure_dialog.visible and actor.data.work_location_id==hut.id,"Quick existing choice cannot skip confirmation")
	await press(scene.area_departure_dialog.cancel_button);scene.game_ui.close_window()
	# Creation from the resident card remains independent and returns the same list.
	select_source(scene,"B",farm,actor.data,area);await open_list(scene,"B","card")
	var count: int=scene.work_areas.all().size()
	var old_area: StringName=actor.data.work_area_id
	await press(scene.work_areas_window.create_button)
	check(scene.work_area_tool.active() and scene.work_area_tool.resident_id.is_empty(),"Resident list creation starts an independent preview")
	scene.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(0,0,24)})
	await press(scene.area_confirm);await settle()
	check(scene.work_areas.all().size()==count+1 and scene.work_areas_window.visible and actor.data.work_area_id==old_area and clean_offer(scene),"Creating an area never autoassigns the selected resident")
	scene.game_ui.close_window()
	# Ordinary workplace assignment remains independent of WorkArea.
	selection.select(actor.data);scene.game_ui.open_window(&"buildings");await settle()
	await F.row_click(self,scene.buildings_window,str(hut.id))
	check(scene.assignment_dialog.visible and not scene.area_departure_dialog.visible,"Resident to building still opens ordinary workplace assignment")
	scene.assignment_dialog.close();scene.game_ui.close_window()
	# Existing resident filters survive card and green-panel openings alike.
	var people=scene.settlement_panel
	people.search.text=actor.data.resident_name
	people.search.text_changed.emit(people.search.text)
	scene._view_work_area(area.id);await open_list(scene,"D","card")
	check(people.search.text==actor.data.resident_name and people.visible_ids==[actor.data.id],"Area button preserves ordinary resident search: %s / %s / %s"%[people.search.text,people.visible_ids,actor.data.id])
	scene.game_ui.close_window();await open_list(scene,"D","green")
	check(people.search.text==actor.data.resident_name and people.visible_ids==[actor.data.id],"Green-panel opening preserves filter: %s / %s / %s"%[people.search.text,people.visible_ids,actor.data.id])
	scene.game_ui.close_window();people.search.text="";people.search.text_changed.emit("")
	await observe(scene,"ordinary-inspection")
func open_list_without_card(scene: Node, direction: String) -> void:
	scene.game_ui.open_window(&"buildings" if direction=="C" else (&"residents" if direction=="D" else &"areas"))
	await settle()
func stale_check(mutation: String) -> void:
	var f=setup_scene();var scene=f.scene;var actor=f.actor;var area=f.area;var pc=scene.player_control
	var building_pair: bool=mutation in ["building_identity","building_target_remove","building_geometry","building_inactive"]
	var direction: String="C" if building_pair else "D"
	if mutation in ["building_source_remove","source_building_identity"]: direction="A"
	elif mutation=="resident_source_remove": direction="B"
	select_source(scene,direction,f.farm,actor.data,area);await open_list(scene,direction,"card")
	await row(scene,direction,f.farm,actor.data,area)
	check(scene.area_departure_dialog.visible,"Stale fixture has a concrete confirmed pair: "+mutation)
	if mutation=="selection": scene.resident_selection.select(scene.residents[1])
	elif mutation=="card_close": scene.game_ui.info_panel._close()
	elif mutation=="window_close": scene.game_ui.close_window()
	elif mutation=="escape": F.key(self,KEY_ESCAPE)
	elif mutation=="switch": scene.game_ui.open_window(&"areas")
	elif mutation in ["geometry","building_geometry"]: pc.edit_work_area(area.id,area.center+Vector2(25,0),area.radius)
	elif mutation=="source_remove": pc.remove_work_area(area.id)
	elif mutation in ["target_remove","resident_source_remove"]: pc.unregister_resident(actor.data.id)
	elif mutation in ["building_source_remove","building_target_remove"]: pc.unregister_building(f.farm.id)
	elif mutation=="building_inactive": check(pc.change_construction_direction(f.farm.id,true) and not f.farm.is_built(),"Demolition invalidates a built recipient through the actual lifecycle")
	elif mutation in ["building_identity","source_building_identity"]:
		var replacement=Building.new(f.farm.id,f.farm.definition,f.farm.position)
		scene.buildings[scene.buildings.find(f.farm)]=replacement
	elif mutation=="resident_identity":
		var replacement=Resident.new(actor.data.id,"Replacement",30);replacement.profession=P.LUMBERJACK
		pc._residents[actor.data.id]=replacement
	elif mutation=="area_identity": scene.work_areas._areas[area.id]=Area.new(area.id,area.center,area.radius)
	elif mutation=="profession": pc.assign_profession(actor.data.id,P.COOK)
	elif mutation=="workplace": pc.clear_work_assignment(actor.data.id)
	elif mutation in ["close_callback","inspect_callback"]:
		var callback: Callable=func():
			if not scene.area_departure_dialog.visible: pc.assign_profession(actor.data.id,P.COOK)
		scene.area_departure_dialog.visibility_changed.connect(callback,CONNECT_ONE_SHOT)
		if mutation=="inspect_callback": await press(scene.area_departure_dialog.view_button)
	scene.area_departure_dialog.confirmed.emit()
	check(actor.data.work_area_id.is_empty() and f.farm.work_area_override_id.is_empty(),"Stale proposal cannot assign: "+mutation)
	if mutation in ["building_identity","source_building_identity"]: check(pc.get_building(f.farm.id).work_area_override_id.is_empty(),"Replacement building cannot receive an old command")
	elif mutation=="resident_identity": check(pc.get_resident(actor.data.id).work_area_id.is_empty(),"Replacement resident cannot receive an old command")
	if mutation=="inspect_callback": check(scene.resident_selection.selected_work_area==area,"Invalidated inspection callback cannot navigate to an obsolete pair")
	if scene.area_departure_dialog.visible: scene.area_departure_dialog.close()
	if mutation=="selection": await observe(scene,"stale-selection-cancelled")
	check(clean_offer(scene),"Stale or cancelled proposal leaves no hidden assignment: "+mutation)
	scene.game_ui.close_window();scene.game_ui.open_window(&"areas")
	check(clean_offer(scene) and scene.work_areas_window.create_button.visible,"Reopening does not revive a stale proposal")
	scene.free();await process_frame
