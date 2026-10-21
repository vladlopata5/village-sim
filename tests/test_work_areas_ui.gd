extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const P = preload("res://scripts/resident_profession.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func capture(label: String) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	# Let the first rendered container layout reach the viewport texture.
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w3/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	root.size = Vector2i(1600,900)
	var world = F.create(self)
	await settle()
	var window = world.work_areas_window
	var panel = world.game_ui.info_panel
	var card = panel.area_details
	var selection = world.resident_selection
	var actor = world.resident_runtimes[0]
	var second = world.resident_runtimes[1]
	var camera = world.get_node("World/Camera3D")
	F.click(self,world.construction_panel.buttons[&"areas"])
	await settle()
	check(window.visible and window.rows.is_empty() and window.empty_label.visible,"Areas quick button opens a truthful empty list")
	check(not world.settlement_panel.visible and selection.selected_entity == null,"Opening the window is browsing, not object selection")
	check(window.position==Vector2(12,12) and window.size==Vector2(924,476) and window.table.visible,"Empty area window preserves the shared fixed rectangle and table")
	check(window.get_global_rect().encloses(window.create_button.get_global_rect()),"Create button stays inside the window and viewport")
	await capture("01-empty-window")
	check(window.size==Vector2(924,476),"Empty window preserves the fixed rectangle after rendering settles")
	var first = world.work_areas.create(C.to_sim(Vector3(-5,0,8)),C.length_to_sim(15))
	var other = world.work_areas.create(C.to_sim(Vector3(20,0,-10)),C.length_to_sim(9))
	world.player_control.assign_profession(actor.data.id,P.LUMBERJACK)
	world.player_control.assign_profession(second.data.id,P.MINER)
	world.player_control.assign_work_area(actor.data.id,first.id)
	world.player_control.assign_work_area(second.data.id,first.id)
	await settle()
	check(window.rows.size()==2 and not window.empty_label.visible,"Registry additions appear without a new window")
	check(window.rows[first.id].get_text(1)=="15.0" and window.rows[first.id].get_text(2)=="2","List shows world radius and two direct resident assignments")
	await F.row_click(self,window,str(first.id))
	await settle()
	check(selection.selected_work_area == first and selection.selected_resident == null and selection.selected_building == null,"Actual row click exclusively selects WorkArea data")
	check(panel.expanded and panel.active_tab==&"info" and card.visible and not panel.resident_details.visible and not panel.building_details.visible,"Selected area is a full InfoPanel object view")
	check(str(first.id) in card.title.text and "X -5.0, Z 8.0" in card.center_label.text and "15.0" in card.radius_label.text,"Area card displays ID and actual world geometry")
	check(actor.data.resident_name in card.assignments_label.text and second.data.resident_name in card.assignments_label.text,"Card lists exact resident IDs, regardless of profession")
	check(world.work_highlight.circle.visible and world.work_highlight.circle.position.is_equal_approx(C.to_world(first.center)+Vector3(0,0.02,0)),"Selected area uses shared W2 circle independent of assignment")
	var row: TreeItem = window.rows[first.id]
	var mesh = world.work_highlight.circle.mesh
	var creates: int = window.row_creation_count
	var paints: int = card.refresh_count
	var tabs: int = panel.tab_rebuild_count
	var refreshes: int = window.refresh_count
	await settle()
	check(window.refresh_count==refreshes and card.refresh_count==paints,"No per-frame list or card rebuild")
	other.update(other.center,C.length_to_sim(12))
	await settle()
	check(window.rows[first.id]==row and window.table.get_selected()==row and window.row_creation_count==creates,"Other-area update preserves existing rows and the selected row")
	check(card.refresh_count==paints and panel.tab_rebuild_count==tabs and world.work_highlight.circle.mesh==mesh,"Unrelated area change does not repaint card/tabs/selected contour")
	await capture("02-list-and-card")
	var zoom: float = camera.get_zoom_distance()
	F.click(self,card.focus_button)
	await settle()
	check(not window.visible and camera.get_focus_position().is_equal_approx(C.to_world(first.center)) and is_equal_approx(camera.get_zoom_distance(),zoom),"Real focus button closes the list and pans to center while preserving zoom")
	await capture("03-area-on-map")
	first.update(C.to_sim(Vector3(-2,0,8)),first.radius)
	check(world.work_highlight.circle.mesh==mesh and "X -2.0" in card.center_label.text,"Geometry signal updates card and transform without rebuilding same-radius contour")
	first.update(first.center,C.length_to_sim(11))
	check(world.work_highlight.circle.mesh!=mesh and "11.0" in card.radius_label.text,"Radius change updates existing area view")
	world._set_navigation_debug(true)
	check(world.work_highlight.circle.visible,"Navigation debug does not own the chosen area contour")
	world._set_navigation_debug(false)
	panel._close()
	check(selection.selected_entity==null and not world.work_highlight.circle.visible,"Closing blue card clears selection and outline")
	world._view_work_area(other.id)
	check(card.assignments_label.text=="Не используется" and world.work_highlight.circle.visible,"Unassigned area still has its own card and contour")
	selection.select(actor.data)
	check(selection.selected_work_area==null and not card.visible,"Resident selection replaces the area view")
	selection.select_building(world.warehouse_data)
	check(selection.selected_work_area==null and panel.building_details.visible and not world.work_highlight.circle.visible,"Building selection still uses its existing card and clears area contour")
	# Independent creation must neither select nor assign the newly created object.
	selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"bio")
	await settle()
	var assignment: Array = [actor.data.profession,actor.data.work_area_id,actor.data.work_location_id,actor.data.work_assignment_revision]
	var source_queries: Array = []
	var original: Callable = world.logistics.sources.route_available
	world.logistics.sources.route_available = func(start,target): source_queries.append([start,target]); return original.call(start,target)
	var requests: int = world.decision_dispatcher.requests
	var decisions: Array = world.resident_runtimes.map(func(runtime): return runtime.decision.decision_count)
	var nav_revision: int = world.navigation.revision
	F.click(self,world.construction_panel.buttons[&"areas"])
	await settle()
	F.click(self,window.create_button)
	await settle()
	check(world.work_area_tool.active() and world.work_area_tool.resident_id.is_empty() and not window.visible,"Create starts the same tool without a resident target and closes the obstructing list")
	check(selection.selected_resident==actor.data and world.work_areas.all().size()==2,"Starting independent preview preserves selection and registry")
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-9,0,14)})
	check(world.work_area_tool.locked and world.area_confirm.visible,"Existing map click locks independent preview for confirmation")
	await capture("04-independent-preview")
	world.handle_world_click(MOUSE_BUTTON_RIGHT,{})
	check(not world.work_area_tool.active() and not world.area_confirm.visible and world.work_areas.all().size()==2,"Right-click cancel creates no area")
	world._start_work_area()
	check(world.game_ui.try_escape() and not world.work_area_tool.active(),"Escape cancels independent creation through the existing UI stack")
	world._start_work_area()
	world._confirm_work_area()
	check(world.work_areas.all().size()==2 and world.work_area_tool.active(),"Confirm before locking cannot create an unintended origin area")
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-9,0,14)})
	F.click(self,world.area_confirm)
	await settle()
	check(world.work_areas.all().size()==3 and not world.work_area_tool.active() and window.visible,"Real confirmation button registers independent area and reopens list")
	var created = world.work_areas.all()[-1]
	check(created.center==C.to_sim(Vector3(-9,0,14)) and C.length_to_world(created.radius)==15,"Independent area uses selected center and existing 15-world-unit radius")
	check(selection.selected_resident==actor.data and assignment==[actor.data.profession,actor.data.work_area_id,actor.data.work_location_id,actor.data.work_assignment_revision],"Independent creation changes neither selected resident nor assignment")
	check(window.rows[created.id].get_text(2)=="0" and window.rows.size()==3,"New independent row truthfully has no assigned workers")
	check(world.decision_dispatcher.requests==requests and world.resident_runtimes.map(func(runtime): return runtime.decision.decision_count)==decisions and world._work_updates.is_empty(),"Creating unrelated area and browsing cause zero AI requests or decisions")
	check(source_queries.is_empty() and world.navigation.revision==nav_revision,"Creation and viewing neither query source routes nor change navigation")
	world.logistics.sources.route_available = original
	await capture("05-created-list")
	window.activate_row(created.id)
	if world.area_departure_dialog.visible: world.area_departure_dialog.view_button.pressed.emit()
	check(selection.selected_work_area==created and card.assignments_label.text=="Не используется","Created area can subsequently be browsed without assignment")
	window.hide()
	check(world.work_areas.get_area(created.id)==created,"Closing window does not delete areas")
	world.work_areas.remove(created.id)
	check(selection.selected_entity==null and not world.work_highlight.circle.visible,"Removed selected area safely clears its card and highlight")
	# Existing resident-card workflow remains an assignment, with its original semantics.
	selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	world.resident_card_view().area_button.pressed.emit()
	check(window.visible and window.create_button.visible and selection.selected_resident==actor.data,"Resident button chooses an existing area without changing the source selection")
	world.game_ui.close_window()
	# Legacy tool API remains covered; creation in ordinary VIEW is still independent.
	world._start_work_area(actor.data.id)
	check(world.work_area_tool.resident_id==actor.data.id,"Existing resident-targeted tool API keeps its explicit creation context")
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-24,0,-20)})
	world._confirm_work_area()
	await settle()
	check(actor.data.work_area_id!=first.id and selection.selected_resident==actor.data,"Original confirmation assigns new area and retains resident selection")
	world._start_work_area(actor.data.id)
	var old_id: StringName = actor.data.work_area_id
	world._cancel_work_area()
	check(actor.data.work_area_id==old_id,"Cancelling resident-targeted creation preserves prior assignment")
	# Only affected assignments retain the existing geometry-change notification.
	await settle()
	first.update(first.center,C.length_to_sim(13))
	check(world._work_updates.has(second.data.id) and not world._work_updates.has(actor.data.id),"Geometry change notifies only residents referencing that area")
	await settle()
	world.player_control.clear_work_assignment(second.data.id)
	await settle()
	world._view_work_area(first.id)
	check(card.assignments_label.text=="Не используется","Unassignment removes actual card links")
	var connections: int = world.work_areas.changed.get_connections().size()
	window.queue_free()
	await settle()
	check(world.work_areas.changed.get_connections().size()==connections-1,"Area window teardown disconnects registry subscription")
	world.free()
	print("Work areas UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
