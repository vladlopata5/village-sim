extends SceneTree
const ResidentData = preload("res://scripts/resident_data.gd")
const TraitData = preload("res://scripts/trait_data.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	await process_frame
	await process_frame
	var data = scene.residents[0]
	var selection = scene.get_node("ResidentSelection")
	var card = scene.get_node("HUD/ResidentCard")
	var expected_ids := [&"hardworking", &"sociable", &"stubborn"]
	check(data.traits.size() == 3, "Test resident has three traits")
	for index in range(data.traits.size()):
		var trait_definition = data.traits[index]
		check(trait_definition is TraitData and not trait_definition is Node, "Trait is separate non-visual data")
		check(trait_definition.id == expected_ids[index] and not trait_definition.display_name.is_empty(), "Stable trait_definition ID and display name")
	selection.select(data)
	check(card.traits_label.text == "Известные черты:\n• Трудолюбивый\n• Общительный\n• Упрямый", "Card displays trait_definition names from data")
	# A display-name change must not change identity or require UI edits.
	var first_trait = data.traits[0]
	var original_name: String = first_trait.display_name
	first_trait.display_name = "Тестовое название"
	await process_frame
	await process_frame
	check(first_trait.id == &"hardworking", "Trait identity survives a name change")
	check(card.traits_label.text.contains("Тестовое название"), "Card reads the current trait_definition definition")
	first_trait.display_name = original_name
	# The collection is owned by the resident, not the card or another resident.
	var other = ResidentData.new("resident_002", "Тест", 25)
	check(other.traits.is_empty(), "New resident has its own empty trait_definition list")
	other.traits.append(first_trait)
	check(data.traits.size() == 3 and other.traits.size() == 1, "Trait lists are independent")
	var removed = data.traits.pop_back()
	paused = true
	await process_frame
	await process_frame
	check(not card.traits_label.text.contains("Упрямый"), "Trait removal updates open card on pause")
	data.traits.append(removed)
	await process_frame
	await process_frame
	check(card.traits_label.text.contains("Упрямый"), "Trait addition updates open card on pause")
	selection.select(other)
	check(card.traits_label.text == "Известные черты:\n• Трудолюбивый", "Switching resident reads the new list")
	other.traits.clear()
	await process_frame
	await process_frame
	check(card.traits_label.text == "Известные черты: нет", "Empty trait_definition list is displayed")
	selection.select(data)
	await process_frame
	await process_frame
	check(card.get_global_rect().encloses(card.close_button.get_global_rect()), "Close button fits the expanded card")
	selection.clear()
	check(not card.visible, "Card still closes")
	paused = false
	scene.queue_free()
	print("Trait checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
