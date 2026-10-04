extends SceneTree
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const WorldLocation = preload("res://scripts/world_location.gd")
const Activity = preload("res://scripts/resident_activity.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.game_time.set_process(false)
	scene.resident_view.set_process(false)
	var building = scene.kitchen_data
	var view = scene.get_node("World/CommunalKitchen")
	var mapping = scene.world_locations
	var place = mapping.get_location(building.id)
	check(building is BuildingData and not building is Node, "Building exists as nonvisual game data")
	check(building.id == &"communal_kitchen_01" and building.display_name == "Общая кухня" and building.type == BuildingType.Type.FOOD, "Kitchen identity, name and category")
	check(place is WorldLocation and not place is BuildingData, "Place and building are distinct objects")
	check(place.id == building.id and place.display_name == building.display_name, "Building and world place linked by stable ID")
	check(view.building_data == building and view.get_node("Caption").text == building.display_name, "View reads original building data")
	check(view.is_visible_in_tree() and mapping.get_position(place.id) == view.global_position, "Kitchen visible and registered in existing coordinate mapping")
	var screen_rect := Rect2(view.get_global_transform_with_canvas() * Vector2(-72, -78), Vector2(144, 126))
	check(root.get_visible_rect().encloses(screen_rect), "Kitchen and caption fit starting viewport")
	view.position += Vector2(40, -20)
	check(mapping.get_position(place.id) == view.global_position, "World resolves moved kitchen without a separate coordinate copy")
	var data = scene.resident_data
	var hunger_before: int = data.hunger
	check(scene.resident_schedule.request_manual_move(mapping.get_position(place.id)), "Morning manual movement can target kitchen normally")
	scene.resident_view._process(20.0)
	check(data.hunger == hunger_before and data.activity == Activity.Type.IDLE, "Arriving at kitchen does not eat or reduce hunger")
	scene.game_time.advance(15.0)
	check(data.hunger == hunger_before + 1 and data.fatigue == 35 and data.mood == 65, "Kitchen does not change normal hunger growth or other states")
	# No building selection or interaction UI is introduced.
	check(view.get_node("Caption").mouse_filter == Control.MOUSE_FILTER_IGNORE, "Caption does not intercept world input")
	view.free()
	check(scene.kitchen_data == building and mapping.get_location(place.id) == place, "Building and place survive removal of representation")
	check(mapping.get_position(place.id) == null, "Removed view leaves no fake world position")
	var replacement = load("res://scenes/building_view_2d.tscn").instantiate()
	replacement.setup(building)
	replacement.position = Vector2(-280, 240)
	scene.get_node("World").add_child(replacement)
	mapping.register(place, replacement)
	check(replacement.building_data == building and mapping.get_position(place.id) == replacement.global_position, "Replacement representation reuses data and world identity")
	var building_count := 0
	for child in scene.get_node("World").get_children():
		if child.get_script() == preload("res://scripts/building_view_2d.gd"):
			building_count += 1
	check(building_count == 1, "Exactly one building representation")
	scene.queue_free()
	print("Building checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
