extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Type = preload("res://scripts/need_type.gd").Type
const Job = preload("res://scripts/haul_job.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var lines: Array[String] = []
class ControlSpy extends RefCounted:
	signal residents_changed
	func get_residents() -> Array: return []
	signal home_changed(resident_id: String, previous: StringName, current: StringName)
	func get_home(_resident_id: String) -> RefCounted: return null
	func notify_home() -> void:
		home_changed.emit("", &"", &"")
		residents_changed.emit()
	var calls: Array = []
	func assign_profession(resident_id: String, profession: int) -> bool:
		calls.append([resident_id, profession])
		return true
	func current_intent(_resident_id: String): return null

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func work_api(scene: Node, runtime: Node) -> void:
	runtime.decision.work_available = scene._work_available.bind(runtime)
	runtime.decision.work_request = scene._request_work.bind(runtime)
	runtime.schedule.work_decision = runtime.decision.request_decision
func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
func listen(scene: Node) -> void:
	lines.clear()
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
func _run() -> void:
	var scene = Setup.make_scene(self)
	await process_frame
	await process_frame
	var card = scene.get_node("HUD/ResidentCard")
	for runtime in scene.resident_runtimes:
		click_at(runtime.view.get_global_transform_with_canvas() * Vector2.ZERO)
		check(scene.resident_selection.selected_resident == runtime.data, "Mouse selects the concrete simulation resident")
		check(scene.resident_runtimes.filter(func(other): return other.view.selected).size() == 1 and runtime.view.selected, "Exactly one highlighted resident")
		check(card.visible and runtime.data.resident_name in card.name_label.text and not card.intent_label.text.is_empty(), "Panel reads selected resident and action")
	click_at(scene.field.get_global_transform_with_canvas() * Vector2(-200, 250))
	check(scene.resident_selection.selected_resident == null and not card.visible and scene.resident_runtimes.all(func(runtime): return not runtime.view.selected), "Empty field clears data selection, panel and highlight")
	var resident = scene.resident_runtimes[1]
	scene.resident_selection.select(resident.data)
	var spy = ControlSpy.new()
	card.bind_control(spy)
	spy.notify_home() # Exercise the management notification contract of the UI test double.
	card.profession_choice.item_selected.emit(card.profession_choice.get_item_index(Profession.PORTER))
	check(spy.calls == [[resident.data.id, Profession.PORTER]] and resident.data.profession == Profession.NONE, "UI delegates ID/profession to simulation API; no direct mutation")
	card.bind_control(scene.player_control)
	for profession in [Profession.PORTER, Profession.GATHERER, Profession.NONE]:
		card.profession_choice.item_selected.emit(card.profession_choice.get_item_index(profession))
		check(resident.data.profession == profession and profession_text(profession) in card.profession_label.text, "Panel changes profession and reads live result")
		check(resident.data.work_location_id == ({Profession.PORTER: scene.warehouse_data.id, Profession.GATHERER: scene.gatherer_hut_data.id}.get(profession, &"")), "Simulation API resolves profession workplace ID")
	check(not scene.player_control.assign_profession("missing", Profession.PORTER), "Unknown ID cannot mutate anyone")
	check(not scene._work_available(resident), "NONE has no professional work")
	scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
	check(scene._work_available(resident), "New PORTER can request haul work independent of Stepan")
	scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
	check(scene._work_available(resident), "New GATHERER can request gatherer work")
	var order = Assignment.new(&"test_order", resident.data.id)
	check(order.state == Assignment.State.QUEUED and order.target == null and order.type == &"", "ResidentAssignment is inert persistent-task data, no invented concrete types")
	check(Assignment.State.size() == 5 and order.resident_id == resident.data.id, "Order lifecycle foundation is separate from profession")
	scene.free()
	# Each personal committed action survives management, including its movement stage.
	for action in ["eat", "leisure", "wander", "social", "sleep", "personal_route"]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[1]
		match action:
			"eat":
				scene.kitchen_data.resources.add(FOOD, 1)
				resident.data.hunger = 75
				resident.needs.try_eat(5000)
				resident.view._process(20)
			"leisure": resident.social.try_leisure(5000)
			"wander":
				resident.wander.target_provider = scene._wander_target_2d.bind(resident.data.id)
				resident.wander.try_wander(500)
			"social": scene.social_world.arrive(resident.data.id, {"target_id": scene.residents[3].id, "group_id": 0})
			"sleep":
				resident.schedule._on_phase_changed("Ночь")
				resident.view._process(20)
			"personal_route": resident.schedule.request_manual_move(Vector2(100, 200))
		var previous = resident.intents.current_intent
		var activity: int = resident.data.activity
		var position: Vector2 = resident.view.global_position
		var decisions: int = resident.decision.decision_count
		scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
		check(resident.intents.current_intent == previous and resident.data.activity == activity and resident.view.global_position == position and resident.decision.decision_count == decisions, "Profession is not forced interrupt/teleport/re-decision during " + action)
		scene.free()
	# Already-started safe work contributes until its original 60-minute boundary.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	work_api(scene, resident)
	scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
	scene.game_time.debug_next_phase()
	resident.view._process(20)
	scene.game_time.debug_skip_minutes(45)
	check(scene.gatherer_hut_data.production_progress == 15 and resident.data.activity == Activity.WORKING, "Old gatherer cycle is physically working at minute 45")
	var before: int = resident.decision.decision_count
	scene.player_control.assign_profession(resident.data.id, Profession.NONE)
	check(resident.data.profession == Profession.NONE and resident.data.activity == Activity.WORKING and resident.decision.decision_count == before, "Persistent assignment changes immediately, committed cycle remains")
	scene.game_time.debug_skip_minutes(15)
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 2 and scene.gatherer_hut_data.production_progress == 0, "Committed old cycle finishes its contribution without resetting building progress")
	check(not resident.decision._work_cycle_active and resident.data.activity == Activity.IDLE and not resident.decision.collect_actions(scene._work_available(resident)).any(func(row): return row.id == "WORK"), "No new gatherer cycle after profession removed")
	print("WORK proof: 45 min -> assign NONE -> old cycle finishes 60 min -> no old work")
	scene.free()
	# A personal action's next boundary uses the new work assignment.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	work_api(scene, resident)
	scene.game_time.debug_next_phase()
	resident.social.try_leisure(5000)
	scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
	scene.game_time.debug_skip_minutes(30)
	check(resident.intents.current_intent.reason_id == &"day_work", "New profession is used on next normal action completion")
	resident.view._process(20)
	check(resident.data.activity == Activity.WORKING, "New gatherer reaches workplace normally")
	scene.free()
	# A stale professional route can finish moving, but cannot begin an invalid cycle.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	work_api(scene, resident)
	scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
	scene.game_time.debug_next_phase()
	var old_route = resident.intents.current_intent
	scene.player_control.assign_profession(resident.data.id, Profession.NONE)
	check(resident.intents.current_intent == old_route, "Old work route is not forcibly replaced")
	resident.view._process(20)
	check(not resident.decision._work_cycle_active and resident.data.activity == Activity.IDLE, "Arrival after assignment change does not start invalid old work")
	scene.free()
	# Both haul stages complete safely, then eligibility uses the new assignment.
	for picked_up in [false, true]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		work_api(scene, resident)
		scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
		scene.game_time.debug_next_phase()
		var job = scene.logistics.current_job
		if picked_up: resident.view._process(20)
		var haul = resident.intents.current_intent
		scene.player_control.assign_profession(resident.data.id, Profession.NONE)
		check(resident.intents.current_intent == haul and job.is_active(), "Profession change preserves already-started haul stage")
		if not picked_up: resident.view._process(20)
		resident.view._process(20)
		check(job.state == Job.State.COMPLETED and resident.data.inventory.amount == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 1, "Old porter delivers safely after role removal")
		check(scene.logistics.jobs.is_empty() and job.state == Job.State.COMPLETED and not scene._work_available(resident), "No next haul from old profession")
		scene.free()
	# Executor ownership follows an actual requester, not a startup singleton.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	work_api(scene, resident)
	scene.player_control.assign_profession(scene.residents[0].id, Profession.NONE)
	scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
	scene.game_time.debug_next_phase()
	var claimed = scene.logistics.current_job
	check(claimed.assigned_resident_id == resident.data.id and claimed.state == Job.State.GOING_TO_SOURCE, "Anna claims the same logistics API as Stepan")
	resident.view._process(20)
	scene.player_control.assign_profession(resident.data.id, Profession.NONE)
	resident.view._process(20)
	check(claimed.state == Job.State.COMPLETED and scene.kitchen_data.resources.get_amount(FOOD) == 1, "Newly assigned porter really delivers, not just UI eligibility")
	print("Haul proof: new PORTER Anna -> pickup -> assign NONE -> deliver -> no next claim")
	scene.free()
	# Transition to another profession starts its work only at the safe boundary.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[2]
	work_api(scene, resident)
	scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
	scene.game_time.debug_next_phase()
	resident.view._process(20)
	scene.game_time.debug_skip_minutes(45)
	scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
	scene.game_time.debug_skip_minutes(15)
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 2 and not resident.decision._work_cycle_active and resident.intents.current_intent.reason_id == &"haul_source", "GATHERER -> PORTER finishes old cycle, then claims new profession work")
	scene.free()
	# A newly assigned executor retains the correct forced-drop owner.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	work_api(scene, resident)
	scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
	scene.game_time.debug_next_phase()
	resident.view._process(20)
	var loaded_job = scene.logistics.current_job
	var drop_position: Vector2 = resident.view.global_position
	resident.data.fatigue = 100
	check(loaded_job.state == Job.State.CANCELLED and resident.data.inventory.amount == 0 and scene.ground_resources.drops.size() == 1, "Critical fatigue cancels newly assigned porter's loaded haul and drops cargo")
	check(scene.ground_resources.drops[0].world_position == drop_position and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0, "Ground cargo uses actual executor position, never Stepan's")
	scene.free()
	# Management never bypasses critical/forced survival.
	for critical in ["hunger", "fatigue"]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[1]
		scene.kitchen_data.resources.add(FOOD, 1)
		resident.social.try_leisure(5000)
		scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
		if critical == "hunger": resident.data.hunger = 100
		else: resident.data.fatigue = 100
		check(resident.intents.forced_priority > 0 and resident.intents.current_intent.reason_id != &"leisure", "Critical survival still overrides committed action after profession change")
		scene.free()
	# Startup in a work phase must not leave a PORTER in fake warehouse work.
	scene = load("res://scenes/main.tscn").instantiate()
	scene.get_node("GameTime").total_minutes = 450
	root.add_child(scene)
	scene.game_time.set_process(false)
	check(scene.resident_runtimes[0].intents.current_intent.reason_id == &"haul_source" and scene.logistics.current_job.assigned_resident_id == scene.residents[0].id, "Daytime startup uses actual profession work source")
	scene.free()
	# WANDER start/end INFO belongs to the action, including natural completion.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	resident.wander.target_provider = scene._wander_target_2d.bind(resident.data.id)
	listen(scene)
	scene.game_logger.debug_enabled = true
	resident.wander.try_wander(500)
	resident.view._process(20)
	resident.wander.target_provider = Callable()
	scene.game_time.debug_skip_minutes(10)
	check(lines.count("[06:00][AI] Анна: начинает прогулку") == 1 and lines.count("[06:10][AI] Анна: прогулка завершена") == 1, "Exactly one WANDER INFO start/end at game timestamps")
	check(lines.any(func(line): return "[AI][DEBUG] Анна WANDER target=" in line), "Coordinates only in WANDER DEBUG")
	for line in lines:
		if "прогул" in line: print(line)
	scene.free()
	print("Player control checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func profession_text(profession: int) -> String:
	return preload("res://scripts/resident_profession.gd").display_name(profession)
