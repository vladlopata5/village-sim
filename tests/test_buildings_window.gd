extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const D = preload("res://scripts/building_definition.gd")
const BuildingsWindow = preload("res://scripts/ui/buildings_window.gd")
const Player = preload("res://scripts/player_control.gd")
const Selection = preload("res://scripts/resident_selection.gd")
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
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w5a/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	root.size = Vector2i(1600,900)
	var world = F.create(self)
	await settle()
	var window = world.buildings_window
	var ui = world.game_ui
	var panel = ui.info_panel
	var pc = world.player_control
	var selection = world.resident_selection
	var camera = world.get_node("World/Camera3D")
	var actor = world.resident_runtimes[0]
	var hut = F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	world._select_building_definition(D.for_type(T.STORAGE))
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(22,0,22)})
	var site = world.buildings[-1]
	world._cancel_active_world_tool()
	check(not site.is_built() and pc.get_building(site.id)==site,"Real placement creates an existing registered construction object")
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var worker = actor.get_node("Lumberjack")
	check(worker.request_work() and worker.kind==&"CHOP","A real accepted job exists during UI checks")
	var intent = actor.intents.current_intent
	var tree = worker.tree
	selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	var hut_view = world.world_locations.get_view(hut.id)
	check(hut_view.indicator.visible and world.work_highlight.circle.visible,"W2 highlights an assigned idle/work resident before opening the window")
	F.click(self,world.construction_panel.buttons[&"buildings"])
	await settle()
	check(window.visible and not world.settlement_panel.visible and not world.work_areas_window.visible,"Buildings quick button uses the existing exclusive GameUI window slot")
	check(selection.selected_resident==actor.data and hut_view.indicator.visible and world.work_highlight.circle.visible,"Opening a window preserves resident selection and W2 work highlight")
	check(window.position==Vector2(12,12) and window.size.x<=924 and window.size.y==476 and window.get_global_rect().encloses(window.close_button.get_global_rect()) and not window.get_global_rect().intersects(panel.get_global_rect()),"Building list/footer fit 1600x900 and leave the actual blue card unobscured")
	check(window.rows.size()==pc.get_buildings().size() and window.rows[hut.id].get_text(0)==hut.display_name and window.rows[hut.id].get_text(2)=="Построено" and window.rows[site.id].get_text(2)=="Строится","Same built instances and real construction sites appear in the list")
	check(window.rows[hut.id].get_text(1)==preload("res://scripts/resident_profession.gd").display_name(hut.definition.worker_profession),"Type/purpose comes from existing BuildingDefinition roles")
	var clone: Array = pc.get_buildings()
	clone.clear()
	check(pc.get_building(hut.id)==hut,"Read-only registry array cannot remove actual buildings")
	await capture("01-built-and-building")
	var source_queries: Array = []
	var original: Callable = world.logistics.sources.route_available
	world.logistics.sources.route_available = func(start,target): source_queries.append([start,target]); return original.call(start,target)
	var requests: int = world.decision_dispatcher.requests
	var decisions: Array = world.resident_runtimes.map(func(runtime): return runtime.decision.decision_count)
	var nav_revision: int = world.navigation.revision
	var resources: Dictionary = site.construction_delivered
	var reserved: int = hut.resources.get_reserved_out(R.LOG)
	await F.row_click(self,window,str(hut.id))
	check(selection.selected_resident==actor.data and world.assignment_dialog.visible,"Row offers an action without replacing the resident context")
	await settle()
	F.click(self,world.assignment_dialog.view_button)
	await settle()
	check(selection.selected_building==hut and selection.selected_resident==null and panel.building_details==world.building_card_view() and panel.expanded,"Actual row click opens the existing building card as the single selected object")
	check(hut_view.indicator.visible and not world.work_highlight.circle.visible,"Ordinary building highlight replaces resident work-area highlight")
	var row: TreeItem = window.rows[hut.id]
	var rows_created: int = window.row_creation_count
	var refreshes: int = window.refresh_count
	var zoom: float = camera.get_zoom_distance()
	var rotation: Vector3 = camera.rotation
	await capture("02-selected-building-card")
	F.click(self,window.focus_button)
	await settle()
	check(not window.visible and camera.get_focus_position().is_equal_approx(C.to_world(hut.position)) and is_equal_approx(camera.get_zoom_distance(),zoom) and camera.rotation==rotation,"Show on map closes the list and pans to the actual building without zoom/rotation changes")
	check(selection.selected_building==hut and actor.intents.current_intent==intent and worker.tree==tree and tree.reservation_owner_id==StringName(actor.data.id) and site.construction_delivered==resources and hut.resources.get_reserved_out(R.LOG)==reserved,"Focus preserves building selection, accepted work and resource/reservation data")
	await capture("03-focused-building")
	F.click(self,world.construction_panel.buttons[&"buildings"])
	await settle()
	check(window.rows[hut.id]==row and window.row_creation_count==rows_created and window.refresh_count==refreshes,"Reopening an unchanged list reuses its rows and does not repaint")
	await F.row_click(self,window,str(site.id))
	await settle()
	check(selection.selected_building==site and not hut_view.indicator.visible and world.world_locations.get_view(site.id).indicator.visible,"Selecting a site removes the old building highlight")
	F.click(self,window.focus_button)
	await settle()
	check(camera.get_focus_position().is_equal_approx(C.to_world(site.position)) and selection.selected_building==site,"Construction-site focus uses its own real position")
	check(world.decision_dispatcher.requests==requests and world.resident_runtimes.map(func(runtime): return runtime.decision.decision_count)==decisions and source_queries.is_empty() and world.navigation.revision==nav_revision,"Browsing, selecting and focusing generate no AI requests or source-route queries")
	world.logistics.sources.route_available = original
	ui.open_window(&"buildings")
	await settle()
	# Repeated construction signals that do not change visible columns must be cheap.
	refreshes = window.refresh_count
	site.reserve_construction_material(R.LOG,1)
	site.release_construction_material(R.LOG,1)
	site.add_construction_work(1)
	await settle()
	check(window.refresh_count==refreshes and window.row_creation_count==rows_created,"Progress and reservations do not repaint unchanged list columns")
	await F.row_click(self,window,str(hut.id))
	await settle()
	preload("res://tests/construction_recipe_expectations.gd").complete(site,false)
	check(site.complete_construction(),"Existing completion API finishes the same construction entity")
	await settle()
	check(window.rows[site.id].get_text(2)=="Построено" and window.rows[hut.id]==row and window.table.get_selected()==row and selection.selected_building==hut,"Completion updates state while preserving the other selected row/card")
	check(window.row_creation_count==rows_created,"Completion does not replace existing rows or instances")
	var addition = F.building(world,T.SAWMILL,Vector3(-12,0,8))
	await settle()
	check(window.rows.has(addition.id) and pc.get_building(addition.id)==addition and window.table.get_selected()==row,"Debug registration appends the actual building without losing selection")
	# Real cancellation removes the selected site and its row safely.
	world._select_building_definition(D.for_type(T.HOME))
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(8,0,-25)})
	var cancelled = world.buildings[-1]
	world._cancel_active_world_tool()
	await settle()
	window.activate_row(cancelled.id)
	check(selection.selected_building==cancelled,"New real construction can be selected immediately")
	check(world.cancel_construction(cancelled.id),"Existing cancellation API removes the selected site")
	await settle()
	check(not window.rows.has(cancelled.id) and selection.selected_entity==null and not panel.expanded,"Removal clears stale row, object selection and blue card")
	window.activate_row(cancelled.id)
	check(selection.selected_entity==null,"Stale row activation cannot restore a removed building")
	# Other windows, Esc, building tools and work-area editing keep their old contracts.
	selection.select_building(hut)
	F.click(self,window.close_button)
	check(not window.visible and selection.selected_building==hut and pc.get_building(hut.id)==hut and actor.intents.current_intent==intent,"Closing Buildings keeps selection, entity and accepted work")
	F.click(self,ui.residents_button)
	await settle()
	check(world.settlement_panel.visible and not window.visible,"Residents window still opens")
	F.key(self,KEY_ESCAPE)
	check(not world.settlement_panel.visible and selection.selected_building==hut,"Esc closes only the active window")
	F.click(self,world.construction_panel.buttons[&"areas"])
	await settle()
	check(world.work_areas_window.visible and not window.visible,"Areas window still uses the same coordinator")
	F.key(self,KEY_ESCAPE)
	world._select_building_definition(D.for_type(T.HOME))
	ui.open_window(&"buildings")
	F.key(self,KEY_ESCAPE)
	check(world.placement.is_active() and not window.visible,"Closing Buildings leaves an active construction tool intact")
	F.key(self,KEY_ESCAPE)
	check(not world.placement.is_active(),"Next Esc still cancels the ordinary construction tool")
	var area = world.work_areas.create(C.to_sim(Vector3(-10,0,-15)),C.length_to_sim(15))
	world._view_work_area(area.id)
	world._edit_work_area(area.id)
	world._cancel_work_area()
	check(selection.selected_work_area==area and not world.work_area_tool.active(),"WorkArea card/edit cancellation still works")
	# Standalone empty-registry view, using existing UI nodes rather than a new fixture framework.
	var empty_player = Player.new()
	empty_player.setup([],[])
	var empty_selection = Selection.new()
	root.add_child(empty_selection)
	var empty_window = BuildingsWindow.new()
	ui.get_node("Windows").add_child(empty_window)
	empty_window.setup(empty_player,empty_selection)
	empty_window.show()
	await settle()
	check(empty_window.empty_label.visible and empty_window.rows.is_empty() and empty_window.focus_button.disabled,"An empty real registry has a truthful empty state and disabled focus")
	empty_window.free()
	empty_selection.free()
	var connections: int = hut.construction_changed.get_connections().size()
	window.queue_free()
	await settle()
	check(hut.construction_changed.get_connections().size()==connections-1,"Window teardown disconnects its building observation")
	world.free()
	print("Buildings window: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
