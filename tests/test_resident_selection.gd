extends SceneTree
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var selection = scene.get_node("ResidentSelection")
	var view = scene.get_node("World/ResidentView2D")
	var card = scene.get_node("HUD/ResidentCard")
	var camera: Camera2D = scene.get_node("World/Camera2D")
	var field: Node2D = scene.get_node("World/Field")
	check(selection.selected_resident == null and not card.visible, "Initially no selection or card")
	var resident_point: Vector2 = view.get_global_transform_with_canvas() * Vector2.ZERO
	click_at(resident_point)
	check(selection.selected_resident == scene.resident_data, "Click selects the original data")
	check(card.visible, "Card opens on click")
	check(card.name_label.text == "Имя: Степан", "Card name")
	check(card.age_label.text == "Возраст: 30", "Card age")
	check(card.profession_label.text == "Профессия: Носильщик", "Card profession")
	check(card.id_label.text == "ID: resident_001", "Card ID")
	# UI must read live data, rather than keeping a resident snapshot.
	scene.resident_data.resident_name = "Проверка"
	scene.resident_data.age = 31
	scene.resident_data.profession = preload("res://scripts/resident_profession.gd").Type.NONE
	scene.resident_data.id = "test_id"
	await process_frame
	await process_frame
	check(card.name_label.text == "Имя: Проверка" and card.age_label.text == "Возраст: 31", "Card reads current name and age")
	check(card.profession_label.text == "Профессия: Без профессии" and card.id_label.text == "ID: test_id", "Card reads current profession and ID")
	await process_frame
	click_at(card.name_label.get_global_rect().get_center())
	check(selection.selected_resident == scene.resident_data and card.visible, "Click on card does not clear selection")
	click_at(scene.pause_button.get_global_rect().get_center())
	check(paused and card.visible, "HUD click preserves selection and pauses")
	click_at(card.close_button.get_global_rect().get_center())
	check(selection.selected_resident == null and not card.visible, "Close button clears selection on pause")
	click_at(resident_point)
	check(selection.selected_resident == scene.resident_data and card.visible, "Resident selectable on pause")
	var empty_point: Vector2 = field.get_global_transform_with_canvas() * Vector2(-150, 150)
	click_at(empty_point)
	check(selection.selected_resident == null and not card.visible, "Empty field clears selection on pause")
	paused = false
	camera.position = Vector2(200, 100)
	camera.force_update_scroll()
	await process_frame
	resident_point = view.get_global_transform_with_canvas() * Vector2(0, -22)
	click_at(resident_point)
	check(selection.selected_resident == scene.resident_data, "Head selectable after camera movement")
	empty_point = field.get_global_transform_with_canvas() * Vector2(-150, 150)
	click_at(empty_point)
	check(selection.selected_resident == null and not card.visible, "Empty field clears selection after camera movement")
	# Selection keeps data independently of the representation's lifetime.
	click_at(resident_point)
	view.free()
	check(selection.selected_resident == scene.resident_data and card.visible, "Selection survives visual replacement")
	selection.clear()
	scene.queue_free()
	print("Selection checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
