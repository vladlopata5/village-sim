extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Command = preload("res://scripts/player_command.gd")
const Option = preload("res://scripts/interaction_option.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Job = preload("res://scripts/haul_job.gd").State
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var lines: Array[String] = []
class ControlSpy extends RefCounted:
	var calls: Array = []
	var data: RefCounted
	func get_resident(_id: String): return data
	func assign_workplace(id: String, location: StringName) -> bool:
		calls.append([id, location])
		return true
	func move_to(id: String, position: Vector2) -> bool:
		calls.append([id, position])
		return true
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
func listen(scene: Node) -> void:
	lines.clear()
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
func work_api(scene: Node, runtime: Node) -> void:
	runtime.decision.work_available = scene._work_available.bind(runtime)
	runtime.decision.work_request = scene._request_work.bind(runtime)
	runtime.schedule.work_decision = runtime.decision.request_decision
func _run() -> void:
	var scene = Setup.make_scene(self)
	await process_frame
	await process_frame
	var resident = scene.resident_runtimes[1]
	var destination := Vector2(-350, 150)
	var screen: Vector2 = scene.field.get_global_transform_with_canvas() * destination
	click(screen)
	check(scene.resident_runtimes.all(func(runtime): return runtime.commands.active_command == null), "RMB without selection does nothing")
	scene.resident_selection.select(resident.data)
	listen(scene)
	click(screen)
	var first = resident.commands.active_command
	check(first != null and first.type == Command.Type.MOVE_TO and first.target == destination and resident.intents.player_controlled, "RMB on ground creates active MOVE_TO in simulation controller")
	check(scene.resident_selection.selected_resident == resident.data, "RMB preserves selection")
	var second_position := Vector2(-320, 160)
	click(scene.field.get_global_transform_with_canvas() * second_position)
	var second = resident.commands.active_command
	check(first.state == Command.State.CANCELLED and second != first and resident.view.target_position == second_position, "New command cancels previous and immediately redirects, no queue")
	check(not resident.intents.submit(Intent.new(Intent.Type.MOVE_TO, &"ai", Vector2.ZERO, 99999999)) and not resident.intents.force_set_intent(Intent.new(), 99999999), "Player ownership rejects ordinary and any numeric forced AI priority")
	paused = true
	var old_position: Vector2 = resident.view.global_position
	resident.view._process(20)
	check(resident.view.global_position == old_position and resident.commands.active_command == second, "Pause preserves active command and stops movement")
	paused = false
	var count: int = resident.decision.decision_count
	resident.view._process(20)
	check(second.state == Command.State.COMPLETED and resident.commands.active_command == null and not resident.intents.player_controlled, "Arrival clears player ownership and completes command")
	check(resident.decision.decision_count == count + 1, "Command completion creates exactly one normal decision")
	resident.view.intent_completed.emit(resident.intents.current_intent)
	check(resident.decision.decision_count == count + 1, "Stale/empty arrival cannot duplicate normal decision")
	check(lines.any(func(line): return "[PLAYER]" in line and "приказ MOVE_TO →" in line) and lines.any(func(line): return "отменён — заменён новым приказом" in line) and lines.any(func(line): return "приказ MOVE_TO выполнен" in line), "PLAYER INFO command/replace/completion with game clock")
	for line in lines:
		if "[PLAYER]" in line: print(line)
	scene.free()
	# All committed actions share cleanup, not bespoke manual logic.
	for action in ["wander", "relax", "talk", "sleep", "eat_reserved", "eating", "work"]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[2]
		match action:
			"wander":
				resident.wander.target_provider = scene._wander_target_2d.bind(resident.data.id)
				resident.wander.try_wander(500)
			"relax": resident.social.try_leisure(5000)
			"talk":
				var target = scene.resident_runtimes[1]
				scene.social_world.arrive(resident.data.id, {"target_id": target.data.id, "group_id": 0})
				var group = scene.social_world.group_of(resident.data.id)
				scene.social_world.arrive(scene.residents[3].id, {"target_id": target.data.id, "group_id": group.id})
			"sleep":
				scene.game_time.total_minutes = 1380
				resident.schedule._on_phase_changed("Ночь")
				resident.view._process(20)
			"eat_reserved", "eating":
				scene.kitchen_data.resources.add(FOOD, 1)
				resident.data.hunger = 75
				resident.needs.try_eat(5000)
				if action == "eating": resident.view._process(20)
			"work":
				work_api(scene, resident)
				scene.player_control.assign_profession(resident.data.id, Profession.GATHERER)
				scene.game_time.debug_next_phase()
				resident.view._process(20)
				scene.game_time.debug_skip_minutes(15)
		var progress: float = scene.gatherer_hut_data.production_progress
		check(scene.player_control.move_to(resident.data.id, Vector2(-500, 300)), "Player interrupt accepted for " + action)
		check(resident.data.activity == Activity.MOVING and resident.intents.current_intent.reason_id == &"player_move", "Activity becomes MOVING after interrupt " + action)
		match action:
			"wander": check(resident.wander._active == null and resident.wander._stay_ends_at == 0, "Wander action and target cleared")
			"relax": check(resident.social._active == null, "Relax stops")
			"talk":
				check(scene.social_world.group_of(resident.data.id) == null and scene.social_world.group_of(scene.residents[1].id).participants.size() == 2, "Leaving three-person conversation preserves other two participants")
			"sleep": check(resident.data.activity != Activity.SLEEPING, "Command wakes sleeping resident")
			"eat_reserved", "eating":
				check(resident.needs._active_intent == null and not resident.needs._meal_active and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Meal reservation released and meal action cleaned")
				check(scene.kitchen_data.resources.get_amount(FOOD) == (1 if action == "eat_reserved" else 0), "Consumed FOOD is never magically returned")
			"work":
				check(not resident.decision._work_cycle_active and scene.gatherer_hut_data.production_progress == progress, "Working cycle stops but building progress remains")
		scene.game_time.debug_skip_minutes(2)
		check(resident.commands.active_command != null and resident.intents.current_intent.reason_id == &"player_move", "Ordinary simulation does not steal command " + action)
		scene.free()
	# Same-point commands arrive synchronously: cleanup must precede the new decision.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	resident.data.hunger = 75
	resident.needs.try_eat(5000)
	resident.view._process(20)
	count = resident.decision.decision_count
	scene.player_control.move_to(resident.data.id, resident.view.global_position)
	check(resident.commands.active_command == null and resident.needs._active_intent == null and not resident.needs._meal_active and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Same-point command completes after cleanup without refunding consumed food")
	check(resident.decision.decision_count == count + 1 and not resident.intents.player_controlled, "Synchronous arrival produces one decision and releases player lock")
	scene.free()
	# Two-person group dissolution wakes the remaining participant correctly.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[0]
	scene.social_world.arrive(resident.data.id, {"target_id": scene.residents[1].id, "group_id": 0})
	scene.player_control.move_to(resident.data.id, Vector2(-500, 300))
	await process_frame
	check(scene.social_world.groups.is_empty() and scene.residents[1].activity != Activity.TALKING, "Player departure dissolves group below two and releases remaining actor")
	scene.free()
	# Critical AI can be replaced and cannot steal control back until arrival.
	for critical in ["hunger", "fatigue"]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		scene.kitchen_data.resources.add(FOOD, 2)
		if critical == "hunger": resident.data.hunger = 100
		else: resident.data.fatigue = 100
		check(resident.intents.forced_priority > 0, "Fixture starts forced " + critical)
		scene.player_control.move_to(resident.data.id, Vector2(-500, 300))
		var command = resident.commands.active_command
		scene.game_time.debug_skip_minutes(5)
		resident.decision.check_critical()
		check(resident.commands.active_command == command and resident.intents.current_intent.reason_id == &"player_move", "ACTIVE player is above critical " + critical)
		resident.view._process(20)
		check(command.state == Command.State.COMPLETED and resident.commands.active_command == null and resident.intents.forced_priority > 0, "Critical AI resumes after command completes " + critical)
		scene.free()
	# Phase boundaries never cancel ACTIVE player ownership; they update future AI context.
	scene = Setup.make_scene(self)
	resident = scene.resident_runtimes[1]
	scene.player_control.move_to(resident.data.id, Vector2(-500, 300))
	var across_phases = resident.commands.active_command
	for phase in ["День", "Вечер", "Ночь", "Утро"]:
		scene.game_time.debug_next_phase()
		check(resident.schedule.get_phase() == phase and resident.commands.active_command == across_phases and resident.intents.current_intent.reason_id == &"player_move", "ACTIVE command survives mandatory phase " + phase)
	resident.view._process(20)
	check(across_phases.state == Command.State.COMPLETED and resident.commands.active_command == null, "Command completes normally after night and morning boundaries")
	scene.free()
	# Source/destination reservations and cargo use existing forced-interrupt cleanup.
	for picked_up in [false, true]:
		scene = Setup.make_scene(self)
		resident = scene.resident_runtimes[0]
		work_api(scene, resident)
		scene.player_control.assign_profession(resident.data.id, Profession.PORTER)
		scene.game_time.debug_next_phase()
		var job = scene.logistics.current_job
		if picked_up: resident.view._process(20)
		var position: Vector2 = resident.view.global_position
		scene.player_control.move_to(resident.data.id, Vector2(-500, 300))
		check(job.state == Job.CANCELLED and scene.warehouse_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_in(FOOD) == 0 and resident.data.inventory.amount == 0, "Player haul interrupt settles reservations and job")
		check(scene.ground_resources.drops.size() == (1 if picked_up else 0), "Only actually picked-up cargo becomes GroundResource")
		if picked_up: check(scene.ground_resources.drops[0].world_position == position and scene.ground_resources.drops[0].amount == 1, "Cargo physically drops at executor position")
		check(resident.intents.current_intent.reason_id == &"player_move", "Haul cleanup does not overwrite player command")
		scene.free()
	# Object RMB is only an interaction query; execution is delegated and revalidated.
	scene = Setup.make_scene(self)
	await process_frame
	await process_frame
	resident = scene.resident_runtimes[0]
	scene.resident_selection.select(resident.data)
	var kitchen = scene.get_node("World/CommunalKitchen")
	click(kitchen.get_global_transform_with_canvas() * Vector2.ZERO)
	check(scene.interaction_menu.visible and resident.commands.active_command == null, "RMB on building opens menu without MOVE_TO")
	check(scene.interaction_menu.options.map(func(option): return option.label) == ["Идти к", "Поесть здесь"] and scene.interaction_menu.options[1].enabled, "Kitchen menu: go to and queued eating assignment, no direct eating hack")
	check(scene.interaction_menu.options[0].interaction_kind == Option.Kind.PLAYER_COMMAND and scene.interaction_menu.options[1].interaction_kind == Option.Kind.RESIDENT_ASSIGNMENT, "Options distinguish command and assignment")
	var button = scene.interaction_menu._column.get_child(0)
	await process_frame
	click(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	check(resident.commands.active_command != null and resident.commands.active_command.target == kitchen.global_position and not scene.interaction_menu.visible, "Menu button delegates go-to object command through service")
	var active = resident.commands.active_command
	var camera = scene.get_node("World/Camera2D")
	camera.position = Vector2(200, -300) # Keep hut clear of the resident panel/HUD.
	camera.force_update_scroll()
	var hut = scene.get_node("World/GathererHut")
	click(hut.get_global_transform_with_canvas() * Vector2.ZERO)
	check(scene.interaction_menu.visible and resident.commands.active_command == active and scene.interaction_menu.options[1].label == "Устроиться на работу", "New RMB updates object menu without changing active command")
	var spy = ControlSpy.new()
	spy.data = resident.data
	var real = scene.interactions.control
	scene.interactions.control = spy
	scene.interaction_menu._column.get_child(1).pressed.emit()
	check(spy.calls == [[resident.data.id, scene.gatherer_hut_data.id]] and resident.data.profession == Profession.PORTER, "UI/service invoke management API, never mutate profession directly")
	scene.interactions.control = real
	var employment = scene.interactions.get_interactions([resident.data.id], scene.gatherer_hut_data.id)[1]
	check(scene.interactions.execute([resident.data.id], employment) and resident.data.profession == Profession.GATHERER and resident.data.work_location_id == scene.gatherer_hut_data.id, "Employment uses existing profession/workplace assignment")
	check(not scene.interactions.get_interactions([resident.data.id], scene.gatherer_hut_data.id)[1].enabled and resident.commands.active_command == active, "Already employed is disabled; management does not cancel command")
	camera.position = Vector2.ZERO
	camera.force_update_scroll()
	click(scene.resident_runtimes[1].view.get_global_transform_with_canvas() * Vector2.ZERO)
	check(scene.interaction_menu.visible and scene.interaction_menu.options.size() == 1, "Resident target has generic go-to option")
	var drop = scene.ground_resources.create_drop(FOOD, 1, Vector2(-200, 200))
	click(scene._ground_views[drop].get_global_transform_with_canvas() * Vector2.ZERO)
	check(scene.interaction_menu.visible and scene.interaction_menu.options.size() == 3 and resident.commands.active_command == active, "RMB on another object replaces an already-open menu without a command")
	scene.resident_selection.select(scene.residents[1])
	check(not scene.interaction_menu.visible, "Selection change closes menu")
	click(scene._ground_views[drop].get_global_transform_with_canvas() * Vector2.ZERO)
	check(scene.interaction_menu.visible and scene.interaction_menu.options.size() == 3 and not scene.interaction_menu.options[1].enabled and not scene.interaction_menu.options[2].enabled, "GroundResource has go-to and two disabled future assignments")
	var stale = scene.interaction_menu.options[0]
	drop.lifetime = 0
	scene.ground_resources._on_minute(scene.game_time.total_minutes)
	check(not scene.interactions.execute([resident.data.id], stale), "Expired ground target cannot execute stale menu option")
	click(Vector2(800, 650), MOUSE_BUTTON_LEFT)
	check(not scene.interaction_menu.visible, "Click outside closes menu")
	check(Assignment.new(&"future", resident.data.id).state == Assignment.State.QUEUED, "ResidentAssignment foundation is separate, no queue executor added")
	check(not scene.interactions.get_interactions([resident.data.id, scene.residents[2].id], scene.gatherer_hut_data.id)[1].enabled, "Future group API intersects availability, not union")
	scene.free()
	print("PlayerCommand/interaction checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
