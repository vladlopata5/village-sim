extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Building = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd").Type
const Location = preload("res://scripts/world_location.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var checks := 0
var interrupts := 0
var starts := 0
var resource_changes := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func watch(scene: Node, actor: Node) -> void:
	interrupts = 0
	starts = 0
	resource_changes = 0
	lines.clear()
	actor.intents.forced_interrupt.connect(func(_intent): interrupts += 1)
	actor.needs.eat_started.connect(func(_intent): starts += 1)
	scene.kitchen_data.resources.availability_changed.connect(func(_resource, _amount): resource_changes += 1)
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
func assignment(scene: Node, actor: Node, id: StringName, target: StringName):
	var task := Assignment.new(id, actor.data.id, Assignment.EAT_AT_TARGET, target)
	check(scene.player_control.add_assignment(actor.data.id, task), "Enqueue exact-target assignment")
	check(actor.assignments.start(id), "Start through shared meal executor")
	return task
func second_kitchen(scene: Node):
	var kitchen := Building.new(&"kitchen_a", "Кухня A", BuildingType.FOOD)
	kitchen.resources.set_capacity(FOOD, 20)
	var marker := Node2D.new()
	scene.add_child(marker)
	marker.position = Vector2(-300, 200)
	scene.world_locations.register(Location.new(kitchen.id, kitchen.display_name), marker)
	scene.buildings.append(kitchen)
	return kitchen
func dynamics(scene: Node, actor: Node) -> void:
	scene.game_time.minute_changed.disconnect(actor.needs._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	scene.game_time.minute_changed.connect(actor.needs._on_minute_changed)
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	var task = assignment(scene, actor, &"same", scene.kitchen_data.id)
	var duplicate := Assignment.new(&"duplicate", actor.data.id, Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	scene.player_control.add_assignment(actor.data.id, duplicate)
	var original = actor.intents.current_intent
	var pending := Intent.new(Intent.Type.MOVE_TO, &"night_home", Vector2.ONE, 10000)
	# Pending belongs to the same meal and must survive merge.
	original.interruptible = false
	actor.intents.submit(pending)
	original.interruptible = true
	watch(scene, actor)
	actor.data.hunger = 100
	check(actor.intents.current_intent == original and interrupts == 0 and starts == 0, "Same concrete kitchen merges without forced signal or new intent/flow")
	check(task.state == Assignment.State.ACTIVE and actor.assignments.active_assignment == task, "Assignment stays ACTIVE")
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 1 and scene.kitchen_data.resources.get_amount(FOOD) == 1 and resource_changes == 0, "Own reservation is feasible even when available FOOD=0; no reserve/release mutation")
	check(actor.intents.pending_intent == pending and actor.intents.forced_priority == 200, "Keep pending and existing critical protection, no reactivation")
	check(duplicate.state == Assignment.State.QUEUED and actor.data.assignments == [task, duplicate], "Duplicate assignment and chronological list unchanged")
	for iteration in range(4): actor.decision.check_critical()
	check(lines.filter(func(line): return "critical hunger совпал" in line).size() == 1, "Merge log once at critical transition, not each check/tick")
	for line in lines:
		if "critical hunger совпал" in line: print(line)
	actor.view._process(20)
	check(actor.data.activity == Activity.EATING and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Continue existing route and consume exactly its original FOOD")
	dynamics(scene, actor)
	scene.game_time.debug_skip_minutes(30)
	check(task.state == Assignment.State.COMPLETED and actor.data.hunger == 40 and scene.kitchen_data.resources.get_amount(FOOD) == 0, "One 30-minute eating flow fulfills assignment and critical need")
	scene.free()
	# Concrete selection retains first-feasible policy, not a sticky assignment target.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	var kitchen_a = second_kitchen(scene)
	scene.kitchen_data.resources.add(FOOD, 1) # B is first in existing registry policy.
	kitchen_a.resources.add(FOOD, 1)
	actor.data.hunger = 80
	task = assignment(scene, actor, &"different", kitchen_a.id)
	original = actor.intents.current_intent
	watch(scene, actor)
	actor.data.hunger = 100
	check(task.state == Assignment.State.QUEUED and actor.assignments.active_assignment == null, "Different critical target interrupts assignment and requeues")
	check(kitchen_a.resources.get_reserved_out(FOOD) == 0 and kitchen_a.resources.get_amount(FOOD) == 1, "Old A reservation released through existing meal cleanup")
	check(actor.intents.current_intent != original and actor.needs._food_building == scene.kitchen_data and actor.intents.current_intent.target_position == scene.world_locations.get_position(scene.kitchen_data.id), "Ordinary critical EAT starts to selected B, no assignment retargeting")
	check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 1 and interrupts == 1 and starts == 1 and actor.intents.forced_priority == 200, "One new critical flow/reservation and one forced interrupt")
	check(actor.data.assignments == [task] and task.target == kitchen_a.id, "Original assignment persists for A")
	actor.view._process(20)
	dynamics(scene, actor)
	scene.game_time.debug_skip_minutes(30)
	check(task.state != Assignment.State.COMPLETED and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Eating at B does not fulfill assignment A")
	scene.free()
	# Already eating: ignore alternatives and retain timer, resource and execution identity.
	for assigned in [true, false]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[1]
		kitchen_a = second_kitchen(scene)
		scene.kitchen_data.resources.add(FOOD, 2)
		kitchen_a.resources.add(FOOD, 1)
		actor.data.hunger = 80
		if assigned: task = assignment(scene, actor, &"already_eating", kitchen_a.id)
		else: actor.needs.try_eat_at(kitchen_a.id, 5000)
		actor.view._process(20)
		scene.game_time.debug_skip_minutes(5)
		original = actor.intents.current_intent
		var remaining: int = actor.needs._minutes_left
		watch(scene, actor)
		actor.data.hunger = 100
		check(actor.data.activity == Activity.EATING and actor.intents.current_intent == original and actor.needs._food_building == kitchen_a, "Already paid EATING never switches to another available kitchen")
		check(interrupts == 0 and starts == 0 and actor.needs._minutes_left == remaining and kitchen_a.resources.get_amount(FOOD) == 0 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "No duplicated intent, timer, reservation or consumption while eating")
		if assigned: check(task.state == Assignment.State.ACTIVE, "Already eating assignment stays ACTIVE")
		dynamics(scene, actor)
		scene.game_time.debug_skip_minutes(remaining)
		if assigned: check(task.state == Assignment.State.COMPLETED, "Merged eating assignment completes on original deadline")
		check(scene.kitchen_data.resources.get_amount(FOOD) == 2, "Alternative kitchen FOOD untouched")
		scene.free()
	# Consumption emits resource signals synchronously before Activity becomes EATING.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	task = assignment(scene, actor, &"consumption_signal", scene.kitchen_data.id)
	original = actor.intents.current_intent
	watch(scene, actor)
	var data = actor.data
	scene.kitchen_data.resources.changed.connect(func(_resource, _amount): data.hunger = 100)
	actor.view._process(20)
	check(actor.intents.current_intent == original and actor.data.activity == Activity.EATING and task.state == Assignment.State.ACTIVE, "Critical event inside consumption keeps the same meal despite transient MOVING activity")
	check(interrupts == 0 and starts == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 0 and actor.needs._minutes_left == 30, "Consumption signal cannot duplicate food or timer")
	scene.free()
	# Autonomous route also merges if the concrete solution matches its reservation.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	actor.needs.try_eat(5000)
	original = actor.intents.current_intent
	watch(scene, actor)
	actor.data.hunger = 100
	check(original == actor.intents.current_intent and interrupts == 0 and starts == 0 and scene.kitchen_data.resources.get_reserved_out(FOOD) == 1, "Autonomous route same target reuses reserved eating flow")
	scene.free()
	# Player absolute priority still interrupts merged movement and merged paid eating.
	for eating in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[1]
		scene.kitchen_data.resources.add(FOOD, 1)
		actor.data.hunger = 80
		task = assignment(scene, actor, &"player_interrupt", scene.kitchen_data.id)
		if eating: actor.view._process(20)
		actor.data.hunger = 100
		scene.player_control.move_to(actor.data.id, Vector2(-500, 300))
		check(task.state == Assignment.State.QUEUED and actor.intents.player_controlled and actor.intents.current_intent.reason_id == &"player_move", "PlayerCommand still interrupts merged assignment")
		check(scene.kitchen_data.resources.get_reserved_out(FOOD) == 0 and scene.kitchen_data.resources.get_amount(FOOD) == (0 if eating else 1), "Player cleanup releases original promise, never refunds consumed FOOD")
		scene.free()
	# Non-eat action unchanged. No other assignment types invented for this test.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.social.try_leisure(5000)
	watch(scene, actor)
	actor.data.hunger = 100
	check(interrupts == 1 and actor.intents.current_intent.reason_id == &"eat" and actor.intents.forced_priority == 200 and actor.social._active == null, "Non-eat committed action follows existing forced cleanup")
	check(not actor.needs.is_current_eat_compatible(null), "Absent target cannot be compatible")
	scene.free()
	print("Critical EAT compatibility: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
