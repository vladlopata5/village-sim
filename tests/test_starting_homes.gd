extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const View = preload("res://scripts/building_view_2d.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const PLANK = preload("res://scripts/resource_type.gd").Type.PLANK
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
func night(scene: Node) -> void:
	scene.game_time.total_minutes = 1379
	scene.game_time.advance(1.0)
func _run() -> void:
	var scene = Setup.make_scene(self)
	scene.get_node("HUD/DebugPanel").set_collapsed(true)
	await process_frame
	await process_frame
	var card = scene.get_node("HUD/BuildingCard")
	var homes: Array = scene.buildings.filter(func(building): return building.type == Types.HOME)
	var ids := [&"home_stepan", &"home_anna", &"home_fedor", &"home_marina"]
	var positions := [Vector2(-300, -125), Vector2(-100, -200), Vector2(100, -200), Vector2(300, -125)]
	check(homes.size() == 4, "Starting world has exactly four ordinary HOME instances")
	check(not FileAccess.file_exists("res://scripts/world_location_view_2d.gd") and not FileAccess.file_exists("res://scenes/world_location_view_2d.tscn"), "Dead prototype home script/scene are removed")
	var seen: Array = []
	for index in range(homes.size()):
		var home = homes[index]
		var resident = scene.residents[index]
		var view = scene.world_locations.get_view(home.id)
		check(home is Instance and home.get_script() == Instance and home in scene.buildings, "Starting house is a plain BuildingInstance in Main.buildings")
		check(home.is_built() and home.state == Instance.State.BUILT, "Starting house is prebuilt")
		check(home.definition.id == &"home" and home.definition.type == Types.HOME and home.definition.housing_capacity == 4, "Uses normal HOME definition/capacity")
		check(home.id == ids[index] and home.id not in seen, "Unique stable home ID")
		seen.append(home.id)
		check(home.position == positions[index] and home.display_name == "Дом", "Grid-aligned source position and normal house label")
		check(resident.home_location_id == home.id and scene.player_control.get_home(resident.id) == home, "Initial resident relationship references concrete house")
		check(scene.player_control.get_home_occupants(home.id) == [resident], "Initial occupancy is one, derived from residents")
		check(view is View and view.building_data == home and not view is Marker2D, "Same BuildingView as player-built houses; no home marker")
		check(view.scene_file_path == "res://scenes/building_view_2d.tscn" and not view.has_node("Diamond"), "No prototype home visual nodes")
		check(scene.world_locations.get_position(home.id) == home.position and scene.world_locations.get_location(home.id).display_name == "Дом", "Normal world location registration")
		check(home.construction_progress == 0 and home.get_delivered_amount(PLANK) == 0 and home.active_builder_ids.is_empty(), "Prebuilt houses require no retroactive materials/work/builders")
		click(view.get_global_transform_with_canvas() * Vector2(20, 10))
		check(scene.resident_selection.selected_building == home and view.selected and card.visible, "Real LMB selects starter home through normal building flow")
		check(card.name_label.text == "Дом" and card.id_label.text == "ID: %s" % home.id and card.state_label.text == "Состояние: Построено", "Ordinary BuildingCard name/ID/state")
		check(card.housing_section.visible and card.housing_count.text == "Жильцы: 1 / 4" and resident.resident_name in card.housing_residents.text, "Ordinary housing card displays occupant")
		scene.resident_selection.clear()
		scene.placement.select(Definition.for_type(Types.HOME))
		scene.placement.update_position(home.position)
		check(not scene.placement.can_place() and scene.placement.confirm() == null and scene.buildings.size() == 7, "Starter footprint blocks overlapping player construction")
		scene.placement.cancel()
	check(scene.get_node("World").get_children().filter(func(child): return child is Marker2D).is_empty(), "World contains no independent prototype home markers")

	# Resident hit priority is unchanged even on top of a starter HOME.
	var actor = scene.resident_runtimes[0]
	actor.view.global_position = homes[0].position
	click(actor.view.get_global_transform_with_canvas().origin)
	check(scene.resident_selection.selected_resident == actor.data and scene.resident_selection.selected_building == null, "Exact resident overlap wins over house footprint")
	scene.resident_selection.clear()
	night(scene)
	for runtime in scene.resident_runtimes:
		var home = scene.player_control.get_home(runtime.data.id)
		check(runtime.view.target_position == home.position or runtime.data.activity == Activity.SLEEPING, "Ordinary night routing targets the same selectable BuildingInstance")
		runtime.view._process(20)
		check(runtime.data.activity == Activity.SLEEPING and runtime.view.global_position == home.position, "Residents physically sleep at their starting house")
	scene.game_time.debug_next_phase()

	# Reassign/clear changes occupancy and next night route, never deletes the home.
	scene.resident_selection.select_building(homes[0])
	check(scene.player_control.assign_home(actor.data.id, homes[1].id), "Starting house assignment can be replaced")
	check(scene.player_control.get_home_occupants(homes[0].id).is_empty() and scene.player_control.get_home_occupants(homes[1].id).size() == 2, "Reassign gives original 0/4 and destination 2/4")
	check(card.housing_count.text == "Жильцы: 0 / 4", "Old house card immediately updates after reassign")
	scene.resident_selection.select_building(homes[1])
	check(card.housing_count.text == "Жильцы: 2 / 4" and actor.data.resident_name in card.housing_residents.text, "New house card shows both occupants")
	night(scene)
	check(actor.view.target_position == homes[1].position, "Next night follows reassigned starter house")
	actor.view._process(20)
	scene.game_time.debug_next_phase()
	check(scene.player_control.clear_home(actor.data.id), "Resident can leave starter housing")
	check(homes[0] in scene.buildings and homes[1] in scene.buildings and homes[0].is_built(), "Eviction never removes houses")
	night(scene)
	check(actor.data.activity == Activity.SLEEPING and actor.intents.current_intent.reason_id == &"night_outdoor" and not actor.view.has_movement_target, "Evicted resident uses outdoor fallback")
	scene.game_time.debug_next_phase()

	# Placement, completion and resident reassignment use exactly the same type/view/API.
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_position(Vector2(600, 400))
	var placed = scene.placement.confirm()
	check(placed != null and placed.state == Instance.State.UNDER_CONSTRUCTION, "Player placement still starts UNDER_CONSTRUCTION")
	check(placed.definition.id == homes[0].definition.id and placed.definition.size == homes[0].definition.size and placed.definition.housing_capacity == 4, "One HOME definition type for starter/player buildings")
	placed.add_delivered_material(PLANK, placed.get_required_amount(PLANK))
	placed.construction_progress = placed.definition.construction_work_required
	check(placed.complete_construction() and placed.is_built(), "Normal player construction completes")
	var placed_view = scene.world_locations.get_view(placed.id)
	check(placed_view.get_script() == scene.world_locations.get_view(homes[0].id).get_script() and placed_view.scene_file_path == scene.world_locations.get_view(homes[0].id).scene_file_path, "Starter and player houses share visual class/scene")
	check(scene.player_control.assign_home(actor.data.id, homes[0].id) and scene.player_control.assign_home(actor.data.id, placed.id), "Same housing API reassigns starter to player-built home")
	scene.resident_selection.select_building(placed)
	check(card.name_label.text == "Дом" and card.housing_count.text == "Жильцы: 1 / 4" and not card.construction_section.visible, "Completed player house uses same BuildingCard")
	night(scene)
	check(actor.view.target_position == placed.position, "Reassigned sleep also targets player-built HOME")
	scene.free()
	print("Starting homes: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
