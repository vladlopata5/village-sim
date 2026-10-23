extends SceneTree
const T=preload("res://scripts/building_type.gd").Type
const D=preload("res://scripts/building_definition.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const P=preload("res://scripts/resident_profession.gd").Type
var checks:=0
var failures:=0
var world: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func click(control: Control) -> void:
	var point:=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=down
		root.push_input(event,true)
func key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	root.push_input(event,true)
func choose(type: int) -> void:
	world._select_building_definition(world.construction_panel.catalogue.entries[StringName("building_%d" % type)].definition)
func place(point: Vector3):
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":point})
	return world.buildings[-1]
func run() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.set_process(false)
	world.set_physics_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	await process_frame
	await process_frame
	var ui=world.game_ui
	var panel=world.construction_panel
	var catalog=panel.catalogue
	var camera: Camera3D=world.get_node("World/Camera3D")
	var before: Transform3D=camera.global_transform
	var zoom: float=camera.get_zoom_distance()
	check(panel.collapsed and panel.sections.map(func(section): return section.id)==[&"construction",&"residents",&"areas",&"buildings"],"Construction TAB, Residents, Areas and Buildings QUICK_WINDOW; initial collapsed")
	check(panel.sections[0].kind==panel.Kind.TAB and panel.sections[1].kind==panel.Kind.QUICK_WINDOW and panel.sections[2].kind==panel.Kind.QUICK_WINDOW and panel.sections[3].kind==panel.Kind.QUICK_WINDOW,"Distinct registered action kinds")
	var names:=[]
	for category in catalog.categories: names.append(category.title)
	check(names==["Производство","Логистика","Поселение","Социальные","Декор"],"Five ordered building categories; no free road brush")
	var expected:=[[T.LUMBERJACK_HUT,T.QUARRY,T.GATHERER_HUT,T.SAWMILL,T.SHEPHERD_HUT,T.WEAVER_WORKSHOP,T.TAILOR_WORKSHOP,T.WINDMILL,T.FARM,T.CLAY_HUT,T.POTTERY_WORKSHOP,T.STONEMASON_WORKSHOP],[T.STORAGE,T.WELL],[T.HOME,T.FOOD],[T.GAZEBO],[T.FLOWERBED]]
	for index in range(5):
		var category: Dictionary=catalog.categories[index]
		var types:=[]
		for entry in category.entries:
			if entry.action==&"building": types.append(entry.definition.type)
			var tile: Button=catalog.tiles[entry.id]
			check(not tile.get_node("Content/Title").text.is_empty() and tile.get_node("Content/Icon").texture!=null,"Permanent title and real icon: "+entry.name)
		check(types==expected[index],"Correct category contents "+category.title)
	check(catalog.tiles.size()==18 and catalog.tile_for_type(T.TOWN_CENTER)==null,"Eighteen buildings including social/decorative types; no manual road or Town Center")
	check(not catalog.entries.has(&"dirt_road"),"No free manual road in ordinary catalogue")
	click(panel.collapse_button)
	await process_frame
	await process_frame
	check(not panel.collapsed and catalog.visible,"TAB expands upwards")
	for id in catalog.category_buttons:
		click(catalog.category_buttons[id])
		await process_frame
		check(catalog.category_id==id,"Category button "+String(id))
	catalog.select_category(&"settlement")
	await process_frame
	await process_frame
	world.resident_selection.select(world.residents[0])
	var count: int=world.buildings.size()
	click(catalog.tile_for_type(T.HOME))
	check(world.placement.is_active() and world.resident_selection.selected_entity==null and world.buildings.size()==count,"Tile selects a tool/clears selection; UI press/release never confirms")
	check(ui.info_panel._preview_definition==world.placement.selected_definition,"Preview uses the same actual Definition")
	check(not ui.info_panel.preview.get_node("Description").text.is_empty(),"UI purpose description available")
	var active: RefCounted=world.placement.selected_definition
	click(catalog.category_buttons[&"production"])
	check(world.placement.selected_definition==active and world.buildings.size()==count,"Category UI click does not confirm or replace tool")
	click(ui.residents_button)
	check(world.settlement_panel.visible and world.placement.is_active(),"QUICK_WINDOW opens previous real residents window without cancelling placement")
	key(KEY_ESCAPE)
	check(not world.settlement_panel.visible and world.placement.is_active(),"Window consumes first Esc")
	var dialog:=PanelContainer.new()
	ui.get_node("Windows").add_child(dialog)
	dialog.size=Vector2(50,50)
	ui.open_top_dialog(dialog)
	key(KEY_ESCAPE)
	check(not dialog.visible and world.placement.is_active(),"Top dialog consumes Esc")
	key(KEY_ESCAPE)
	check(not world.placement.is_active() and ui.info_panel.day_summary.visible,"Next Esc cancels building preview")
	dialog.queue_free()
	for turns in range(4):
		choose(T.HOME)
		world.placement.set_orientation(turns)
		var point:=Vector3(-18+turns*9,0,24)
		var first=place(point)
		check(world.buildings.size()==count+1 and first.quarter_turns==turns and world.placement.is_active(),"One click creates one real site and rearms orientation %d" % turns)
		count+=1
		check(world.placement.quarter_turns==turns and world.placement.selected_definition==catalog.entries[StringName("building_%d" % T.HOME)].definition,"Same definition/orientation after confirm")
		check(world.build_grid.occupied_cells(first.id)==world.build_grid.footprint_cells(C.to_world(first.position),first.definition.footprint_cells,turns),"Rotated actual footprint occupied")
		check(not world.navigation.is_world_walkable(C.to_world(first.position)),"Actual NavigationGrid blocker registered")
		place(point)
		check(world.buildings.size()==count and world.placement.is_active() and not world.placement.can_place(),"Invalid second click neither creates nor cancels")
		var second=place(point+Vector3(0,0,7))
		count+=1
		check(world.buildings.size()==count and second.id!=first.id and second.quarter_turns==turns,"Separate second click creates distinct site")
		world._cancel_active_world_tool()
	choose(T.SAWMILL)
	var cancel_callback:=func(_site): world._cancel_active_world_tool()
	world.placement.placed.connect(cancel_callback,CONNECT_ONE_SHOT)
	place(Vector3(-40,0,26))
	check(not world.placement.is_active() and not world.building_ghost.visible and ui.info_panel.day_summary.visible,"Cancellation inside placed callback wins; no rearm")
	choose(T.SAWMILL)
	var replace_callback:=func(_site): choose(T.HOME)
	world.placement.placed.connect(replace_callback,CONNECT_ONE_SHOT)
	place(Vector3(-40,0,15))
	check(world.placement.selected_definition.type==T.HOME and ui.info_panel._preview_definition.type==T.HOME,"Replacement during placed callback wins")
	# A queued event from the former generation cannot confirm a replacement.
	var stale:=InputEventMouseButton.new()
	stale.button_index=MOUSE_BUTTON_LEFT; stale.pressed=true; stale.position=Vector2(640,350)
	world._queue_world_click(stale)
	var old: InputEventMouseButton=world._clicks[0]
	choose(T.QUARRY)
	world._clicks.append(old)
	count=world.buildings.size()
	world._physics_process(0)
	check(world.buildings.size()==count and world._clicks.is_empty(),"Stale queued click rejected after switching tools")
	world.handle_world_click(MOUSE_BUTTON_RIGHT,{})
	check(not world.placement.is_active() and ui.info_panel.day_summary.visible,"RMB cancellation")
	choose(T.HOME)
	choose(T.HOME)
	check(not world.placement.is_active(),"Same active tile cancels")
	choose(T.HOME)
	panel.set_collapsed(true)
	check(not world.placement.is_active() and not world.building_ghost.visible and ui.info_panel.day_summary.visible,"Collapsing Construction cancels without confirm")
	# Even two queued copies of an old click cannot confirm a freshly rearmed tool.
	choose(T.HOME)
	var screen: Vector2=camera.unproject_position(Vector3(-15,0,-2))
	var duplicate_click:=InputEventMouseButton.new()
	duplicate_click.position=screen;duplicate_click.pressed=true;duplicate_click.button_index=MOUSE_BUTTON_LEFT
	world._queue_world_click(duplicate_click)
	world._queue_world_click(duplicate_click)
	count=world.buildings.size()
	world._physics_process(0)
	check(world.buildings.size()==count+1 and world.placement.is_active(),"Rearm invalidates remaining copies of one queued click")
	world._cancel_active_world_tool()
	choose(T.HOME)
	world._select_road_tool()
	check(world.road_tool.active and not world.placement.is_active() and not world.building_ghost.visible and ui.info_panel.day_summary.visible,"Building to real road; no definition preview")
	choose(T.HOME)
	check(world.placement.is_active() and not world.road_tool.active and not world._road_dragging,"Road to building ends stroke")
	world.player_control.assign_profession(world.residents[1].id,P.LUMBERJACK)
	panel.set_collapsed(false)
	world._start_work_area(world.residents[1].id)
	check(world.work_area_tool.active() and not world.placement.is_active() and not world.road_tool.active,"Building to WorkArea")
	panel.set_collapsed(true)
	check(world.work_area_tool.active(),"Collapsing catalogue does not cancel independent WorkArea tool")
	choose(T.QUARRY)
	check(world.placement.is_active() and not world.work_area_tool.active(),"WorkArea to construction")
	world.developer_panel.begin_placement(&"resource",preload("res://scripts/resource_type.gd").Type.LOG,1)
	check(world.developer_panel.active() and not world.placement.is_active(),"Construction to F10 tool")
	choose(T.HOME)
	check(not world.developer_panel.active() and world.placement.is_active(),"F10 tool to construction")
	ui.info_panel._close()
	check(not world.placement.is_active() and ui.info_panel.day_summary.visible,"Blue preview close cancels matching placement")
	choose(T.HOME)
	world.resident_selection.select(world.residents[0])
	check(not world.placement.is_active() and ui.info_panel.resident_details.visible,"Direct selection replaces incompatible preview/tool")
	panel.set_collapsed(false)
	await process_frame
	await process_frame
	var wheel:=InputEventMouseButton.new()
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=panel.get_global_rect().get_center()
	root.push_input(wheel,true)
	check(camera.get_zoom_distance()==zoom,"Catalogue wheel never zooms camera")
	check(camera.global_transform==before and camera.get_zoom_distance()==zoom,"All UI transitions preserve camera")
	world.free()
	print("E3 construction UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
