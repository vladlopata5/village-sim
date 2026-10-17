extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const Stacks = preload("res://tests/ground_stack_fixture.gd")
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
	for frame in range(5): await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w4/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func enter(field: LineEdit, text: String) -> void:
	F.click(self,field)
	field.text = text
	field.text_changed.emit(text)
func run() -> void:
	root.size = Vector2i(1600,900)
	var world = F.create(self)
	await settle()
	var pc = world.player_control
	var areas = world.work_areas
	var panel = world.game_ui.info_panel
	var card = panel.area_details
	var dialog = world.work_area_dialog
	var window = world.work_areas_window
	var actor = world.resident_runtimes[0]
	var miner = world.resident_runtimes[1]
	var unrelated = world.resident_runtimes[2]
	var area = areas.create(C.to_sim(Vector3(0,0,-9)),C.length_to_sim(15))
	var other = areas.create(C.to_sim(Vector3(-38,0,-20)),C.length_to_sim(15))
	check(area.display_name=="Область 1" and other.display_name=="Область 2","Registry creates readable independent names with stable technical IDs")
	pc.edit_work_area(area.id,area.center,C.length_to_sim(30))
	pc.assign_profession(actor.data.id,P.LUMBERJACK)
	pc.assign_profession(miner.data.id,P.MINER)
	pc.assign_profession(unrelated.data.id,P.LUMBERJACK)
	pc.assign_work_area(actor.data.id,area.id)
	pc.assign_work_area(miner.data.id,area.id)
	pc.assign_work_area(unrelated.data.id,other.id)
	await settle()
	var worker = actor.get_node("Lumberjack")
	var stone_worker = miner.get_node("Miner")
	check(worker.request_work() and worker.kind==&"CHOP" and stone_worker.request_work(),"Two real workers accept CHOP and MINE in a shared area")
	var tree = worker.tree
	var rock = stone_worker.rock
	var chop_intent = actor.intents.current_intent
	var mine_intent = miner.intents.current_intent
	F.walk(world,actor)
	F.walk(world,miner)
	check(worker.chopping and stone_worker.mining,"Both workers physically arrive before editing")
	world._view_work_area(area.id)
	world._focus_work_area(area.center)
	world.get_node("World/Camera3D").set_zoom_distance(90)
	world.game_ui.open_window(&"areas")
	await settle()
	var row: TreeItem = window.rows[area.id]
	var mesh = world.work_highlight.circle.mesh
	var revision: int = area.revision
	var assignment: Array = [actor.data.work_assignment_revision,miner.data.work_assignment_revision]
	var requests: int = world.decision_dispatcher.requests
	var id: StringName = area.id
	F.click(self,card.rename_button)
	await settle()
	check(dialog.visible and not dialog.deleting and dialog.name_input.text==area.display_name,"Rename action captures the selected area in the existing dialog layer")
	enter(dialog.name_input,"Отменённое имя")
	F.click(self,dialog.cancel_button)
	check(area.display_name=="Область 1" and area.revision==revision,"Cancelling rename preserves both name and geometry revision")
	F.click(self,card.rename_button)
	enter(dialog.name_input,"  ")
	F.click(self,dialog.confirm_button)
	check(dialog.visible and not dialog.feedback.text.is_empty() and area.display_name=="Область 1","Empty rename is rejected without losing display name")
	enter(dialog.name_input,"  Общий лес и камень  ")
	F.click(self,dialog.confirm_button)
	await settle()
	check(area.display_name=="Общий лес и камень" and areas.get_area(id)==area and area.id==id,"Rename trims text but preserves object and ID")
	check(area.revision==revision and [actor.data.work_assignment_revision,miner.data.work_assignment_revision]==assignment and world.decision_dispatcher.requests==requests and world._work_updates.is_empty(),"Presentation-only rename does not invalidate assignments, geometry or AI")
	check(window.rows[id]==row and window.table.get_selected()==row and row.get_text(0)==area.display_name and area.display_name in card.title.text,"Renaming updates retained row/card without losing selection")
	check(world.work_highlight.circle.mesh==mesh,"Renaming does not rebuild the geometry")
	check(pc.rename_work_area(other.id,area.display_name) and other.id!=area.id,"Duplicate display names keep independent identities")
	await capture("01-before-edit")
	F.click(self,card.edit_button)
	check(world.work_area_tool.edited_area==area and world.work_area_tool.preview!=area and world.work_area_tool.locked,"Editing starts a private preview, retaining a usable center for radius-only changes")
	var live_geometry: Array = [area.center,area.radius,area.revision]
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(35,0,15)})
	enter(world.area_radius_input,"4")
	check([area.center,area.radius,area.revision]==live_geometry and world.work_area_tool.preview.center==C.to_sim(Vector3(35,0,15)),"Map click moves only preview, never selects the clicked world object")
	check(world.resident_selection.selected_work_area==area,"Editing retains the area's blue card and object selection")
	for invalid in ["0","-1","31","abc","nan","inf","1e999",""]:
		enter(world.area_radius_input,invalid)
		world._confirm_work_area()
		check(world.area_confirm.disabled and [area.center,area.radius,area.revision]==live_geometry,"Invalid radius leaves live geometry intact: "+invalid)
	check(not pc.edit_work_area(id,Vector2(NAN,0),C.length_to_sim(10)) and not pc.edit_work_area(id,Vector2.ZERO,INF) and not pc.edit_work_area(id,Vector2.ZERO,C.length_to_sim(30.1)) and [area.center,area.radius,area.revision]==live_geometry,"Player API rejects invalid geometry atomically, including max radius")
	enter(world.area_radius_input,"0.001")
	check(not world.area_confirm.disabled and is_equal_approx(C.length_to_world(world.work_area_tool.preview.radius),0.001),"No arbitrary minimum radius is introduced")
	enter(world.area_radius_input,"30")
	check(not world.area_confirm.disabled and C.length_to_world(world.work_area_tool.preview.radius)==30,"Maximum 30 world units is accepted")
	world.game_ui.try_escape()
	check(not world.work_area_tool.active() and [area.center,area.radius,area.revision]==live_geometry and world.resident_selection.selected_work_area==area,"Escape cancels preview completely while preserving original geometry/card")
	world.game_ui.close_window()
	F.click(self,card.edit_button)
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(35,0,15)})
	enter(world.area_radius_input,"4,5")
	check(not world.area_confirm.disabled and C.length_to_world(world.work_area_tool.preview.radius)==4.5,"Radius field accepts fractional world units with a decimal comma")
	world._focus_work_area(world.work_area_tool.preview.center)
	world.get_node("World/Camera3D").set_zoom_distance(50)
	await capture("02-edit-preview")
	F.click(self,world.area_confirm)
	check(area.center==C.to_sim(Vector3(35,0,15)) and C.length_to_world(area.radius)==4.5 and area.revision==revision+1,"Confirmation atomically commits center and radius to the same WorkArea")
	check(areas.get_area(id)==area and pc.get_work_area_residents(id).size()==2 and [actor.data.work_assignment_revision,miner.data.work_assignment_revision]==assignment,"Shared geometry edit retains both assignments and the stable ID")
	check(world._work_updates.has(actor.data.id) and world._work_updates.has(miner.data.id) and not world._work_updates.has(unrelated.data.id),"Geometry notifications target only residents of the edited area")
	check(actor.intents.current_intent==chop_intent and miner.intents.current_intent==mine_intent and tree.reservation_owner_id==StringName(actor.data.id) and rock.reservation_owner_id==StringName(miner.data.id),"Accepted CHOP/MINE and both target claims survive geometry edit")
	check(not area.contains(tree.position) and not area.contains(rock.position) and worker.chopping and stone_worker.mining,"Committed work remains active outside the new area boundaries")
	check(world.resident_selection.selected_work_area==area and panel.expanded and "35.0" in card.center_label.text and "4.5" in card.radius_label.text and is_equal_approx(world.work_highlight.circle.mesh.get_aabb().size.x,9),"Card and shared contour reflect committed geometry without changing selection")
	world.game_ui.open_window(&"areas")
	await settle()
	check(window.rows[id]==row and window.table.get_selected()==row and row.get_text(1)=="4.5","Confirmed edit updates the retained selected row when the list reopens")
	world._focus_work_area(area.center)
	world.get_node("World/Camera3D").set_zoom_distance(50)
	await capture("03-after-edit")
	await settle()
	world._edit_work_area(id)
	enter(world.area_radius_input,"30")
	world._confirm_work_area()
	check(C.length_to_world(area.radius)==30 and area.center==C.to_sim(Vector3(35,0,15)),"Radius-only confirmation can increase the area to the maximum without moving its center")
	# An external geometry edit during preview must not be silently overwritten.
	world._edit_work_area(id)
	pc.edit_work_area(id,area.center,C.length_to_sim(5))
	world._confirm_work_area()
	check(world.work_area_tool.active() and world.area_confirm.disabled and C.length_to_world(area.radius)==5,"Stale preview revision is rejected")
	world._cancel_work_area()
	await settle()
	F.click(self,card.delete_button)
	await settle()
	check(dialog.visible and dialog.deleting and actor.data.resident_name in dialog.warning.text and miner.data.resident_name in dialog.warning.text and unrelated.data.resident_name not in dialog.warning.text,"Delete warning enumerates exact affected resident assignments")
	check(dialog.get_global_rect().encloses(dialog.confirm_button.get_global_rect()) and Rect2(Vector2.ZERO,world.game_ui.size).encloses(dialog.get_global_rect()),"Delete confirmation and actions fit the viewport")
	await capture("04-delete-warning")
	F.click(self,dialog.cancel_button)
	check(areas.get_area(id)==area and pc.get_work_area_residents(id).size()==2 and world.resident_selection.selected_work_area==area,"Cancelling deletion preserves data, assignments and selection")
	F.click(self,card.delete_button)
	var reassignments: Array = []
	var attempt := func(resident_id):
		if resident_id==actor.data.id: reassignments.append(pc.assign_work_area(resident_id,id))
	pc.work_assignment_changed.connect(attempt)
	F.click(self,dialog.confirm_button)
	pc.work_assignment_changed.disconnect(attempt)
	world.game_ui.open_window(&"areas")
	await settle()
	check(areas.get_area(id)==null and not window.rows.has(id) and not panel.expanded and world.resident_selection.selected_entity==null and not world.work_highlight.circle.visible,"Deletion removes registry/list/card/highlight together")
	check(actor.data.work_area_id.is_empty() and miner.data.work_area_id.is_empty() and actor.data.profession==P.LUMBERJACK and miner.data.profession==P.MINER,"Deletion clears direct references but preserves professions")
	check(unrelated.data.work_area_id==other.id and reassignments==[false],"Unrelated assignment stays intact; callbacks cannot restore the deleted reference")
	check(actor.intents.current_intent==chop_intent and miner.intents.current_intent==mine_intent and tree.reservation_owner_id==StringName(actor.data.id) and rock.reservation_owner_id==StringName(miner.data.id),"Deleting an area does not interrupt active extraction or release accepted targets")
	dialog.execute()
	check(not pc.remove_work_area(id),"Repeated delete/confirmation has no second effect")
	var log_before: int = Stacks.total(world.ground_resources,R.LOG)
	var stone_before: int = Stacks.total(world.ground_resources,R.STONE)
	var stock: int = rock.stock
	world.game_time.debug_skip_minutes(60)
	check(tree.state==tree.State.DEPLETED and rock.stock==stock-1 and worker.tree==null and stone_worker.rock==null,"Accepted CHOP and MINE both finish after area deletion")
	check(Stacks.total(world.ground_resources,R.LOG)==log_before+3 and Stacks.total(world.ground_resources,R.STONE)==stone_before+1,"Completions yield resources exactly once under existing stack rules")
	check(tree.reservation_owner_id.is_empty() and rock.reservation_owner_id.is_empty() and not worker.has_work() and not stone_worker.has_work(),"Finished claims clear; next work cannot use the deleted assignment")
	# Unused deletion has a normal confirmation, and name/cancel still use GameUI Esc.
	world._view_work_area(other.id)
	pc.clear_work_assignment(unrelated.data.id)
	F.click(self,card.delete_button)
	check("Прямых назначений нет" in dialog.warning.text,"Unassigned deletion truthfully reports no affected workers")
	world.game_ui.try_escape()
	check(not dialog.visible and areas.get_area(other.id)==other,"Escape cancels confirmation without deleting the area")
	world._edit_work_area(other.id)
	F.click(self,card.delete_button)
	F.click(self,dialog.confirm_button)
	check(not world.work_area_tool.active() and areas.get_area(other.id)==null,"Deleting the selected area also cancels its outstanding preview")
	world.free()
	print("Work area editing: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
