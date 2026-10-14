extends SceneTree
## Real GUI rendered QA; all rows and assignments read actual PlayerControl data.
const F=preload("res://tests/residents_ui_fixture.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const D=preload("res://scripts/building_definition.gd")
const OUT="C:/Users/SW/Documents/Codex/outputs/ui-e4-residents/"
var checks:=0
var failures:=0
var rendered:=false
var shots:=[]
var world: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func settle() -> void: await process_frame;await process_frame
func capture(label: String) -> void:
	if not rendered: return
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"Capture "+label)
	shots.append({"name":label,"window":str(root.size),"viewport":str(root.get_visible_rect()),"stretch":str(root.get_stretch_transform()),"roster":str(world.settlement_panel.get_global_rect()),"blue":str(world.game_ui.info_panel.get_global_rect()),"dialog":str(world.assignment_dialog.get_global_rect()),"visible_ids":world.settlement_panel.visible_ids.duplicate()})
func choose_option(menu: OptionButton, index: int) -> void:
	F.click(self,menu)
	await settle()
	var popup:=menu.get_popup()
	var font:=popup.get_theme_font("font")
	var row_height: float=font.get_height(popup.get_theme_font_size("font_size"))+popup.get_theme_constant("v_separation")
	var point:=Vector2(popup.size.x/2.0,popup.get_theme_stylebox("panel").get_content_margin(SIDE_TOP)+row_height*(index+0.5))
	await create_timer(0.25,true).timeout # Popup's normal opening-click protection.
	F.click_at(self,Vector2(popup.position)+point)
	await settle()
	popup.hide()
	check(menu.selected==index,"Actual popup mouse selects option %d" % index)
