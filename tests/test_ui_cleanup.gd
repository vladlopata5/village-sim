extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	var card = scene.get_node("HUD/ResidentCard")
	var hud = scene.get_node("HUD/DebugPanel")
	scene.resident_selection.select(actor.data)
	await process_frame
	await process_frame
	check(not hud.collapsed and hud.extended_content.is_visible_in_tree(), "Expanded default")
	var original_size: Vector2 = hud.size
	var time: int = scene.game_time.total_minutes
	var speed: int = scene.game_time.speed_multiplier
	var hunger: int = actor.data.hunger
	var camera: Vector2 = scene.get_node("World/Camera2D").position
	click(hud.collapse_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(hud.collapsed and not hud.extended_content.visible and hud.collapse_button.text == "Развернуть", "Real click collapses content")
	check(scene.clock_label.is_visible_in_tree() and scene.phase_label.is_visible_in_tree() and not scene.food_label.is_visible_in_tree(), "Compact header stays; resources hidden")
	check(hud.size.y < original_size.y and hud.size.x < original_size.x, "Collapsed panel shrinks")
	check(scene.resident_selection.selected_resident == actor.data and scene.game_time.total_minutes == time and scene.game_time.speed_multiplier == speed and actor.data.hunger == hunger and scene.get_node("World/Camera2D").position == camera, "Collapse changes only presentation state")
	for point in [scene.clock_label.get_global_rect().get_center(), card.name_label.get_global_rect().get_center()]:
		click(point, MOUSE_BUTTON_RIGHT)
		check(actor.commands.active_command == null and not scene.interaction_menu.visible, "UI blocks right click command and interaction")
		click(point)
		check(scene.resident_selection.selected_resident == actor.data, "UI left click preserves selection")
	click(hud.collapse_button.get_global_rect().get_center())
	await process_frame
	await process_frame
	check(not hud.collapsed and scene.food_label.is_visible_in_tree() and hud.collapse_button.text == "Свернуть", "Expand restores resources and help")
	click(scene.food_label.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	check(actor.commands.active_command == null, "Expanded resource text also blocks world input")
	actor.data.hunger = 45
	card._refresh()
	check(card.hunger_label.text == "Голод: 45 — Немного голоден", "Compact needs retain values and descriptions")
	check(not card.profession_label.visible and not card.activity_label.visible and "Без профессии" in card.summary_label.text, "One profession/activity summary")
	check(card.traits_label.text.begins_with("Черты") and card.age_label.visible and card.id_label.visible, "Traits shorter, age and ID retained")
	var task := Assignment.new(&"ui", actor.data.id, Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	scene.player_control.add_assignment(actor.data.id, task)
	check(card.assignment_list.get_child(0).get_meta("assignment_id") == task.id, "Assignment list still event-driven")
	card.assignment_list.get_child(0).get_child(2).pressed.emit()
	check(task.state == Assignment.State.CANCELLED and card.assignment_list.get_child(0).text == "Поручений нет", "Cancel still delegates to existing API")
	scene.resident_selection.select(scene.residents[2])
	check("Фёдор" in card.name_label.text and "Собиратель" in card.summary_label.text, "Selection updates compact summary")
	await process_frame
	check(card.id_label.get_line_count() == 1 and card.get_global_rect().encloses(card.id_label.get_global_rect()), "Metadata ID stays on one readable line")
	check(card.get_global_rect().size.x < 320 and root.get_visible_rect().encloses(card.get_global_rect()), "Narrower card fits viewport")
	scene.free()
	print("UI cleanup: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
