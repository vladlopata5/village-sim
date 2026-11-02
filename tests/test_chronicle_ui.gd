extends SceneTree
const Skill = preload("res://scripts/skill_type.gd")
const BaseWindow = preload("res://scripts/ui/settlement_list_window.gd")
const Sequence = preload("res://tests/test_event_effects.gd").SequenceRng
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate(); root.add_child(world)
	world.game_time.set_process(false); world.game_logger.console_enabled = false; world.social_events.enabled = false
	world.game_events.executor.rng = Sequence.new()
	var ui: Control = world.game_ui; var window: Control = world.chronicle_window
	await process_frame
	check(window is BaseWindow and not window.visible and window.store == world.game_events.chronicle, "Same list framework, real world history, starts closed")
	check(world.construction_panel.buttons.has(&"chronicle") and world.construction_panel.buttons[&"chronicle"].text.contains("Летопись"), "A real quick button on the existing green strip")
	world.construction_panel.buttons[&"chronicle"].pressed.emit(); await process_frame
	check(window.visible and window.empty_label.visible and ui.pointer_blocked(window.get_global_rect().get_center()), "Open empty history; world input blocked inside window")
	check(window.table.get_root().get_first_child() == null, "Ordinary population creates no invented event rows")
	ui.open_window(&"residents")
	check(not window.visible and world.settlement_panel.visible, "Existing window exclusivity")
	var actor: RefCounted = world.residents[0]
	for index in 4:
		world.game_time.total_minutes = [1439,1440,4320,17280][index]
		actor.add_skill_xp(Skill.Type.values()[index],400)
	check(world.game_events.chronicle.size() == 4 and window.refresh_count == 1, "Hidden window does not rebuild on new events")
	world.resident_selection.select(actor)
	world.construction_panel.buttons[&"chronicle"].pressed.emit(); await process_frame
	check(window.visible and not world.settlement_panel.visible and world.resident_selection.selected_resident == actor and not window.empty_label.visible, "History preserves selection and replaces other window")
	var dates: Array = []; var times: Array = []
	var group: TreeItem = window.table.get_root().get_first_child()
	while group != null:
		dates.append(group.get_text(0)); times.append(group.get_first_child().get_text(0).left(5)); group = group.get_next()
	check(dates == ["День 1 · Весна","День 2 · Весна","День 4 · Лето","День 13 · Весна"] and times == ["23:59","00:00","00:00","00:00"], "Actual dates group entries through midnight, seasons and year wrap")
	for person in world.residents:
		for type in Skill.Type.values(): person.add_skill_xp(type,1000)
	await process_frame; await process_frame
	check(window.table.is_v_scroll_enabled() and window.table.get_root().get_first_child().get_next() != null and window.store.size() > 50, "Long history is scrollable and stays available")
	var bar: VScrollBar
	for child in window.table.get_children(true):
		if child is VScrollBar: bar = child
	check(bar != null and bar.max_value > bar.page, "Real native scrollbar has a scrollable history range")
	bar.value = minf(150.0,bar.max_value-bar.page)
	await process_frame
	check(window.table.get_scroll().y > 0, "History actually scrolls")
	var previous_scroll: float = window.table.get_scroll().y
	actor.add_skill_xp(Skill.Type.CONSTRUCTION,400)
	await process_frame; await process_frame
	check(is_equal_approx(window.table.get_scroll().y, previous_scroll), "An arriving event preserves the reader's scroll position")
	world.construction_panel.buttons[&"chronicle"].pressed.emit()
	check(not window.visible, "Second quick click closes the window")
	ui.open_window(&"chronicle"); await process_frame
	check(ui.try_escape() and not window.visible, "Existing Esc lifecycle")
	ui.open_window(&"chronicle"); window.close_button.pressed.emit()
	check(not window.visible, "Shared close control")
	ui.open_window(&"buildings"); ui.open_window(&"chronicle")
	check(not world.buildings_window.visible and window.visible, "Buildings/history switching")
	check(window.store.changed.get_connections().size() == 1, "One store subscription after repeated opens")
	if "--rendered" in OS.get_cmdline_user_args():
		await process_frame; await process_frame
		var path := OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--rendered")+1]
		root.get_texture().get_image().save_png(path)
	var history: RefCounted = window.store
	world.free(); await process_frame
	check(history.changed.get_connections().is_empty(), "Window destruction disconnects history subscription")
	print("Chronicle UI: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
