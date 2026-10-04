extends SceneTree
const ResidentData = preload("res://scripts/resident_data.gd")
const StateText = preload("res://scripts/resident_state_text.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	# Test both ends of every text band, including the complete 0–100 range.
	var boundaries := [0, 24, 25, 49, 50, 74, 75, 100]
	var hunger_texts := ["Сыт", "Немного голоден", "Голоден", "Очень голоден"]
	var fatigue_texts := ["Отдохнувший", "Немного устал", "Устал", "Очень устал"]
	var mood_texts := ["Очень плохое", "Плохое", "Хорошее", "Отличное"]
	for index in range(boundaries.size()):
		var band := int(index / 2.0)
		var value: int = boundaries[index]
		check(StateText.hunger_description(value) == hunger_texts[band], "Hunger boundary %d" % value)
		check(StateText.fatigue_description(value) == fatigue_texts[band], "Fatigue boundary %d" % value)
		check(StateText.mood_description(value) == mood_texts[band], "Mood boundary %d" % value)
	var independent = ResidentData.new("test", "Тест", 25, "Без профессии")
	for property in ["hunger", "fatigue", "mood"]:
		independent.set(property, -1)
		check(independent.get(property) == 0, "Clamp lower bound: " + property)
		independent.set(property, 101)
		check(independent.get(property) == 100, "Clamp upper bound: " + property)
		independent.set(property, 49)
		check(independent.get(property) == 49, "Preserve valid value: " + property)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var data = scene.resident_data
	var selection = scene.get_node("ResidentSelection")
	var card = scene.get_node("HUD/ResidentCard")
	var clock = scene.get_node("GameTime")
	check(data.hunger == 20 and data.fatigue == 35 and data.mood == 65, "Stepan starts with explicit test values")
	selection.select(data)
	check(card.hunger_label.text == "Голод: 20/100 — Сыт", "Initial hunger display")
	check(card.fatigue_label.text == "Усталость: 35/100 — Немного устал", "Initial fatigue display")
	check(card.mood_label.text == "Настроение: 65/100 — Хорошее", "Initial mood display")
	clock.set_process(false)
	for speed in [1, 2, 4]:
		clock.set_speed(speed)
		clock.advance(1440.0)
	check(data.hunger == 20 and data.fatigue == 35 and data.mood == 65, "Passing time never changes resident states")
	data.traits.clear()
	check(data.hunger == 20 and data.fatigue == 35 and data.mood == 65, "Traits do not affect states")
	data.hunger = 75
	data.fatigue = 50
	data.mood = 0
	paused = true
	await process_frame
	await process_frame
	check(card.hunger_label.text == "Голод: 75/100 — Очень голоден", "Card reads updated hunger on pause")
	check(card.fatigue_label.text == "Усталость: 50/100 — Устал", "Card reads updated fatigue on pause")
	check(card.mood_label.text == "Настроение: 0/100 — Очень плохое", "Card reads updated mood on pause")
	card.show_state_numbers = false
	await process_frame
	await process_frame
	check(card.hunger_label.text == "Голод: Очень голоден", "Numbers can be hidden without changing data")
	check(card.fatigue_label.text == "Усталость: Устал" and card.mood_label.text == "Настроение: Очень плохое", "Description-only display")
	check(data.hunger == 75 and data.fatigue == 50 and data.mood == 0, "UI only reads state data")
	selection.select(independent)
	await process_frame
	await process_frame
	check(card.hunger_label.text == "Голод: Немного голоден", "Switching resident reads its own states")
	selection.select(data)
	await process_frame
	await process_frame
	check(card.get_global_rect().encloses(card.close_button.get_global_rect()), "Close button fits expanded card")
	check(root.get_visible_rect().encloses(card.get_global_rect()), "Card fits viewport")
	selection.clear()
	check(not card.visible, "Card still closes")
	paused = false
	scene.queue_free()
	print("State checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
