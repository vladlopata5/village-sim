extends SceneTree
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const Diary = preload("res://scripts/diary_entry.gd")
const OUT = "C:/Users/SW/Documents/Codex/outputs/ui-e2-info-panel/"
var checks := 0
var failures := 0
var measurements: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)
func capture(world: Node, label: String, rendered: bool) -> void:
	await process_frame
	await process_frame
	var panel=world.game_ui.info_panel
	var camera: Camera3D=world.get_node("World/Camera3D")
	var frame: Rect2=panel.get_global_rect()
	check(is_equal_approx(frame.size.x,320.0) and frame.end.x <= world.game_ui.size.x-12.0+0.1,"Bounded card width/right edge: "+label)
	check(frame.position.y >= 139.9 or not panel.expanded,"Expanded card remains below time block: "+label)
	check(not frame.intersects(world.game_ui.time_controls.get_global_rect()),"Time and info never overlap: "+label)
	check(not world.settlement_panel.visible or not frame.intersects(world.settlement_panel.get_global_rect()),"Ordinary window never overlaps blue: "+label)
	measurements.append({"case":label,"window":str(root.size),"viewport":str(root.get_visible_rect()),"stretch":str(root.get_stretch_transform()),"info":str(frame),"window_rect":str(world.settlement_panel.get_global_rect()),"expanded":panel.expanded,"tab":panel.active_tab,"camera":str(camera.global_transform),"zoom":camera.get_zoom_distance()})
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+label+".png")
func run() -> void:
	var rendered: bool="--rendered" in OS.get_cmdline_user_args()
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.game_time.total_minutes=420
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
	var a=world.residents[0]
	var b=world.residents[1]
	a.set_opinion(StringName(b.id),24)
	b.set_opinion(StringName(a.id),-12)
	for n in range(12): a.add_diary_entry(Diary.new("Запись текущего дня %d: тест длинного настоящего дневника жителя" % n,Diary.Importance.KEY,420+n))
	var home_result: Dictionary=world.debug_spawn.spawn_building(Vector3(-15,0,15),Def.for_type(Types.HOME))
	var saw_result: Dictionary=world.debug_spawn.spawn_building(Vector3(-15,0,-14),Def.for_type(Types.SAWMILL))
	var store_result: Dictionary=world.debug_spawn.spawn_building(Vector3(29,0,-15),Def.for_type(Types.STORAGE))
	check(home_result.ok and saw_result.ok and store_result.ok,"Registered normal debug buildings for rendered QA")
	var home=home_result.objects[0]
	var saw=saw_result.objects[0]
	var store=store_result.objects[0]
	world.player_control.assign_home(b.id,home.id)
	world.player_control.assign_workplace(b.id,saw.id,P.SAWYER)
	saw.resources.add(R.LOG,1)
	var worker=world.get_resident_runtime(b)
	check(worker.recipe_work.request_work(),"Actual Sawmill work, not UI progress injection")
	for step in range(2000):
		worker.view._physics_process(0.05)
		if worker.recipe_work.phase==preload("res://scripts/resident_recipe_controller.gd").Phase.WORKING: break
	world.game_time.debug_skip_minutes(15)
	check(saw.production_progress==15,"Real work minutes reflected in Sawmill fixture")
	world.placement.select(Def.for_type(Types.HOME))
	world.placement.update_world_position(Vector3(29,0,24))
	var site=world.placement.confirm()
	check(site!=null,"Normal construction site for QA")
	var panel=world.game_ui.info_panel
	var selection=world.resident_selection
	var camera: Camera3D=world.get_node("World/Camera3D")
	var original_transform:=camera.global_transform
	var original_zoom: float=camera.get_zoom_distance()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution
		await process_frame
		await process_frame
		var prefix: String="info_%d_" % resolution.x
		selection.clear()
		await capture(world,prefix+"day",rendered)
		selection.select(a)
		await capture(world,prefix+"resident_compact",rendered)
		click(panel.get_node("Column/Header/Expand"))
		check(panel.expanded,"Actual GUI expand button")
		await process_frame
		await process_frame # Godot Container layout before the next GUI click.
		for tab in [&"bio",&"work",&"relations"]:
			for button in panel.get_node("Column/Tabs").get_children():
				if button.get_meta("tab_id")==tab: click(button)
			check(panel.active_tab==tab,"Actual tab GUI click: "+String(tab))
			await capture(world,prefix+"resident_"+String(tab),rendered)
		panel.select_tab(&"bio")
		world.resident_card_view().get_node("%DiaryToggle").button_pressed=true
		await process_frame
		var scroll: ScrollContainer=world.resident_card_view().get_node("%Scroll")
		scroll.scroll_vertical=1000
		await capture(world,prefix+"diary_scrolled",rendered)
		var wheel:=InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_UP
		wheel.pressed=true
		wheel.position=scroll.get_global_rect().get_center()
		root.push_input(wheel,true)
		wheel.pressed=false
		root.push_input(wheel,true)
		check(camera.get_zoom_distance()==original_zoom,"Wheel on real expanded card never zooms camera")
		for entity in [home,saw,store,world.warehouse_data,site]:
			selection.select_building(entity)
			panel.select_tab(&"info")
			var tag: String=String(entity.definition.id)+( "_construction" if not entity.is_built() else "")
			await capture(world,prefix+tag+"_info",rendered)
			if entity.type == Types.HOME:
				world.building_card_view().get_node("%Scroll").scroll_vertical=1000
				await capture(world,prefix+tag+"_footer",rendered)
				check(world.building_card_view().get_node("%Demolish").disabled,"Actual Info footer has inactive Demolish")
				world.building_card_view().get_node("%Scroll").scroll_vertical=0
			if panel._tabs.has(&"production"):
				panel.select_tab(&"production")
				await capture(world,prefix+String(entity.definition.id)+"_production",rendered)
			if panel._tabs.has(&"storage"):
				panel.select_tab(&"storage")
				await capture(world,prefix+String(entity.definition.id)+"_storage",rendered)
		selection.select_building(world.warehouse_data)
		world.game_ui.open_window(&"residents")
		await capture(world,prefix+"town_residents_window",rendered)
		world.game_ui.close_window()
		selection.clear()
		check(panel.show_type_preview(Def.for_type(Types.SAWMILL)),"Standalone preview uses real definition")
		await capture(world,prefix+"type_preview",rendered)
		panel.clear_type_preview()
		check(camera.global_transform==original_transform and camera.get_zoom_distance()==original_zoom,"No card action changes camera at either resolution")
	if rendered:
		var file:=FileAccess.open(OUT+"rendered-measurements.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(measurements,"\t"))
	world.free()
	print("E2 rendered matrix: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
