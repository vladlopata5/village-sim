extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	event.echo=echo
	root.push_input(event,true)
func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=point
	event.button_index=button
	event.pressed=pressed
	root.push_input(event,true)
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	await process_frame
	var ui = world.game_ui
	var camera: Camera3D=world.get_node("World/Camera3D")
	world.resident_selection.select(world.residents[0])
	world._select_building_definition(preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME))
	ui.open_window(&"residents")
	var dialog := PanelContainer.new() # Test fixture, no future UI in production.
	dialog.position=Vector2(580,200)
	dialog.size=Vector2(150,100)
	ui.get_node("Windows").add_child(dialog)
	ui.open_top_dialog(dialog)
	key(KEY_ESCAPE)
	check(not dialog.visible and world.settlement_panel.visible and world.placement.is_active(),"Esc closes only top dialog")
	key(KEY_ESCAPE,true,true)
	check(world.settlement_panel.visible and world.placement.is_active(),"Esc echo cannot cascade")
	key(KEY_ESCAPE)
	check(not world.settlement_panel.visible and world.placement.is_active(),"Second Esc closes only ordinary window")
	key(KEY_ESCAPE)
	check(not world.placement.is_active() and world.resident_selection.selected_entity==null,"Third Esc cancels tool only; E3 tile selection was cleared")
	# Exactly one ordinary window, without constructing future production windows.
	ui.register_window(&"test",dialog)
	ui.open_window(&"residents")
	ui.open_window(&"test")
	check(dialog.visible and not world.settlement_panel.visible,"Ordinary window replacement closes previous window")
	ui.close_window()
	var point: Vector2=ui.time_controls.get_global_rect().get_center()
	var count: int=world.buildings.size()
	world._select_building_definition(preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME))
	var before: float=camera.size
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_WHEEL_UP]:
		mouse(point,button,true)
		mouse(point,button,false)
	await physics_frame
	check(world.buildings.size()==count and world.placement.is_active() and world._clicks.is_empty(),"UI press/release neither confirms nor cancels placement or queues world click")
	check(camera.size==before,"Wheel over UI never zooms camera")
	world.placement.cancel()
	ui.open_window(&"residents")
	var scroll: Vector2=world.settlement_panel.get_global_rect().get_center()
	mouse(scroll,MOUSE_BUTTON_WHEEL_DOWN,true)
	mouse(scroll,MOUSE_BUTTON_WHEEL_DOWN,false)
	check(camera.size==before,"Scrollable population window owns wheel")
	ui.close_window()
	world.social_feed.add_message("Проверка границы существующей ленты")
	await process_frame
	var feed_point: Vector2=world.social_feed.get_global_rect().get_center()
	mouse(feed_point,MOUSE_BUTTON_RIGHT,true)
	mouse(feed_point,MOUSE_BUTTON_RIGHT,false)
	check(not ui.input_context.pointer_blocked(feed_point) and not world._clicks.is_empty(),"Passive message feed permits normal world input")
	world._clear_world_input()
	await physics_frame
	# An interface transition must discard an already queued world click.
	mouse(Vector2(700,450),MOUSE_BUTTON_RIGHT,true)
	check(not world._clicks.is_empty(),"World click initially enters normal deferred queue")
	ui.open_window(&"residents")
	await physics_frame
	check(world._clicks.is_empty() and world.resident_runtimes[0].commands.active_command==null,"Opening UI clears pending world click before execution")
	ui.close_window()
	world.interaction_menu.open_for([world.residents[0].id],world.warehouse_data.id,Vector2(600,160))
	check(world.interaction_menu.visible,"Actual context menu uses current interactions")
	mouse(Vector2(700,450),MOUSE_BUTTON_RIGHT,true)
	await physics_frame
	check(not world.interaction_menu.visible and world.resident_runtimes[0].commands.active_command==null,"Outside dismiss click cannot also issue MOVE_TO")
	world._select_road_tool()
	world._road_dragging=true
	world.road_tool._previous=Vector2i(10,10)
	var motion := InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	await physics_frame
	check(world.road_tool._previous==null,"Road motion through UI ends stroke; no interpolation across UI")
	mouse(point,MOUSE_BUTTON_LEFT,false)
	check(not world._road_dragging,"Release observed even over UI")
	world._cancel_road_tool()
	# A real focused field and real global keyboard state exercise the polling camera.
	var field := LineEdit.new()
	field.position=Vector2(600,200)
	field.size=Vector2(160,40)
	ui.get_node("Windows").add_child(field)
	ui.register_pointer_control(field)
	field.grab_focus()
	check(ui.input_context.text_editing(),"Text editing context sees GUI focus")
	world._select_building_definition(preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME))
	var orientation: int=world.placement.quarter_turns
	var transform_before := camera.global_transform
	var speed_before: int=world.game_time.speed_multiplier
	for code in [KEY_W,KEY_A,KEY_D,KEY_UP,KEY_R,KEY_4,KEY_SPACE,KEY_ENTER]: key(code)
	check(world.placement.quarter_turns==orientation and world.game_time.speed_multiplier==speed_before and not paused,"Text entry leaves rotation/speed/pause unchanged")
	var held := InputEventKey.new()
	held.physical_keycode=KEY_W
	held.keycode=KEY_W
	held.pressed=true
	Input.parse_input_event(held.duplicate())
	Input.flush_buffered_events()
	check(Input.is_physical_key_pressed(KEY_W), "Real global held-key state")
	camera._process(1.0)
	check(camera.global_transform==transform_before,"Polling camera ignores held W while text has focus")
	field.release_focus()
	camera._process(0.1)
	check(camera.global_transform!=transform_before,"Camera polling resumes after focus released")
	held.pressed=false
	Input.parse_input_event(held.duplicate())
	field.queue_free()
	world.placement.cancel()
	# F10 stays independent of quick access and can place while paused.
	key(KEY_F10)
	check(world.developer_panel.visible,"F10 opens real developer controls")
	world.game_time.toggle_pause()
	world.developer_panel.begin_placement(&"resource",preload("res://scripts/resource_type.gd").Type.LOG,1)
	ui.open_window(&"residents")
	key(KEY_ESCAPE)
	check(not world.settlement_panel.visible and world.developer_panel.active(),"Paused F10 Esc respects ordinary window priority")
	key(KEY_ESCAPE)
	check(not world.developer_panel.active() and world.developer_panel.visible,"Next paused Esc cancels developer tool only")
	world.developer_panel.begin_placement(&"resource",preload("res://scripts/resource_type.gd").Type.LOG,1)
	var drops: int=world.ground_resources.drops.size()
	mouse(point,MOUSE_BUTTON_LEFT,true)
	mouse(point,MOUSE_BUTTON_LEFT,false)
	await physics_frame
	check(world.ground_resources.drops.size()==drops and world.developer_panel._paused_clicks.is_empty(),"Paused developer placement also rejects UI clicks")
	key(KEY_F10)
	check(not world.developer_panel.visible and not world.developer_panel.active(),"F10 close cleans paused tool")
	world.game_time.toggle_pause()
	world.free()
	print("E1 UI input: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
