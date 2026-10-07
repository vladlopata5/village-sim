extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const PlayerAPI = preload("res://scripts/player_control.gd")
const Service = preload("res://scripts/interaction_service.gd")
const Option = preload("res://scripts/interaction_option.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const EventLog = preload("res://scripts/game_logger.gd")
const WOOD = preload("res://scripts/resource_type.gd").Type.WOOD
class ControlSpy extends "res://scripts/player_control.gd":
	var calls: Array = []
	func assign_home(resident_id: String, building_id: StringName) -> bool:
		calls.append(["assign", resident_id, building_id])
		return super.assign_home(resident_id, building_id)
	func clear_home(resident_id: String) -> bool:
		calls.append(["clear", resident_id])
		return super.clear_home(resident_id)
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func make_house(id: StringName, state: int = Instance.State.BUILT):
	return Instance.new(id, Definition.for_type(Types.HOME), Vector2.ZERO, state)
func housing_options(service: RefCounted, id: String, target: StringName) -> Array:
	return service.get_interactions([id], target).filter(func(option): return option.id in [&"assign_home", &"clear_home"])
func click(point: Vector2, button: MouseButton) -> void:
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
	var population: Array = []
	for i in range(6): population.append(Data.new("r%d" % i, "Resident %d" % i, 30))
	check(population.all(func(resident): return resident.home_location_id.is_empty()), "Residents default to optional empty home")
	check(Balance.HOUSE_RESIDENT_CAPACITY == 4 and Definition.for_type(Types.HOME).housing_capacity == 4, "Prototype house capacity centralized")
	for type in [Types.STORAGE, Types.FOOD, Types.GATHERER_HUT]:
		check(Definition.for_type(type).housing_capacity == 0, "Non-house capacity zero")
	var a = make_house(&"house_a")
	var b = make_house(&"house_b")
	var unfinished = make_house(&"unfinished", Instance.State.UNDER_CONSTRUCTION)
	var buildings: Array = [a, b, unfinished]
	for type in [Types.STORAGE, Types.FOOD, Types.GATHERER_HUT]: buildings.append(Instance.new(StringName("other_%d" % type), Definition.for_type(type)))
	var control = PlayerAPI.new()
	control.setup(population, buildings)
	check(not control.is_housing_target(preload("res://scripts/world_location.gd").new(&"house_marker", "Дом")), "World marker alone is not a housing BuildingInstance")
	check(not control.assign_home("missing", a.id) and not control.assign_home(population[0].id, &"missing"), "Unknown resident/building rejected")
	check(not control.assign_home(population[0].id, unfinished.id), "Construction house not eligible")
	for building in buildings.slice(3): check(not control.assign_home(population[0].id, building.id), "Only built house can be home")
	var transitions: Array = []
	control.home_changed.connect(func(id, old_id, new_id): transitions.append([id, old_id, new_id]))
	for i in range(4): check(control.assign_home(population[i].id, a.id), "Four residents accepted")
	check(control.get_home_occupants(a.id).size() == 4 and population[0].home_location_id == a.id, "Occupants derived from sole resident relation")
	check(not control.assign_home(population[0].id, a.id) and transitions.size() == 4, "Same home is a no-op without duplicate/event")
	check(not control.assign_home(population[4].id, a.id) and population[4].home_location_id.is_empty(), "Fifth resident rejected without losing default state")
	check(control.assign_home(population[4].id, b.id), "Other house accepted")
	check(not control.assign_home(population[4].id, a.id) and population[4].home_location_id == b.id, "Failed reassign preserves old home")
	check(control.clear_home(population[0].id) and control.get_home_occupants(a.id).size() == 3 and population[0].home_location_id.is_empty(), "Clear releases capacity")
	check(not control.clear_home(population[0].id) and not control.clear_home("missing"), "Already homeless/unknown clear safe")
	check(control.assign_home(population[4].id, a.id) and control.get_home_occupants(b.id).is_empty(), "Reassign replaces link and frees old house immediately")
	check(control.assign_home(population[0].id, b.id), "Freed house slot can be reused")
	var queried: Array = control.get_home_occupants(a.id)
	queried.clear()
	check(control.get_home_occupants(a.id).size() == 4, "Query result cannot mutate housing ownership")
	# Direct source data imported by existing factory/generator is still the source of truth.
	population[5].home_location_id = b.id
	check(control.get_home_occupants(b.id).size() == 2 and control.get_home(population[5].id) == b, "Query reflects source data without synchronized house list")
	population[5].home_location_id = &"deleted"
	check(control.get_home(population[5].id) == null and control.clear_home(population[5].id), "Invalid home references safe and clearable")
	var service = Service.new()
	service.control = control
	for building in buildings: service.register_building(building, func(): return Vector2.ZERO)
	var options = housing_options(service, population[0].id, a.id)
	check(options.size() == 1 and options[0].label == "Назначить дом" and not options[0].enabled and options[0].disabled_reason == "Дом заполнен", "Full house shown disabled with reason")
	options = housing_options(service, population[4].id, a.id)
	check(options.size() == 1 and options[0].id == &"clear_home" and options[0].label == "Выселиться" and options[0].enabled, "Current house offers eviction even when full")
	check(options[0].interaction_kind == Option.Kind.MANAGEMENT_ACTION, "Housing is management, not command/assignment")
	for building in buildings.slice(2): check(housing_options(service, population[0].id, building.id).is_empty(), "No housing interaction on unfinished/non-house")
	control.clear_home(population[1].id)
	options = housing_options(service, population[0].id, a.id)
	check(options[0].enabled and service.execute([population[0].id], options[0]), "Context service assigns available house")
	check(population[0].home_location_id == a.id and control.get_home_occupants(b.id).is_empty(), "Context reassignment uses API")
	var stale = housing_options(service, population[5].id, b.id)[0]
	for i in range(4): control.clear_home(population[i].id); control.assign_home(population[i].id, b.id)
	check(not service.execute([population[5].id], stale) and population[5].home_location_id.is_empty(), "Context revalidates capacity at execution")
	# House completion enables assignment only; it never auto-fills.
	unfinished.add_delivered_material(WOOD, unfinished.get_required_amount(WOOD))
	unfinished.construction_progress = unfinished.definition.construction_work_required
	check(unfinished.complete_construction() and control.get_home_occupants(unfinished.id).is_empty(), "Completed house has no automatic occupants")
	service.register_building(unfinished, func(): return Vector2.ZERO)
	check(housing_options(service, population[5].id, unfinished.id)[0].enabled and control.assign_home(population[5].id, unfinished.id), "Completed house immediately eligible")
	# Real right-click menu and immediate card events, with per-frame card updates disabled.
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[0]
	var resident_card = scene.get_node("HUD/ResidentCard")
	var building_card = scene.get_node("HUD/BuildingCard")
	resident_card.set_process(false)
	building_card.set_process(false)
	var old_house = scene.player_control.get_home(actor.data.id)
	var new_house = scene.player_control.get_home(scene.residents[1].id)
	for resident in scene.residents: scene.player_control.clear_home(resident.id)
	scene.resident_selection.select(actor.data)
	check(resident_card.home_label.text == "Дом: Нет дома", "Resident card shows homeless")
	scene.get_node("HUD/DebugPanel").set_collapsed(true)
	await process_frame
	await process_frame
	var screen_position: Vector2 = scene.field.get_global_transform_with_canvas() * old_house.position
	click(screen_position, MOUSE_BUTTON_RIGHT)
	check(scene.interaction_menu.visible and scene.interaction_menu.options.any(func(option): return option.id == &"assign_home" and option.enabled), "Actual RMB on house opens housing interaction")
	var assign_option = housing_options(scene.interactions, actor.data.id, old_house.id)[0]
	scene.interaction_menu._choose(assign_option)
	check(actor.data.home_location_id == old_house.id and resident_card.home_label.text == "Дом: %s (%s)" % [old_house.display_name, old_house.id], "Assign updates resident card synchronously without frame")
	check(actor.commands.active_command == null and actor.data.assignments.is_empty(), "Housing creates no command or assignment")
	scene.resident_selection.select_building(old_house)
	check(building_card.housing_section.visible and building_card.housing_count.text == "Жильцы: 1 / 4" and building_card.housing_residents.text.contains("Степан"), "House card shows count and names")
	# A second card demonstrates that both old and new views receive the same change.
	var second_selection = preload("res://scripts/resident_selection.gd").new()
	root.add_child(second_selection)
	var second_card = load("res://scenes/building_card.tscn").instantiate()
	root.add_child(second_card)
	second_card.set_process(false)
	second_card.bind_selection(second_selection)
	second_card.bind_control(scene.player_control)
	second_selection.select_building(new_house)
	check(second_card.housing_count.text == "Жильцы: 0 / 4" and second_card.housing_residents.text == "Нет жильцов", "Empty house UI explicit")
	check(scene.player_control.assign_home(actor.data.id, new_house.id), "Real reassign")
	check(building_card.housing_count.text == "Жильцы: 0 / 4" and second_card.housing_count.text == "Жильцы: 1 / 4", "Old/new cards update synchronously on reassign event")
	scene.resident_selection.select(actor.data)
	check(resident_card.home_label.text.contains(new_house.id), "Selection refresh shows current home")
	check(scene.player_control.clear_home(actor.data.id) and resident_card.home_label.text == "Дом: Нет дома" and second_card.housing_count.text == "Жильцы: 0 / 4", "Clear immediately updates both presentations")
	actor.data.home_location_id = &"absent"
	check(resident_card.home_label.text == "Дом: Нет дома", "Invalid housing reference safely renders homeless")
	for building in [scene.warehouse_data, scene.kitchen_data, scene.gatherer_hut_data]:
		scene.resident_selection.select_building(building)
		check(not building_card.housing_section.visible, "Non-house card has no housing block")
	# New placement remains construction-only until completed, then housing section appears.
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_position(Vector2(600, 400))
	var placed = scene.placement.confirm()
	scene.resident_selection.select_building(placed)
	check(building_card.construction_section.visible and not building_card.housing_section.visible and not scene.player_control.assign_home(actor.data.id, placed.id), "Placed unfinished house has no active housing")
	placed.add_delivered_material(WOOD, placed.get_required_amount(WOOD))
	placed.construction_progress = placed.definition.construction_work_required
	placed.complete_construction()
	check(building_card.housing_section.visible and building_card.housing_count.text == "Жильцы: 0 / 4" and not building_card.construction_section.visible, "Completion event reveals empty housing section")
	check(housing_options(scene.interactions, actor.data.id, placed.id)[0].enabled, "Main registers completed house housing interaction")
	# Management preserves a committed action, command, and existing assignment instance.
	scene.resident_selection.select(actor.data)
	actor.social.try_leisure(1000)
	var current = actor.intents.current_intent
	var task = Assignment.new(&"housing_test_eat", actor.data.id, Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	scene.player_control.add_assignment(actor.data.id, task)
	var decisions: int = actor.decision.decision_count
	scene.player_control.assign_home(actor.data.id, placed.id)
	check(actor.data.activity == Activity.RELAXING and actor.intents.current_intent == current and actor.decision.decision_count == decisions and actor.data.assignments[0] == task, "Home change preserves committed action/assignment and creates no decision")
	scene.player_control.move_to(actor.data.id, Vector2(300, 300))
	var command = actor.commands.active_command
	current = actor.intents.current_intent
	scene.player_control.clear_home(actor.data.id)
	check(actor.commands.active_command == command and actor.intents.current_intent == current, "Clear home leaves PlayerCommand untouched")
	# Housing now determines the next night action; changing an active sleep still does not wake.
	actor.view._process(20) # Complete the existing MOVE_TO normally.
	for runtime in scene.resident_runtimes: runtime.intents.cancel_current(runtime.intents.current_intent)
	scene.player_control.assign_home(actor.data.id, placed.id)
	scene.player_control.clear_home(actor.data.id)
	while scene.game_time.get_phase() != "Ночь": scene.game_time.debug_next_phase()
	check(actor.intents.current_intent.reason_id == &"night_outdoor" and not actor.view.has_movement_target, "Cleared housing starts outdoor sleep")
	actor.view._process(20)
	check(actor.data.activity == Activity.SLEEPING and actor.data.home_location_id.is_empty(), "Outdoor sleep works with no assigned housing")
	var sleeping = actor.intents.current_intent
	scene.player_control.assign_home(actor.data.id, placed.id)
	check(actor.data.activity == Activity.SLEEPING and actor.intents.current_intent == sleeping, "Assigning home never wakes/moves sleeping resident")
	second_card.free()
	second_selection.free()
	scene.free()
	# Interaction calls the existing management API, with no UI mutation.
	var spy = ControlSpy.new()
	spy.setup(population, buildings)
	service.control = spy
	spy.clear_home(population[0].id)
	options = housing_options(service, population[0].id, a.id)
	service.execute([population[0].id], options[0])
	check(spy.calls.back() == ["assign", population[0].id, a.id], "Housing context delegates resident/building ids to API")
	service.execute([population[0].id], housing_options(service, population[0].id, a.id)[0])
	check(spy.calls.back() == ["clear", population[0].id], "Eviction context delegates to clear_home API")
	var lines: Array[String] = []
	spy.logger = EventLog.new()
	spy.logger.console_enabled = false
	spy.logger.line_logged.connect(func(line, _level): lines.append(line))
	spy.assign_home(population[0].id, a.id)
	spy.assign_home(population[0].id, unfinished.id)
	spy.clear_home(population[0].id)
	check(lines.size() == 3 and lines[0].contains("назначен дом") and lines[1].contains("сменил дом") and lines[2].contains("больше не имеет"), "INFO logs assign/reassign/clear once each")
	for line in lines: print(line)
	print("Housing foundation: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