func type_text(field: LineEdit, text: String) -> void:
	F.click(self,field)
	for letter in text:
		var event:=InputEventKey.new()
		event.pressed=true;event.unicode=letter.unicode_at(0)
		root.push_input(event,true)
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution
		world=F.create(self)
		var pc=world.player_control
		var saw=F.building(world,T.SAWMILL,Vector3(-15,0,10))
		var house=F.building(world,T.HOME,Vector3(8,0,-18))
		var house2=F.building(world,T.HOME,Vector3(18,0,-22))
		var spawned: Dictionary=world.debug_spawn.spawn_residents(Vector3(-4,0,-8),30,P.NONE)
		check(spawned.created==30,"Normal Debug spawn populates large real registry")
		for actor in world.resident_runtimes:
			actor.decision._deciding=true
			actor.view.set_physics_process(false)
			actor.intents.abort_current(actor.intents.current_intent)
		world.residents[-1].resident_name="Александр Очень Длинное Имя Для Проверки Переноса"
		var window=world.settlement_panel
		var dialog=world.assignment_dialog
		var info=world.game_ui.info_panel
		var camera: Camera3D=world.get_node("World/Camera3D")
		var transform: Transform3D=camera.global_transform
		var zoom: float=camera.size
		var prefix:="e4_%d_" % resolution.x
		await settle()
		F.click(self,world.game_ui.residents_button)
		await settle()
		check(window.visible and window.visible_ids.size()==pc.get_residents().size() and world.resident_selection.selected_entity==null,"Actual quick button opens all registered residents, no selection change")
		check(window.get_global_rect()==Rect2(12,12,924,476),"Fixed approved logical roster geometry")
		await capture(prefix+"no_selection_large_list")
		var scroll_before: int=window.table.get_scroll().y
		var wheel:=InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=window.table.get_global_rect().get_center()
		for step in range(12):
			wheel.pressed=true;root.push_input(wheel.duplicate(),true)
			wheel.pressed=false;root.push_input(wheel.duplicate(),true)
		await settle()
		check(window.table.get_scroll().y>scroll_before and camera.size==zoom,"Actual large-list wheel scroll, no camera zoom")
		await capture(prefix+"scrolled_list")
		await choose_option(window.sort_order,1)
		F.click(self,window.reverse_order)
		await settle()
		check(window.sort_order.selected==1 and window.reverse_order.button_pressed,"Actual GUI sort age descending")
		await choose_option(window.profession_filter,P.NONE+1)
		await choose_option(window.eligibility_filter,P.SAWYER+1)
		await choose_option(window.employment_filter,2)
		var expected: Array=pc.get_residents().filter(func(person): return person.profession==P.NONE and person.work_location_id.is_empty() and person.work_area_id.is_empty()).map(func(person): return person.id)
		check(window.visible_ids.size()==expected.size() and window.visible_ids.all(func(id): return id in expected),"Actual combined filters match registered profession/assignment data")
		await capture(prefix+"filters_sort")
		window.preset_profession(-1)
		await settle()
		type_text(window.search,"СТЕПАН")
		await settle()
		check(window.search.text=="СТЕПАН" and window.visible_ids.all(func(id): return pc.get_resident(id).resident_name.to_lower().contains("степан")),"Actual Unicode input and live substring search")
		check(window.visible_ids.size()>0 and world.game_ui.input_context.text_editing(),"Search shows real matches with text focus")
		await capture(prefix+"search")
		F.key(self,KEY_SPACE);F.key(self,KEY_R);F.key(self,KEY_4);F.key(self,KEY_ENTER)
		check(not paused and world.game_time.speed_multiplier==1,"Search keyboard cannot pause/change speed/confirm world tool")
		window.search.release_focus()
		window.preset_profession(-1)
		window._flush()
		world.resident_selection.select_building(saw)
		info.set_expanded(true)
		await settle()
		check(not info.get_global_rect().intersects(window.get_global_rect()),"Expanded Blue never overlaps fixed window")
		await capture(prefix+"selected_sawmill")
		# Actual card entry uses the same coordinator/window and optional role preset.
		F.click(self,world.building_card_view().staffing_buttons[P.SAWYER])
		await settle()
		check(window.visible and window.eligibility_filter.get_selected_metadata()==P.SAWYER,"Actual production-management entry opens same window with role preset")
		var worker=world.residents[1]
		await F.row_click(self,window,worker.id)
		await settle()
		check(dialog.visible and dialog.buttons.has(P.SAWYER) and dialog.buttons.has(P.PORTER) and world.resident_selection.selected_building==saw,"Actual row opens applicable assignment dialog")
		check(root.get_visible_rect().encloses(dialog.get_global_rect()) and not info.get_global_rect().intersects(dialog.get_global_rect()),"Russian dialog fully visible beside Blue")
		await capture(prefix+"production_dialog")
		F.click(self,dialog.buttons[P.SAWYER])
		await settle()
		check(worker.profession==P.SAWYER and worker.work_location_id==saw.id and not dialog.visible and window.visible and world.resident_selection.selected_building==saw,"Actual assignment button uses PlayerControl, leaves list/building")
		var refused=world.residents[2]
		await F.row_click(self,window,refused.id)
		await settle()
		check(dialog.buttons[P.SAWYER].disabled and dialog.reasons[P.SAWYER].visible,"Full role remains present with readable refusal")
		await capture(prefix+"full_role")
		var revision: int=refused.work_assignment_revision
		F.click(self,dialog.buttons[P.SAWYER])
		check(refused.work_assignment_revision==revision and dialog.visible,"Disabled GUI assignment does not mutate data")
		F.click(self,dialog.cancel_button)
		await F.row_click(self,window,world.residents[3].id)
		await settle()
		await capture(prefix+"porter_dialog")
		F.click(self,dialog.buttons[P.PORTER])
		await settle()
		check(world.residents[3].profession==P.PORTER and world.residents[3].work_location_id==saw.id,"Actual Porter assignment respects separate staffing")
		await F.row_click(self,window,worker.id)
		check(dialog.visible,"Dialog open before stale-context selection")
		var rect: Rect2=window.get_global_rect()
		world.resident_selection.select_building(house)
		check(not dialog.visible and window.visible and window.get_global_rect()==rect,"Changing selected building closes old dialog but preserves window")
		await F.row_click(self,window,worker.id)
		await settle()
		check(dialog.buttons.has(&"home") and not dialog.buttons.has(P.PORTER),"House offers housing instead of fabricated professions")
		await capture(prefix+"housing_dialog")
		F.click(self,dialog.buttons[&"home"])
		await settle()
		check(worker.home_location_id==house.id and worker.work_location_id==saw.id and window.visible and world.resident_selection.selected_building==house,"Actual housing preserves work assignment/list/home selection")
		check(world.building_card_view().housing_count.text=="Жильцы: 1 / 4","Rendered home counter follows real assignment")
		await capture(prefix+"housing_assigned")
		for actor in world.resident_runtimes.slice(4,7): pc.assign_home(actor.data.id,house.id)
		pc.assign_home(refused.id,house2.id)
		await F.row_click(self,window,refused.id)
		await settle()
		check(dialog.buttons[&"home"].disabled and dialog.reasons[&"home"].visible and refused.home_location_id==house2.id,"Full house exposes reason and keeps previous home")
		await capture(prefix+"full_house")
		# Modeless dismissal consumes press and release; no click reuse in the world.
		world.placement.select(D.for_type(T.HOME))
		var building_count: int=world.buildings.size()
		F.click_at(self,Vector2(900,400))
		await physics_frame
		check(not dialog.visible and window.visible and world.placement.is_active() and world.buildings.size()==building_count,"Outside dialog click only dismisses, never confirms placement")
		world.resident_selection.select_building(house2)
		world.placement.select(D.for_type(T.HOME))
		dialog.open_for(refused.id)
		F.key(self,KEY_ESCAPE)
		check(not dialog.visible and window.visible and world.placement.is_active(),"Esc 1 closes dialog only")
		F.key(self,KEY_ESCAPE)
		check(not window.visible and world.placement.is_active(),"Esc 2 closes Residents only")
		F.key(self,KEY_ESCAPE)
		check(not world.placement.is_active(),"Esc 3 cancels existing world tool")
		check(camera.global_transform==transform and camera.size==zoom,"All real GUI actions preserve camera")
		world.free()
		await settle()
	var file:=FileAccess.open(OUT+("rendered-measurements.json" if rendered else "headless-gui.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rendered":rendered,"checks":checks,"failures":failures,"screenshots":shots},"\t"))
	print("E4 GUI/rendered: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
