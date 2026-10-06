extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Utility = preload("res://scripts/action_utility.gd")
const Selector = preload("res://scripts/utility_selector.gd")
const Seed = preload("res://tests/utility_test_seed.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Building = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd").Type
const Location = preload("res://scripts/world_location.gd")
const Option = preload("res://scripts/interaction_option.gd")
class ControlSpy extends RefCounted:
	var resident: RefCounted
	var received: Array = []
	func get_resident(_id: String): return resident
	func add_assignment(id: String, assignment: RefCounted) -> bool:
		received.append([id, assignment])
		return true

const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var checks := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func add(scene: Node, runtime: Node, id: StringName, target: StringName = &"communal_kitchen_01"):
	var assignment := Assignment.new(id, runtime.data.id, Assignment.EAT_AT_TARGET, target)
	check(scene.player_control.add_assignment(runtime.data.id, assignment), "Simulation API adds assignment")
	return assignment
func choose(runtime: Node, assignment: Assignment) -> void:
	var actions: Array = runtime.decision.collect_actions(false)
	runtime.decision.rng.seed = Seed.for_action(actions, "ASSIGNMENT:%s" % assignment.id)
	runtime.decision.request_decision("test")
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	var options: Array = scene.interactions.get_interactions([actor.data.id], scene.kitchen_data.id)
	check(options[1].enabled and options[1].label == "Поесть здесь" and options[1].interaction_kind == Option.Kind.RESIDENT_ASSIGNMENT, "Kitchen offers enabled assignment even without FOOD")
	actor.social.try_leisure(5000)
	var committed = actor.intents.current_intent
	var count: int = actor.decision.decision_count
	check(scene.interactions.execute([actor.data.id], options[1]), "Context action calls player assignment API")
	var first = actor.data.assignments[0]
	check(first.type == Assignment.EAT_AT_TARGET and first.target == scene.kitchen_data.id and first.state == Assignment.State.QUEUED, "Context creates queued exact-target EAT_AT_TARGET")
	check(actor.intents.current_intent == committed and actor.data.activity == Activity.RELAXING and actor.decision.decision_count == count, "Enqueue never interrupts committed action or creates immediate decision")
	var second = add(scene, actor, &"second")
	check(actor.data.assignments == [first, second] and scene.residents[0].assignments.is_empty(), "Per-resident list has chronological append order, no shared storage")
	actor.data.hunger = 80
	check(actor.assignments.collect_actions().is_empty() and first.state == Assignment.State.QUEUED, "No FOOD: unavailable assignments persist QUEUED")
	scene.kitchen_data.resources.add(FOOD, 3)
	check(actor.intents.current_intent == committed and actor.decision.decision_count == count, "FOOD event never interrupts current committed action")
	var rows: Array = actor.assignments.collect_actions()
	check(rows.size() == 2 and is_equal_approx(rows[0].priority, Utility.eat(80) + Balance.ASSIGNMENT_BONUS) and rows[0].priority == rows[1].priority, "Both assignments get nonlinear utility plus identical bonus")
	check(first.importance == Assignment.Importance.NORMAL and Assignment.Importance.size() == 3, "Future importance values exist, NORMAL default")
	first.importance = Assignment.Importance.HIGH
	second.importance = Assignment.Importance.LOW
	actor.data.assignments.reverse()
	check(actor.assignments.collect_actions() == rows, "Importance and list reordering cannot alter utility or stable candidate pool")
	actor.data.assignments.reverse()
	check(actor.data.assignments == [first, second], "Candidate collection never changes chronological history")
	var pool: Array = actor.decision.collect_actions(true)
	check(pool.any(func(row): return row.id == "ASSIGNMENT:%s" % first.id), "Assignment joins normal action pool, not hard scheduler")
	var report: Dictionary = Selector.evaluate(pool)
	var rng := RandomNumberGenerator.new()
	rng.seed = Seed.for_action(pool, "WORK")
	check(Selector.pick(report, rng).id == "WORK", "Higher-utility assignment can lose weighted random to WORK")
	rng.seed = Seed.for_action(pool, "ASSIGNMENT:%s" % first.id)
	check(Selector.pick(report, rng).id == "ASSIGNMENT:%s" % first.id, "Seeded existing UtilitySelector can select assignment")
	check(scene.player_control.cancel_assignment(actor.data.id, second.id) and second.state == Assignment.State.CANCELLED, "Cancel API makes queued assignment terminal")
	check(actor.assignments.collect_actions().size() == 1 and not scene.player_control.cancel_assignment(actor.data.id, &"missing"), "Cancelled assignment excluded; unknown ID rejected")
	scene.free()
	# Normal selection -> shared executor -> progressive benefit -> complete before next decision.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"meal")
	choose(actor, first)
	check(first.state == Assignment.State.ACTIVE and actor.assignments.active_assignment == first, "Selected assignment becomes ACTIVE")
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 1 and actor.intents.current_intent.target_position == scene.world_locations.get_position(first.target), "Reserve and move to exact assigned kitchen")
	check(actor.needs._active_intent == actor.intents.current_intent, "Assignment reuses existing Needs executor")
	actor.view._process(20)
	check(actor.data.activity == Activity.EATING and scene.kitchen_data.resources.get_amount(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Arrival consumes reserved portion once through existing meal logic")
	scene.game_time.minute_changed.disconnect(actor.needs._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.needs._on_minute_changed)
	scene.game_time.debug_skip_minutes(29)
	check(first.state == Assignment.State.ACTIVE and actor.data.hunger == 22, "Same progressive hunger decrease, no early completion")
	count = actor.decision.decision_count
	scene.game_time.debug_skip_minutes(1)
	check(first.state == Assignment.State.COMPLETED and actor.assignments.active_assignment == null and actor.data.hunger == 20, "Successful 30-minute meal completes assignment")
	check(actor.decision.decision_count == count + 1 and not actor.decision.collect_actions(false).any(func(row): return row.id == "ASSIGNMENT:meal"), "One normal decision after completion, terminal assignment never selected again")
	check(lines.any(func(line): return "добавлено поручение" in line) and lines.any(func(line): return "начал поручение" in line) and lines.any(func(line): return "поручение выполнено" in line), "Game-time PLAYER/ASSIGNMENT lifecycle logs")
	for line in lines:
		if "[ASSIGNMENT]" in line or "[PLAYER]" in line: print(line)
	scene.free()
	# Player interruption before and after consumption: keep request, never refund consumed food.
	for eating in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[1]
		scene.kitchen_data.resources.add(FOOD, 1)
		actor.data.hunger = 80
		first = add(scene, actor, &"interrupted")
		choose(actor, first)
		if eating: actor.view._process(20)
		scene.player_control.move_to(actor.data.id, Vector2(-500, 300))
		check(first.state == Assignment.State.QUEUED and actor.assignments.active_assignment == null, "PlayerCommand requeues assignment, never marks fulfilled")
		check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_amount(FOOD) == (0 if eating else 1), "Interrupt releases reservation; consumed FOOD not refunded")
		check(actor.intents.player_controlled and actor.needs._active_intent == null, "Shared forced pipeline clears meal execution and player wins")
		check(actor.assignments.collect_actions().size() == (0 if eating else 1), "Queued assignment availability reflects remaining target food")
		if not eating:
			actor.decision.rng.seed = Seed.for_action(actor.decision.collect_actions(false), "ASSIGNMENT:interrupted")
			actor.view._process(20)
			check(first.state == Assignment.State.ACTIVE, "After command completion persistent assignment can be chosen again")
		else:
			check(scene.player_control.cancel_assignment(actor.data.id, first.id), "Queued interrupted request can be manually cancelled")
		scene.free()
	# Event-driven restoration: one owner creates one decision, no polling retries.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	actor.data.hunger = 80
	first = add(scene, actor, &"waiting")
	for iteration in range(3): actor.decision.request_decision("no_food")
	check(first.state == Assignment.State.QUEUED and actor.needs.food_search_count == 1, "No FOOD does not produce repeated eat searches without world change")
	count = actor.decision.decision_count
	scene.kitchen_data.resources.add(FOOD, 1)
	check(actor.decision.decision_count == count + 1 and actor.intents.has_current_action(), "Available FOOD triggers exactly one existing event-driven decision for idle actor")
	scene.free()
	# Two kitchens: assigned target is never silently substituted with available other kitchen.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	var kitchen = Building.new(&"other_kitchen", "Другая кухня", BuildingType.FOOD)
	kitchen.resources.set_capacity(FOOD, 20)
	var marker := Node2D.new()
	scene.add_child(marker)
	marker.position = Vector2(-260, 150)
	scene.world_locations.register(Location.new(kitchen.id, kitchen.display_name), marker)
	scene.buildings.append(kitchen)
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"exact_target", kitchen.id)
	check(actor.assignments.collect_actions().is_empty() and first.state == Assignment.State.QUEUED, "Food in another kitchen cannot satisfy target assignment")
	kitchen.resources.add(FOOD, 1)
	choose(actor, first)
	check(actor.intents.current_intent.target_position == marker.global_position and kitchen.resources.get_reserved_out(FOOD) == 1 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Targeted execution reserves only selected kitchen")
	scene.world_locations._views.erase(kitchen.id)
	actor.needs._on_minute_changed(scene.game_time.total_minutes + 1)
	check(first.state == Assignment.State.QUEUED and kitchen.resources.get_reserved_out(FOOD) == 0, "Temporarily moved/unreachable target requeues and frees reservation")
	# Prevent immediate ordinary action retry while removing the target permanently.
	scene.player_control.move_to(actor.data.id, Vector2(-500, 300))
	scene.buildings.erase(kitchen)
	actor.assignments.collect_actions()
	check(first.state == Assignment.State.CANCELLED, "Permanently removed queued target cancels request")
	scene.free()
	# Permanent removal during ACTIVE route also cleans ownership/reservation.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"removed_active")
	choose(actor, first)
	scene.buildings.erase(scene.kitchen_data)
	actor.needs._on_minute_changed(scene.game_time.total_minutes + 1)
	check(first.state == Assignment.State.CANCELLED and actor.assignments.active_assignment == null and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Removed ACTIVE target cancels assignment and releases food")
	scene.free()
	# Manual cancellation of ACTIVE eating stops shared executor, no food refund.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"cancel_active")
	choose(actor, first)
	actor.view._process(20)
	check(scene.player_control.cancel_assignment(actor.data.id, first.id) and first.state == Assignment.State.CANCELLED and actor.needs._active_intent == null and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Cancel ACTIVE API uses meal cleanup and never refunds consumed FOOD")
	scene.free()
	# Real menu UI delegates the option to simulation API, never mutates list itself.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	var spy := ControlSpy.new()
	spy.resident = actor.data
	scene.interactions.control = spy
	scene.interaction_menu.open_for([actor.data.id], scene.kitchen_data.id, Vector2(450, 120))
	scene.interaction_menu._column.get_child(1).pressed.emit()
	check(spy.received.size() == 1 and spy.received[0][0] == actor.data.id and spy.received[0][1].type == Assignment.EAT_AT_TARGET and actor.data.assignments.is_empty(), "Menu sends add_assignment API, never mutates resident list")
	check(not scene.interaction_menu.visible, "Menu closes after choosing assignment")
	scene.interactions.control = scene.player_control
	var wrong_owner := Assignment.new(&"wrong", scene.residents[0].id, Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	check(not scene.player_control.add_assignment(actor.data.id, wrong_owner), "API rejects mismatched owner")
	first = add(scene, actor, &"duplicate")
	check(not scene.player_control.add_assignment(actor.data.id, first), "API rejects duplicate assignment ID")
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 29
	check(actor.assignments.collect_actions().is_empty(), "HUNGER 29 excludes assignment, same EAT eligibility")
	actor.data.hunger = 30
	check(actor.assignments.collect_actions()[0].priority == Balance.ASSIGNMENT_BONUS, "HUNGER 30 uses zero nonlinear base plus bonus")
	scene.free()
	# Add while WORKING: wait for a real cycle boundary, building progress retained.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[2]
	actor.decision.work_available = scene._work_available.bind(actor)
	actor.decision.work_request = scene._request_work.bind(actor)
	actor.schedule.work_decision = actor.decision.request_decision
	scene.player_control.assign_workplace(actor.data.id, scene.gatherer_hut_data.id)
	scene.game_time.debug_next_phase()
	actor.view._process(20)
	check(actor.data.activity == Activity.WORKING, "Fixture has committed gatherer cycle")
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"after_cycle")
	count = actor.decision.decision_count
	actor.decision.rng.seed = Seed.for_action(actor.decision.collect_actions(true), "ASSIGNMENT:after_cycle")
	scene.game_time.debug_skip_minutes(59)
	check(actor.data.activity == Activity.WORKING and first.state == Assignment.State.QUEUED and actor.decision.decision_count == count, "Enqueued assignment waits through current 60-minute committed work")
	scene.gatherer_hut_data.production_progress = 17 # Nonzero building-owned partial product.
	var progress: int = scene.gatherer_hut_data.production_progress
	scene.game_time.debug_skip_minutes(1)
	check(first.state == Assignment.State.ACTIVE and actor.decision.decision_count == count + 1, "Next work-cycle decision selects assignment through UtilitySelector")
	check(scene.gatherer_hut_data.production_progress == progress + 1, "Last worked minute adds contribution; taking assignment never resets building progress")
	scene.free()
	# Existing critical bypass stays unchanged; interrupted persistent request requeues.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	first = add(scene, actor, &"critical_interrupt")
	choose(actor, first)
	actor.data.fatigue = 100
	check(first.state == Assignment.State.QUEUED and actor.data.activity == Activity.SLEEPING and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Existing critical fatigue bypass requeues assignment and releases reservation")
	scene.free()
	# Bonus must not become a new mechanical priority above the existing night source.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 90
	first = add(scene, actor, &"night_route")
	choose(actor, first)
	check(actor.intents.current_intent.priority == roundi(Utility.eat(90)), "Assignment bonus affects selection only, not eat intent priority")
	actor.schedule._on_phase_changed("Ночь")
	check(first.state == Assignment.State.QUEUED and actor.intents.current_intent.reason_id == &"night_home" and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Existing night route replacement is preserved without new assignment hierarchy")
	scene.free()
	print("Resident assignments: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
