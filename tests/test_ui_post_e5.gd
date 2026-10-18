extends SceneTree
const C = preload("res://scripts/resource_category.gd").Type
const F=preload("res://tests/residents_ui_fixture.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const D=preload("res://scripts/building_definition.gd")
const Candidate=preload("res://scripts/delivery_candidate.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const Job=preload("res://scripts/haul_job.gd")
const OUT="C:/Users/SW/Documents/Codex/outputs/ui-post-e5-revisions/"
var checks:=0
var failures:=0
var rendered:=false
var shots:=[]
var world: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func settle() -> void: await process_frame;await process_frame
func capture(label: String) -> void:
	if not rendered: return
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"Capture "+label)
	shots.append({"name":label,"window":str(root.size),"viewport":str(root.get_visible_rect()),"stretch":str(root.get_stretch_transform()),"strip":str(world.construction_panel.strip.get_global_rect()),"catalogue":str(world.construction_panel._contents.get_global_rect()),"blue":str(world.game_ui.info_panel.get_global_rect()),"residents":str(world.settlement_panel.get_global_rect()),"time":str(world.game_ui.time_controls.get_global_rect())})
func clear_button(id: String) -> Button:
	for row in world.building_card_view().get_node("%People").get_children():
		if row is HBoxContainer and row.get_child_count()==2 and row.get_child(0) is Button and row.get_child(0).text==world.player_control.get_resident(id).resident_name: return row.get_child(1)
	return null
func developer_tab(index: int) -> void:
	var bar: TabBar=world.developer_panel._tabs.get_tab_bar()
	F.click_at(self,bar.global_position+bar.get_tab_rect(index).get_center())
	await settle()
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution
		world=F.create(self)
		var saw=F.building(world,T.SAWMILL,Vector3(-18,0,10))
		var home=F.building(world,T.HOME,Vector3(-10,0,-18))
		var ui=world.game_ui
		var info=ui.info_panel
		var green=world.construction_panel
		var selection=world.resident_selection
		var card=ui.building_card
		var window=world.settlement_panel
		var camera: Camera3D=world.get_node("World/Camera3D")
		var transform: Transform3D=camera.global_transform
		var zoom: float=camera.get_zoom_distance()
		var prefix:="polish_%d_" % resolution.x
		await settle()
		var viewport: Rect2=root.get_visible_rect()
		check(info.size.x==320 and info.day_summary.visible,"Persistent full-width day card")
		check(green.strip.size.x==ui.size.x-24 and green.strip.get_global_rect().end.y>viewport.end.y,"Near-full-width bottom surface deliberately clipped below viewport")
		check(green.buttons.values().all(func(button):return viewport.encloses(button.get_global_rect())),"Every green button and hit area remains on screen")
		check(ui.time_controls.speed_buttons.map(func(button):return button.text)==["x1","x2","x4"] and not ui.time_controls.has_node("Column/ClockRow/Day"),"Normal time HUD excludes day/x10/x20")
		check(not world.has_node("HUD/NavigationDebugToggle") and world.developer_panel.navigation_toggle!=null,"Navigation access exists only in F10")
		check(not green._row.get_parent().get_global_rect().intersects(info.get_global_rect()),"Menu scroll viewport stays left of Blue while its background underlays it")
		await capture(prefix+"collapsed_hud")
		var hits:=[0,0]
		info.gui_input.connect(func(event):
			if event is InputEventMouseButton: hits[0]+=1)
		green.strip.gui_input.connect(func(event):
			if event is InputEventMouseButton: hits[1]+=1)
		F.click_at(self,info.get_global_rect().get_center())
		check(hits[0]>0 and hits[1]==0 and world._clicks.is_empty(),"Real GUI overlap routes to Blue, never underlay/world")
		F.click(self,green.collapse_button)
		await settle()
		check(green._contents.size==Vector2(720,156),"Catalogue has fixed separate left footprint")
		check(not ui.input_context.pointer_blocked(Vector2(850,560)),"Transparent space between catalogue and Blue leaves world accessible")
		F.click_at(self,Vector2(850,560))
		check(not world._clicks.is_empty(),"Real input in transparent layout gap reaches world queue")
		world._clear_world_input()
		await capture(prefix+"construction_expanded")
		var strip_width: float=green.strip.size.x
		for category in green.catalogue.categories:
			F.click(self,green.catalogue.category_buttons[category.id]);await settle()
			check(green.strip.size.x==strip_width and green.catalogue.category_id==category.id,"Category preserves strip width: "+category.title)
		green.catalogue.select_category(&"production")
		selection.select_building(saw)
		await settle()
		check(info.size.x==320 and not info.expanded and not card.get_node("%Summary").visible,"Compact built card has name/counts and no Built status")
		check(card.get_node("%StaffSummary").text.contains("0 / 1") and card.get_node("%Image").texture!=null,"Real staffing counts and existing type icon")
		for field in ["ID","State","Type","Characteristics"]: check(card.find_child(field,true,false)==null,"No hidden canonical technical widget: "+field)
		await capture(prefix+"sawmill_compact")
		F.click(self,info.get_node("Column/Header/Expand"));await settle()
		check(info.expanded and info.size.x==320 and info.get_node("Column/Header/Expand").text=="▼" and info.get_node("Column/Header/Close").text=="×","Small shared header controls reflect their actions")
		check(not card.get_node("%StaffSummary").visible and card.staffing_buttons[P.SAWYER].text=="Назначить" and card.staffing_buttons[P.PORTER].text=="Назначить","Expanded header avoids repeated counts; role actions are short")
		await capture(prefix+"sawmill_info_free")
		F.click(self,card.staffing_buttons[P.SAWYER]);await settle()
		var rect: Rect2=window.get_global_rect()
		check(rect==Rect2(12,12,924,476) and not rect.intersects(green._contents.get_global_rect()) and not rect.intersects(info.get_global_rect()),"Large residents window avoids both catalogue and expanded Blue")
		world.social_feed.add_message("Лента остаётся под окном жителей.")
		check(ui.get_node("Windows").z_index>ui.get_node("MessagesAnchor").z_index,"Residents overlays unchanged feed")
		await capture(prefix+"residents_blue_construction")
		F.click(self,green.collapse_button);await settle()
		check(window.get_global_rect()==rect,"Collapsing catalogue never changes window rectangle")
		info.set_expanded(false);await settle()
		check(window.get_global_rect()==rect,"Collapsing Blue never changes window rectangle")
		info.set_expanded(true)
		var worker=world.residents[1]
		await F.row_click(self,window,worker.id);await settle()
		F.click(self,world.assignment_dialog.buttons[P.SAWYER]);await settle()
		check(worker.work_location_id==saw.id and worker.profession==P.SAWYER and window.visible and selection.selected_building==saw,"Actual universal-window production assignment preserved")
		var dismiss: Button=clear_button(worker.id)
		check(dismiss!=null and dismiss.text=="Уволить","Specific worker has a short right-side dismissal action")
		var stale: Callable=dismiss.pressed.get_connections()[0].callable
		check(world.player_control.assign_workplace(worker.id,saw.id,P.PORTER),"Existing explicit-role reassignment succeeds")
		var revision: int=worker.work_assignment_revision
		stale.call()
		check(worker.profession==P.PORTER and worker.work_location_id==saw.id and worker.work_assignment_revision==revision,"Stale producer row cannot dismiss a new Porter role at the same building")
		world.player_control.assign_workplace(worker.id,saw.id,P.SAWYER)
		var porter=world.residents[0]
		world.player_control.assign_workplace(porter.id,saw.id,P.PORTER)
		await settle()
		await capture(prefix+"staffing_occupied")
		ui.close_window()
		info.select_tab(&"production");await settle()
		check(card.resources_label.text.contains("Вход") and card.resources_label.text.contains("Выход") and not card.get_node("%Info").visible,"Production has actual buffers, no duplicate header/personnel blocks")
		await capture(prefix+"production")
		selection.select_building(world.warehouse_data);info.select_tab(&"storage");await settle()
		check(card.storage_rows[C.PLANK].amount.text=="60 /" and card.storage_rows[C.PLANK].editor.text=="60","Actual storage amount and per-resource quota")
		await capture(prefix+"storage")
		world.player_control.assign_home(worker.id,home.id)
		selection.select_building(home);await settle()
		check(not card.staffing_buttons.has(P.PORTER) and card.housing_count.text=="Жильцы: 1 / 4","House has housing action and no fictitious Porter role")
		await capture(prefix+"home_occupants")
		selection.select(worker);await settle()
		check(info.resident_details.name_label.text.contains(worker.resident_name) and info._tabs==[&"bio",&"work",&"relations"],"Resident contents and tabs preserved")
		await capture(prefix+"resident")
		F.click(self,info.get_node("Column/Header/Close"));await settle()
		check(selection.selected_entity==null and info.day_summary.visible and not info.expanded,"Close symbol clears selection, leaves compact day")
		green.set_collapsed(false);green.catalogue.select_category(&"settlement");await settle()
		F.click(self,green.catalogue.tile_for_type(T.HOME));await settle()
		check(not info.expanded and info._preview_definition==world.placement.selected_definition and info.size.x==320,"Preview A: compact selection remains compact")
		await capture(prefix+"preview_compact")
		F.click(self,info.get_node("Column/Header/Expand"));await settle()
		await capture(prefix+"preview_expanded")
		F.click(self,green.catalogue.tile_for_type(T.FOOD));await settle()
		check(info.expanded and info._preview_definition.type==T.FOOD,"Preview C: switching types preserves explicit expansion")
		F.click(self,info.get_node("Column/Header/Close"));await settle()
		check(not world.placement.is_active() and not info.expanded and info.day_summary.visible,"Preview close cancels placement and resets compact day")
		selection.select(worker);info.set_expanded(true)
		F.click(self,green.catalogue.tile_for_type(T.HOME));await settle()
		check(selection.selected_entity==null and info.expanded,"Preview B: intermediate selection.clear never loses expansion")
		F.key(self,KEY_R)
		var turns: int=world.placement.quarter_turns
		info.set_expanded(false);info.set_expanded(true)
		check(world.placement.quarter_turns==turns,"Card disclosure never changes placement rotation")
		F.key(self,KEY_ESCAPE);await settle()
		check(not world.placement.is_active() and not info.expanded,"Preview D: cancellation resets disclosure")
		F.click(self,green.catalogue.tile_for_type(T.FOOD));await settle()
		check(not info.expanded,"Preview after cancellation starts compact")
		F.click_at(self,Vector2(850,440),MOUSE_BUTTON_RIGHT);await physics_frame;await process_frame
		check(not world.placement.is_active() and info.day_summary.visible,"RMB cancellation retained")
		F.click(self,green.catalogue.tile_for_type(T.HOME));F.click(self,green.collapse_button);await settle()
		check(not world.placement.is_active() and green.collapsed,"Catalogue collapse cancels without confirmation")
		F.click(self,ui.time_controls.pause_button)
		check(paused and ui.time_controls.pause_button.text=="▶","Real pause icon and action")
		F.click(self,ui.time_controls.speed_buttons[2])
		check(world.game_time.speed_multiplier==4 and paused,"x4 remains usable while paused")
		F.click(self,ui.time_controls.pause_button)
		check(not paused and ui.time_controls.pause_button.text.begins_with("⏸"),"Real resume icon and action")
		F.key(self,KEY_F10);await settle()
		await developer_tab(3)
		F.click(self,world.developer_panel.speed_buttons[20])
		check(world.game_time.speed_multiplier==20 and world.developer_panel.speed_buttons[20].button_pressed and ui.time_controls.speed_buttons.all(func(button):return not button.button_pressed),"F10 x20 uses unchanged clock API and accurate selected state")
		F.click(self,world.developer_panel.speed_buttons[10])
		check(world.game_time.speed_multiplier==10,"F10 x10 retained")
		await capture(prefix+"developer_time")
		F.click(self,world.developer_panel.navigation_toggle)
		check(world.navigation_debug.visible,"Native F10 navigation toggle enables existing renderer")
		await capture(prefix+"developer_navigation")
		F.click(self,world.developer_panel.navigation_toggle)
		F.key(self,KEY_F10)
		world.game_time.set_speed(1)
		# Physical committed hauling survives the new specific dismissal button.
		if resolution.x==1920:
			var actor=world.resident_runtimes[0]
			world.player_control.assign_workplace(actor.data.id,world.warehouse_data.id,P.PORTER)
			world.warehouse_data.resources.add(R.LOG,1) # Normal resource API; starter stock contains PLANK, not LOG.
			var source_amount: int=world.warehouse_data.resources.get_amount(R.LOG)
			var destination=F.building(world,T.SAWMILL,Vector3(0,0,-20))
			var destination_amount: int=destination.resources.get_amount(R.LOG)
			var candidate=Candidate.new()
			candidate.source=world.warehouse_data;candidate.source_ref=Source.new(Source.Kind.CONTAINER,world.warehouse_data.id)
			candidate.destination=destination;candidate.resource_type=R.LOG
			var job=world.logistics._claim_delivery(actor.data,candidate)
			check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Actual committed haul starts before UI dismissal")
			if job!=null:
				for step in range(4000):
					actor.view._physics_process(0.05)
					if world.logistics._executors[actor.data.id].handling.operation==&"loading": break
				world.game_time.debug_skip_minutes(10)
				check(actor.data.inventory.amount==1 and job.is_active(),"Actual physical pickup completed")
				selection.select_building(world.warehouse_data);info.set_expanded(true);await settle()
				F.click(self,clear_button(actor.data.id));await settle()
				check(actor.data.work_location_id.is_empty() and job.is_active() and actor.data.inventory.amount==1,"Specific UI dismissal preserves committed cargo/job")
				for leg in range(8):
					if not job.is_active(): break
					F.walk(world,actor);world.game_time.debug_skip_minutes(10)
				check(job.state==Job.State.COMPLETED and destination.resources.get_amount(R.LOG)==destination_amount+1 and world.warehouse_data.resources.get_amount(R.LOG)==source_amount-1 and actor.data.inventory.amount==0,"Dismissed Porter delivers once and conserves resources")
				check(destination.resources.get_reserved_in(R.LOG)==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Committed reservations cleaned up")
		world.placement.select(D.for_type(T.HOME))
		world.placement.update_world_position(Vector3(28,0,24))
		var site=world.placement.confirm()
		check(site!=null,"Normal placement creates real UNDER_CONSTRUCTION")
		selection.select_building(site);info.set_expanded(true);await settle()
		check(card.get_node("%Summary").visible and card.get_node("%Summary").text=="Строится" and info._tabs==[&"info"],"Construction is clearly distinguished without technical fields")
		await capture(prefix+"construction_site")
		for resource in site.definition.construction_requirements: site.add_delivered_material(resource,site.get_required_amount(resource))
		site.add_construction_work(site.definition.construction_work_required)
		check(site.complete_construction() and not card.get_node("%Summary").visible,"Real lifecycle completion updates shared header")
		check(card.get_node("%Demolish").disabled and card.get_node("%Demolish").pressed.get_connections().is_empty(),"Demolition remains disabled without callback")
		if not rendered:
			for index in range(12): green.register_section(StringName("fixture_%d" % index),"Проверка меню %d" % index,green.Kind.QUICK_WINDOW)
			await settle()
			var scroll: ScrollContainer=green._row.get_parent()
			check(scroll.get_h_scroll_bar().max_value>scroll.get_h_scroll_bar().page,"Long ordered registry keeps horizontal scrolling")
			scroll.scroll_horizontal=int(scroll.get_h_scroll_bar().max_value)
			await settle()
			check(viewport.encloses(green.buttons[&"fixture_11"].get_global_rect()),"Last menu entry has an on-screen hit area through scrolling")
		check(camera.global_transform==transform and camera.get_zoom_distance()==zoom,"All native UI transitions preserve camera")
		world.free();await settle()
	root.size=Vector2i(1440,900) # Existing project default, no stretch/settings mutation.
	world=F.create(self)
	world.game_ui.set_actions_expanded(true)
	world.resident_selection.select_building(world.warehouse_data)
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.open_window(&"residents")
	await settle()
	check(not world.settlement_panel.get_global_rect().intersects(world.game_ui.info_panel.get_global_rect()) and not world.settlement_panel.get_global_rect().intersects(world.construction_panel._contents.get_global_rect()),"Existing project viewport default also preserves window gaps")
	await capture("polish_default_residents")
	world.free();await settle()
	var file:=FileAccess.open(OUT+("rendered.json" if rendered else "headless.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rendered":rendered,"screenshots":shots},"\t"))
	print("Post E5 UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
