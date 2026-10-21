extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Resident=preload("res://scripts/resident_data.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func press(button: Button) -> void:
	var parent:=button.get_parent()
	while parent!=null:
		if parent is ScrollContainer: parent.ensure_control_visible(button);break
		parent=parent.get_parent()
	await settle()
	F.click(self,button)
func show_resident(world: Node, actor: Node) -> void:
	world.resident_selection.select(actor.data)
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.info_panel.select_tab(&"work")
func capture(label: String) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var folder:="C:/Users/SW/Documents/Codex/outputs/work-areas-w5c2/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	root.size=Vector2i(1600,900)
	var world=F.create(self)
	await settle()
	var pc=world.player_control
	var ui=world.game_ui
	var panel=ui.info_panel
	var card=panel.resident_details
	var area_card=panel.area_details
	var areas=world.work_areas_window
	var people=world.settlement_panel
	var warning=world.area_departure_dialog
	var selection=world.resident_selection
	var actor=world.resident_runtimes[0]
	var miner=world.resident_runtimes[1]
	var free_worker=world.resident_runtimes[2]
	var other=world.resident_runtimes[3]
	var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var quarry=F.building(world,T.QUARRY,Vector3(26,0,-20))
	var area=world.work_areas.create(C.to_sim(Vector3(0,0,-8)),C.length_to_sim(30))
	var remote=world.work_areas.create(C.to_sim(Vector3(35,0,20)),C.length_to_sim(8))
	pc.rename_work_area(area.id,"Общий лес и камень")
	pc.rename_work_area(remote.id,"Дальний круг")
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	pc.assign_workplace(miner.data.id,quarry.id,P.MINER)
	pc.assign_profession(free_worker.data.id,P.LUMBERJACK)
	pc.assign_profession(other.data.id,P.NONE)
	var worker=actor.get_node("Lumberjack")
	var stone_worker=miner.get_node("Miner")
	check(worker.request_work() and stone_worker.request_work(),"Real building CHOP and MINE are accepted before UI assignment")
	F.walk(world,actor);F.walk(world,miner)
	check(worker.chopping and stone_worker.mining,"Both committed workers physically arrive")
	var tree=worker.tree
	var rock=stone_worker.rock
	var intents: Array=[actor.intents.current_intent,miner.intents.current_intent]
	var stocks: Array=[hut.resources.get_amount(R.LOG),quarry.resources.get_amount(R.STONE)]
	pc.assign_building_work_area(hut.id,area.id)
	pc.assign_building_work_area(quarry.id,area.id)
	world._view_work_area(area.id)
	check(actor.data.resident_name not in area_card.assignments_label.text and miner.data.resident_name not in area_card.assignments_label.text and str(hut.id) in area_card.buildings_label.text,"Building users remain separate from direct resident assignments")
	show_resident(world,actor)
	check("При здании" in card.work_place_label.text and "Свободная область" not in card.work_place_label.text,"Building work area is not presented as a personal direct area")
	await settle()
	var requests: int=world.decision_dispatcher.requests
	var decisions: Array=world.resident_runtimes.map(func(runtime):return runtime.decision.decision_count)
	var routes: Array=[]
	var original: Callable=world.logistics.sources.route_available
	world.logistics.sources.route_available=func(start,target):routes.append([start,target]);return original.call(start,target)
	var nav: int=world.navigation.revision
	var viewed: Array=[]
	areas.area_selected.connect(func(id):viewed.append(id))
	await press(card.area_button)
	check(areas.visible and areas.create_button.visible and selection.selected_resident==actor.data and areas.close_button.text=="Закрыть" and panel.expanded,"Resident card opens Areas contextual list while retaining the source")
	await capture("01-resident-choose-area")
	await F.row_click(self,areas,str(remote.id))
	check(warning.visible and hut.display_name in warning.warning.text and remote.display_name in warning.warning.text and actor.data.work_location_id==hut.id and actor.data.work_area_id.is_empty(),"Resident-to-area warns before changing the workplace")
	check(selection.selected_resident==actor.data and actor.intents.current_intent==intents[0] and tree.reservation_owner_id==StringName(actor.data.id),"Warning preserves source card, accepted action and claim")
	await settle()
	check(warning.get_global_rect().encloses(warning.confirm_button.get_global_rect()) and warning.get_global_rect().encloses(warning.cancel_button.get_global_rect()) and Rect2(Vector2.ZERO,ui.size).encloses(warning.get_global_rect()),"Departure warning and both actions fit the viewport")
	await capture("02-departure-warning")
	await press(warning.cancel_button)
	check(not warning.visible and areas.create_button.visible and actor.data.work_location_id==hut.id and actor.data.work_area_id.is_empty(),"Cancelling warning leaves old work and a usable chooser")
	await F.row_click(self,areas,str(remote.id))
	await press(warning.confirm_button)
	check(actor.data.profession==P.LUMBERJACK and actor.data.work_location_id.is_empty() and actor.data.work_area_id==remote.id and not areas.visible and areas.create_button.visible,"Confirmed direct assignment clears only the workplace and restores ordinary browsing")
	check(selection.selected_resident==actor.data and panel.expanded and remote.display_name in card.work_place_label.text and viewed.is_empty(),"Successful assignment keeps the source card and never views the area")
	check(world.work_highlight.circle.position.is_equal_approx(C.to_world(remote.center)+Vector3(0,0.02,0)) and not world.world_locations.get_view(hut.id).indicator.visible,"W2 replaces workplace accent with the new direct-area outline")
	world._focus_work_area(remote.center)
	await capture("03-direct-area-result")
	world._view_work_area(area.id)
	var ordinary: Array=[]
	people.assignment_requested.connect(func(id):ordinary.append(id))
	await press(area_card.assign_resident_button)
	await settle()
	check(people.visible and people.close_button.text=="Закрыть" and area.display_name in area_card.title.text and people.visible_ids.size()==4,"Area card opens Residents contextual list with the entire population")
	check(selection.selected_work_area==area and panel.expanded and world.work_highlight.circle.visible and not people.get_global_rect().intersects(panel.get_global_rect()),"Area source and contour remain selected beside the chooser")
	check(people.rows[free_worker.data.id].get_text(1)==preload("res://scripts/resident_profession.gd").display_name(P.LUMBERJACK) and people.rows[other.data.id].get_text(1)==preload("res://scripts/resident_profession.gd").display_name(P.NONE),"Ordinary roster preserves professions and does not promote unsupported residents")
	pc.rename_work_area(area.id,"Общий лес и камень — жители")
	people._poll_visible()
	check(area.display_name in area_card.title.text,"Source rename survives the existing roster poll without losing contextual list")
	await capture("04-area-choose-resident")
	await F.row_click(self,people,other.data.id)
	check(other.data.profession==P.NONE and other.data.work_area_id.is_empty() and not warning.visible and people.close_button.text=="Закрыть" and selection.selected_resident==other.data,"Unsupported resident cannot be assigned or auto-promoted")
	world._view_work_area(area.id)
	await F.row_click(self,people,free_worker.data.id)
	check(free_worker.data.work_area_id.is_empty() and warning.visible,"Free worker also waits for explicit confirmation")
	await press(warning.confirm_button)
	check(free_worker.data.work_area_id==area.id and not warning.visible and not people.visible and selection.selected_work_area==area and ordinary.is_empty(),"Free lumberjack confirms without ordinary resident/building selection")
	check(free_worker.data.resident_name in area_card.assignments_label.text,"Direct assignment list updates without reopening")
	await press(area_card.assign_resident_button)
	await F.row_click(self,people,miner.data.id)
	check(warning.visible and quarry.display_name in warning.warning.text and miner.data.work_location_id==quarry.id,"Area-to-resident also warns before leaving a quarry")
	F.key(self,KEY_ESCAPE)
	check(not warning.visible and people.visible and miner.data.work_location_id==quarry.id,"First Esc cancels warning and preserves old assignment")
	F.key(self,KEY_ESCAPE)
	check(not people.visible and people.close_button.text=="Закрыть" and selection.selected_work_area==area,"Second Esc cancels chooser without closing the source card")
	await press(area_card.assign_resident_button)
	await F.row_click(self,people,miner.data.id)
	await press(warning.confirm_button)
	check(miner.data.profession==P.MINER and miner.data.work_location_id.is_empty() and miner.data.work_area_id==area.id and selection.selected_work_area==area,"Confirmed reverse assignment preserves miner profession and area source")
	check(pc.get_work_area_residents(area.id).size()==2 and miner.data.resident_name in area_card.assignments_label.text and free_worker.data.resident_name in area_card.assignments_label.text,"Two supported professions share one direct area")
	check([actor.intents.current_intent,miner.intents.current_intent]==intents and rock.reservation_owner_id==StringName(miner.data.id) and [hut.resources.get_amount(R.LOG),quarry.resources.get_amount(R.STONE)]==stocks,"CHOP/MINE, claims and building buffers survive both confirmations")
	var paints: int=area_card.refresh_count
	var rows: int=people.row_creation_count
	await settle();await settle()
	check(area_card.refresh_count==paints and people.row_creation_count==rows,"Assignment UI does not repaint unchanged cards or recreate rows every frame")
	show_resident(world,free_worker)
	var version: int=free_worker.data.work_assignment_revision
	await press(card.area_button)
	await F.row_click(self,areas,str(area.id))
	check(warning.visible and free_worker.data.work_assignment_revision==version,"Repeating the same direct assignment still offers inspection without mutation")
	await press(warning.confirm_button)
	check(free_worker.data.work_assignment_revision==version,"Confirming unchanged personal area emits no duplicate mutation")
	check(card.clear_work_button.text=="Снять назначение области","Direct area has a specific clear command")
	await press(card.clear_work_button)
	check(free_worker.data.work_area_id.is_empty() and free_worker.data.work_location_id.is_empty() and free_worker.data.profession==P.LUMBERJACK,"Clearing direct area preserves profession without choosing a building")
	world._view_work_area(area.id)
	check(free_worker.data.resident_name not in area_card.assignments_label.text and miner.data.resident_name in area_card.assignments_label.text,"Clearing updates only direct memberships")
	show_resident(world,free_worker)
	card._choose_area(1)
	await press(warning.confirm_button)
	check(free_worker.data.work_area_id==area.id and selection.selected_resident==free_worker.data,"Existing quick selection reuses the guarded assignment path")
	show_resident(world,actor)
	await press(card.clear_work_button)
	check(actor.data.work_area_id.is_empty() and actor.intents.current_intent==intents[0],"Clearing a direct area preserves the previously accepted CHOP")
	await press(card.area_button)
	await press(areas.close_button)
	check(areas.create_button.visible and selection.selected_resident==actor.data and actor.data.work_area_id.is_empty(),"Closing Areas cancels with the source card intact")
	world._view_work_area(area.id)
	await press(area_card.assign_resident_button)
	F.click(self,world.construction_panel.buttons[&"buildings"])
	check(people.close_button.text=="Закрыть" and world._area_assignment_source==null and selection.selected_work_area==area,"Switching QUICK_WINDOW clears the hidden resident contextual list mode")
	ui.close_window()
	await press(area_card.assign_resident_button)
	selection.select(other.data)
	check(people.close_button.text=="Закрыть" and people.visible and not warning.visible and world._area_assignment_source==null,"Ordinary object selection before a row keeps browsing with no captured source")
	check(world.decision_dispatcher.requests==requests and world.resident_runtimes.map(func(runtime):return runtime.decision.decision_count)==decisions and routes.is_empty() and world.navigation.revision==nav,"Controlled UI actions do not execute AI or source-route queries")
	world.logistics.sources.route_available=original
	var logs: int=Stacks.total(world.ground_resources,R.LOG)
	var stones: int=Stacks.total(world.ground_resources,R.STONE)
	var stock: int=rock.stock
	world.game_time.debug_skip_minutes(60)
	check(tree.state==tree.State.DEPLETED and rock.stock==stock-1 and worker.tree==null and stone_worker.rock==null,"Accepted building CHOP and MINE both finish after direct assignment/clear")
	check(Stacks.total(world.ground_resources,R.LOG)==logs+3 and Stacks.total(world.ground_resources,R.STONE)==stones+1 and tree.reservation_owner_id.is_empty() and rock.reservation_owner_id.is_empty(),"Both accepted completions yield once and release claims")
	check(worker.best_target().is_empty() and not stone_worker.best_target().is_empty(),"New searches use the current FREE or absent assignment")
	await stale_checks(world,actor,free_worker,hut,quarry,area,remote)
	world.free()
	print("Resident area assignment UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func stale_checks(world: Node, actor: Node, free_worker: Node, hut: RefCounted, quarry: RefCounted, area: RefCounted, remote: RefCounted) -> void:
	var pc=world.player_control
	var card=world.resident_card_view()
	var people=world.settlement_panel
	var areas=world.work_areas_window
	var area_card=world.game_ui.info_panel.area_details
	var warning=world.area_departure_dialog
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	world._view_work_area(area.id)
	await press(area_card.assign_resident_button)
	await F.row_click(self,people,actor.data.id)
	pc.assign_workplace(actor.data.id,quarry.id,P.MINER)
	check(not warning.visible and world._resident_area_offer.is_empty() and people.close_button.text=="Закрыть","Work reassignment invalidates the open departure confirmation")
	warning.confirmed.emit()
	check(actor.data.work_location_id==quarry.id and actor.data.work_area_id.is_empty(),"Old confirmation cannot overwrite a new workplace")
	await F.row_click(self,people,actor.data.id)
	pc.assign_profession(actor.data.id,P.NONE)
	check(not warning.visible and not pc.can_assign_work_area(actor.data.id),"Unsupported profession invalidates pending confirmation")
	pc.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	await F.row_click(self,people,actor.data.id)
	world.game_ui.close_window()
	check(not warning.visible and people.close_button.text=="Закрыть" and world._resident_area_offer.is_empty() and actor.data.work_location_id==hut.id,"Closing chooser also removes an outstanding warning without a write")
	show_resident(world,actor)
	card._choose_area(1)
	check(warning.visible and actor.data.work_location_id==hut.id,"Legacy quick selection cannot bypass departure warning")
	world.resident_selection.select(free_worker.data)
	warning.confirmed.emit()
	check(not warning.visible and not areas.visible and actor.data.work_location_id==hut.id,"Changing the source selection cancels a pending command")
	show_resident(world,actor)
	await press(card.area_button)
	await F.row_click(self,areas,str(remote.id))
	pc.remove_work_area(remote.id)
	warning.confirmed.emit()
	check(not warning.visible and actor.data.work_area_id.is_empty() and actor.data.work_location_id==hut.id,"Removed target area cannot receive a delayed assignment")
	world.game_ui.close_window()
	world._view_work_area(area.id)
	await press(area_card.assign_resident_button)
	await F.row_click(self,people,actor.data.id)
	var replacement=Resident.new(actor.data.id,"Replacement",30)
	replacement.id=actor.data.id
	replacement.profession=P.LUMBERJACK
	pc._residents[actor.data.id]=replacement
	warning.confirmed.emit()
	check(replacement.work_area_id.is_empty() and actor.data.work_location_id==hut.id,"A replacement resident with the same ID cannot receive an old confirmation")
	pc._residents[actor.data.id]=actor.data
	await F.row_click(self,people,actor.data.id)
	pc.remove_work_area(area.id)
	warning.confirmed.emit()
	check(not people.visible and not warning.visible and people.close_button.text=="Закрыть" and actor.data.work_location_id==hut.id,"Deleting the source area clears the pending offer safely")
	show_resident(world,free_worker)
	await press(card.area_button)
	pc.unregister_resident(free_worker.data.id)
	check(areas.visible and areas.create_button.visible and world._area_assignment_source==null,"Removing selected resident before a row leaves an ordinary Areas window")
	world.game_ui.open_window(&"residents")
	await F.row_click(self,people,actor.data.id)
	check(world.resident_selection.selected_resident==actor.data and people.close_button.text=="Закрыть","Normal resident selection is restored after all cancellations")
