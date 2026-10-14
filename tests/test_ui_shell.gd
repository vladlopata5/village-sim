extends SceneTree
var checks := 0
var failures := 0
var rendered := false
var measurements: Array = []
const OUT = "C:/Users/SW/Documents/Codex/outputs/ui-e1-shell/"
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func snapshot(world: Node) -> Dictionary:
	var camera: Camera3D = world.get_node("World/Camera3D")
	return {"transform": camera.global_transform, "zoom": camera.get_zoom_distance()}
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
func capture(world: Node, name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var controls: Dictionary = {}
	for path in ["MessagesAnchor", "TimeAnchor/TimeControls", "ActionsAnchor", "InfoAnchor", "InfoAnchor/InfoPanel/Column/Body/ResidentDetails", "InfoAnchor/InfoPanel/Column/Body/BuildingDetails", "Windows"]:
		var node: Control = world.game_ui.get_node(path)
		controls[path] = {"rect":str(node.get_global_rect()),"visible":node.is_visible_in_tree()}
	controls["ConstructionPanel"] = {"rect":str(world.construction_panel.get_global_rect()),"visible":world.construction_panel.visible}
	controls["ResidentsWindow"] = {"rect":str(world.settlement_panel.get_global_rect()),"visible":world.settlement_panel.visible}
	controls["SocialFeed"] = {"rect":str(world.social_feed.get_global_rect()),"visible":world.social_feed.visible}
	measurements.append({"name":name,"window":str(root.size),"viewport":str(root.get_visible_rect()),"stretch":str(root.get_stretch_transform()),"controls":controls})
	root.get_texture().get_image().save_png(OUT+name+".png")
func run() -> void:
	rendered = "--rendered" in OS.get_cmdline_user_args()
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	await process_frame
	var ui = world.game_ui
	check(ui.get_parent()==world.get_node("HUD") and ui.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Real canonical shell in existing CanvasLayer; background ignores mouse")
	check(world.resident_selection==world.get_node("ResidentSelection") and world.residents.size()==4 and world.resident_runtimes.size()==4,"Single selection; no duplicate population bootstrap")
	check(world.resident_card_view()._selection==world.resident_selection,"ResidentCard shares existing selection")
	check(world.social_feed.get_parent()==ui.get_node("MessagesAnchor") and world.construction_panel.get_parent()==ui.get_node("ActionsAnchor"),"Actual feed and construction panel mounted")
	check(not world.has_node("HUD/DebugPanel") and world.population_label==null and world.production_label==null and world.logistics_label==null,"No hidden compatibility telemetry")
	check(ui.time_controls.speed_buttons.size()==3,"Player UI contains x1/x2/x4")
	for i in range(3):
		ui.time_controls.speed_buttons[i].pressed.emit()
		check(world.game_time.speed_multiplier==world.game_time.SUPPORTED_SPEEDS[i],"Real speed button %d" % i)
	ui.time_controls.pause_button.pressed.emit()
	check(paused and ui.time_controls.pause_button.text=="▶","Actual pause and caption")
	ui.time_controls.speed_buttons[0].pressed.emit()
	check(world.game_time.speed_multiplier==1 and paused,"Speed controls function while paused")
	ui.time_controls.pause_button.pressed.emit()
	world.game_time.total_minutes=1505
	world.game_time.minute_changed.emit(1505)
	await process_frame # E5 coalesces clock paint after domain listeners.
	check(ui.info_panel.day_summary.text=="День 2" and not ui.time_controls.has_node("Column/ClockRow/Day") and world.clock_label.text=="01:05","Day/time come from simulation clock")
	var before := snapshot(world)
	world.resident_selection.select(world.residents[0])
	ui.open_window(&"residents")
	check(world.settlement_panel.visible and world.resident_selection.selected_resident==world.residents[0],"Quick access preserves existing selection/card")
	ui.toggle_window(&"residents")
	ui.set_actions_expanded(false)
	ui.set_actions_expanded(true)
	check(snapshot(world)==before,"Window and panel transitions do not move/zoom camera")
	check(ui.active_green_tab()==&"construction","Only real construction content; no future sections")
	if rendered:
		# Exercise the real feed connection with an explicit presentation fixture,
		# without inventing domain history, journal entries or notification state.
		world.social_events.feed_message.emit("Лента сообщений: существующий SocialFeed")
		for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
			root.size=resolution
			await process_frame
			await process_frame
			check(is_equal_approx(world.construction_panel.size.x,ui.get_node("ActionsAnchor").size.x),"Old construction row fills available width")
			click(ui.time_controls.pause_button)
			check(paused,"Rendered GUI click pauses actual simulation")
			click(ui.time_controls.speed_buttons[2])
			check(world.game_time.speed_multiplier==4,"Rendered GUI speed click works while paused")
			click(ui.time_controls.pause_button)
			check(not paused,"Rendered GUI resume click")
			click(ui.time_controls.speed_buttons[0])
			world.resident_selection.select(world.residents[0])
			await capture(world,"shell_%d_resident" % resolution.x)
			check(not ui.info_panel.get_global_rect().intersects(ui.time_controls.get_global_rect()),"Time and transitional ResidentCard do not overlap")
			check(ui.get_node("InfoAnchor").z_index>ui.get_node("ActionsAnchor").z_index,"Blue owns intentional strip overlap")
			world.resident_selection.select_building(world.warehouse_data)
			ui.open_window(&"residents")
			await capture(world,"shell_%d_building_residents" % resolution.x)
			check(not world.settlement_panel.get_global_rect().intersects(world.building_card_view().get_global_rect()),"Existing residents window never overlaps card")
			ui.close_window()
		var file := FileAccess.open(OUT+"rendered-measurements.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(measurements,"\t"))
	world.free()
	var legacy = load("res://scenes/main.tscn").instantiate()
	root.add_child(legacy)
	legacy.game_time.set_process(false)
	check(legacy.has_node("HUD/DebugPanel") and legacy.resident_card_view()==legacy.get_node("HUD/ResidentCard") and legacy.ui_input_context()==null,"Legacy real HUD and default hooks unchanged")
	legacy.free()
	print("E1 UI shell: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
