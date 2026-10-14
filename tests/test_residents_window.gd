extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const Resident=preload("res://scripts/resident_data.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func flush(window: Node) -> void: window._projection_changed();window._flush()
func run() -> void:
	var world=F.create(self)
	var pc=world.player_control
	var window=world.settlement_panel
	var ui=world.game_ui
	var camera: Camera3D=world.get_node("World/Camera3D")
	var transform: Transform3D=camera.global_transform
	var zoom: float=camera.size
	var no_view=Resident.new("no_view","Алексей Очень Длинное Имя Жителя Поселения",42,P.NONE)
	var twin=Resident.new("twin","Алексей Очень Длинное Имя Жителя Поселения",42,P.NONE)
	pc.register_resident(no_view);pc.register_resident(twin)
	world.residents[1].activity=preload("res://scripts/resident_activity.gd").Type.SLEEPING
	world.resident_runtimes[2].view.hide()
	await process_frame
	await process_frame
	F.click(self,ui.residents_button)
	await process_frame
	await process_frame
	check(window.visible and window.rows.size()==pc.get_residents().size() and window.rows.has(no_view.id),"All registered residents, including invisible/sleeping/no 3D view")
	check(window.table.columns==3 and window.rows[no_view.id].get_metadata(0)==no_view.id,"Three columns and stable resident ID, no nodes per cell")
	check(window.visible_ids.find(no_view.id)<window.visible_ids.find(twin.id),"Equal names tie by stable ID")
	var original_row: TreeItem=window.rows[world.residents[0].id]
	window.search.text="сТеПаН";flush(window)
	check(window.visible_ids==[world.residents[0].id],"Case-insensitive substring search")
	window.search.text="";flush(window)
	for role in P.values():
		window.eligibility_filter.select(role+1);flush(window)
		check(window.visible_ids.size()==pc.get_residents().size(),"Profession eligibility independent of absent buildings/vacancy: %d" % role)
	window.eligibility_filter.select(0)
	var area=world.work_areas.create(Vector2(-700,-250),375)
	pc.assign_profession(world.residents[1].id,P.LUMBERJACK)
	pc.assign_work_area(world.residents[1].id,area.id)
	pc.clear_work_assignment(world.residents[0].id)
	pc.assign_profession(world.residents[2].id,P.BUILDER)
	window._flush()
	check(window.rows[world.residents[0].id]==original_row,"Assignment updates existing row, no full table rebuild")
	check(window.workplace_label(world.residents[1]).contains("Свободная область") and window.has_work_assignment(world.residents[1]),"WorkArea counted as assignment, never displayed as building")
	check(window.workplace_label(world.residents[0])=="Носильщик без рабочего места","Unassigned Porter displayed honestly")
	check(window.workplace_label(world.residents[2]).contains("Работа в мире") and not window.has_work_assignment(world.residents[2]),"Builder world work is not a fictional workplace")
	window.employment_filter.select(1);flush(window)
	check(window.visible_ids==[world.residents[1].id],"Assignment filter includes area and excludes empty workplaces")
	window.profession_filter.select(P.LUMBERJACK+1)
	window.search.text="ан";flush(window)
	check(window.visible_ids==[world.residents[1].id],"Search/current profession/eligibility/assignment combine")
	window.employment_filter.select(2);flush(window)
	check(window.visible_ids.is_empty(),"Conflicting independent filters produce empty list")
	window.preset_profession(-1);window._flush()
	for criterion in range(3):
		window.sort_order.select(criterion)
		for reversed in [false,true]:
			window.reverse_order.set_pressed_no_signal(reversed);flush(window)
			for index in range(window.visible_ids.size()-1): check(window._less(window.visible_ids[index],window.visible_ids[index+1]),"Sort %d reverse %s" % [criterion,reversed])
	var saw=F.building(world,T.SAWMILL,Vector3(-15,0,10))
	pc.assign_workplace(world.residents[3].id,saw.id,P.SAWYER)
	world.resident_selection.select_building(saw)
	world.game_ui.info_panel.set_expanded(true)
	world.building_card_view().staffing_buttons[P.SAWYER].pressed.emit()
	await process_frame
	await process_frame
	check(window==world.settlement_panel and window.visible and window.visible_ids.size()==pc.get_residents().size(),"Same window worker preset does not exclude anyone when target full")
	check(window.eligibility_filter.get_selected_metadata()==P.SAWYER and window.sort_order.selected==2,"Worker entry presets eligibility and unassigned-first sort")
	var rect: Rect2=window.get_global_rect()
	world.game_ui.info_panel.set_expanded(false)
	check(window.get_global_rect()==rect,"Blue collapse never moves/resizes window")
	world.game_ui.info_panel.set_expanded(true)
	check(not window.get_global_rect().intersects(world.game_ui.info_panel.get_global_rect()),"Residents window never overlaps expanded Blue")
	world.resident_selection.clear()
	window.preset_profession(-1);window._flush()
	await process_frame
	await process_frame
	await F.row_click(self,window,world.residents[0].id)
	check(window.visible and world.resident_selection.selected_resident==world.residents[0],"Actual GUI row without building selects resident and keeps window")
	world.resident_selection.select_building(saw)
	await process_frame
	await F.row_click(self,window,world.residents[0].id)
	check(world.assignment_dialog.visible and world.resident_selection.selected_building==saw,"Actual GUI same row with building opens dialog without selection change")
	F.key(self,KEY_ESCAPE)
	F.click(self,window.search)
	check(ui.input_context.text_editing(),"Search focus uses existing UIInputContext")
	var held:=InputEventKey.new()
	held.pressed=true;held.keycode=KEY_W;held.physical_keycode=KEY_W;held.unicode=119
	Input.parse_input_event(held.duplicate());Input.flush_buffered_events()
	camera._process(0.25)
	check(camera.global_transform==transform,"Camera polling ignores held W during actual text focus")
	held.pressed=false;Input.parse_input_event(held.duplicate());Input.flush_buffered_events()
	world._select_building_definition(preload("res://scripts/building_definition.gd").for_type(T.HOME))
	var turns: int=world.placement.quarter_turns
	F.key(self,KEY_R);F.key(self,KEY_SPACE);F.key(self,KEY_4)
	check(world.placement.quarter_turns==turns and not paused and world.game_time.speed_multiplier==1,"Focused text does not rotate/pause/change game speed")
	window.search.release_focus()
	var wheel:=InputEventMouseButton.new()
	wheel.pressed=true;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.position=window.table.get_global_rect().get_center()
	root.push_input(wheel,true)
	wheel.pressed=false;root.push_input(wheel.duplicate(),true)
	check(camera.size==zoom,"Table wheel never zooms camera")
	world._cancel_active_world_tool()
	F.click(self,window.search)
	check(ui.input_context.text_editing(),"Search can regain text focus before closing")
	window.hide()
	check(not ui.input_context.text_editing(),"Hiding window releases text focus and restores game controls")
	var hidden_count: int=window.rows.size()
	var later=Resident.new("hidden_added","Скрытый",24)
	pc.register_resident(later)
	await process_frame
	check(window.rows.size()==hidden_count and window._roster_dirty,"Closed window defers registry scans/row creation")
	ui.open_window(&"residents")
	check(window.rows.has(later.id),"Reopening refreshes current registry")
	pc.unregister_resident(later.id)
	await process_frame
	check(not window.rows.has(later.id),"Removed resident releases stale TreeItem")
	check(camera.global_transform==transform and camera.size==zoom,"All window/dialog/selection transitions preserve camera")
	world.free()
	print("E4 residents window: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
