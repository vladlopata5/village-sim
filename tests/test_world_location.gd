extends SceneTree
const Location = preload("res://scripts/world_location.gd")
const Locations = preload("res://scripts/world_locations_2d.gd")
const Activity = preload("res://scripts/resident_activity.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var location = Location.new(&"home_stepan", "Дом Степана")
	check(location is RefCounted and not location is Node, "Place exists independently of presentation")
	var mapping = Locations.new()
	var marker := Marker2D.new()
	root.add_child(marker)
	mapping.register(location, marker)
	marker.position = Vector2(50, 60)
	check(mapping.get_location(location.id) == location and mapping.get_position(location.id) == Vector2(50, 60), "ID maps to original data and current position")
	location.display_name = "Переименован"
	marker.position = Vector2(70, 80)
	check(location.id == &"home_stepan" and mapping.get_position(location.id) == Vector2(70, 80), "Rename preserves ID; moving marker changes resolved position")
	marker.free()
	check(mapping.get_position(location.id) == null and mapping.get_location(location.id) == location, "Missing view preserves place data without fake coordinates")
	check(mapping.get_position(&"missing") == null, "Unknown ID returns null")
	var replacement := Marker2D.new()
	root.add_child(replacement)
	replacement.position = Vector2(90, 100)
	mapping.register(location, replacement)
	check(mapping.get_position(location.id) == replacement.global_position, "Replacement view reuses the same ID")
	replacement.queue_free()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	# Test this subsystem alone; need/schedule interaction has its own suite.
	scene.resident_runtimes[0].decision.free()
	scene.resident_runtimes[0].needs.free()
	await process_frame
	await process_frame
	var data = scene.residents[0]
	var home = scene.get_node("World/home_stepan")
	var clock = scene.game_time
	var view = scene.resident_runtimes[0].view
	clock.set_process(false)
	view.set_process(false)
	check(data.home_location_id == &"home_stepan" and home.location == scene.world_locations.get_location(data.home_location_id), "Resident and marker refer to same place")
	check(home.location.display_name == "Дом Степана" and home.get_node("Caption").text == home.location.display_name, "Marker caption comes from place data")
	home.position = Vector2(-450, 160)
	while clock.get_phase() != "Ночь":
		clock.debug_next_phase()
	check(view.target_position == home.global_position and data.activity == Activity.Type.MOVING, "Night resolves moved marker instead of cached coordinates")
	view._process(20.0)
	check(view.global_position == home.global_position and data.activity == Activity.Type.SLEEPING, "Night arrival still sleeps")
	clock.debug_next_phase()
	check(data.activity == Activity.Type.IDLE and scene.resident_runtimes[0].schedule.request_manual_move(Vector2(100, 100)), "Morning wakes and allows manual move")
	view._process(20.0)
	check(data.activity == Activity.Type.IDLE, "Manual arrival remains IDLE")
	data.home_location_id = &"missing"
	home.free() # Missing assigned home falls back safely to local outdoor sleep.
	while clock.get_phase() != "Ночь":
		clock.debug_next_phase()
	check(not view.has_movement_target and data.activity == Activity.Type.SLEEPING, "Missing home sleeps outdoors without bogus movement")
	clock.debug_next_phase()
	check(not scene.resident_runtimes[0].schedule.is_night, "Missing home still releases night lock in morning")
	check(data.fatigue >= 0 and data.fatigue <= 100 and data.mood == 65, "Place lookup leaves mood unchanged and fatigue bounded")
	scene.queue_free()
	print("World location checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
