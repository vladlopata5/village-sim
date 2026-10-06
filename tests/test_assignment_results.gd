extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Seed = preload("res://tests/utility_test_seed.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const Building = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd").Type
const Location = preload("res://scripts/world_location.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
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
func add(scene: Node, actor: Node, id: StringName, target: StringName = &"communal_kitchen_01"):
	var task := Assignment.new(id, actor.data.id, Assignment.EAT_AT_TARGET, target)
	check(scene.player_control.add_assignment(actor.data.id, task), "Add result instance")
	return task
func listen(scene: Node) -> void:
	lines.clear()
	scene.game_logger.line_logged.connect(func(line: String, _level: int): lines.append(line))
func other_kitchen(scene: Node):
	var kitchen := Building.new(&"kitchen_b", scene.kitchen_data.display_name, BuildingType.FOOD)
	kitchen.resources.set_capacity(FOOD, 20)
	var marker := Node2D.new()
	scene.add_child(marker)
	marker.position = Vector2(-300, 200)
	scene.world_locations.register(Location.new(kitchen.id, kitchen.display_name), marker)
	scene.buildings.append(kitchen)
	return kitchen
func _run() -> void:
	var scene: Node
	var actor: Node
	var task: Assignment
	# Autonomous and critical completions are the same concrete successful result.
	for critical in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[1]
		scene.kitchen_data.resources.add(FOOD, 1)
		actor.data.hunger = 80 if critical else 99
		task = add(scene, actor, &"independent")
		listen(scene)
		if critical: actor.data.hunger = 100
		else:
			# EAT can win the existing weighted selector despite the assignment bonus.
			actor.decision.rng.seed = Seed.for_action(actor.decision.collect_actions(false), "EAT")
			actor.decision.request_decision("independent_test")
			check(actor.needs._active_intent != null, "Actual normal AI selects autonomous EAT without assignment mechanism")
		check(actor.assignments.active_assignment == null and task.state == Assignment.State.QUEUED, "Reservation and movement never complete queued request")
		actor.view._process(20)
		check(actor.data.activity == Activity.EATING and task.state == Assignment.State.QUEUED, "Paid eating start is not successful completion")
		scene.game_time.debug_skip_minutes(29)
		check(task.state == Assignment.State.QUEUED, "Incomplete 29-minute meal does not satisfy assignment")
		scene.game_time.debug_skip_minutes(1)
		check(task.state == Assignment.State.COMPLETED and actor.data.assignments == [task], "Independent successful meal completes one queued same-target instance, keeps history")
		check(lines.filter(func(line): return "поручение выполнено независимо" in line).size() == 1, "One independent INFO, no duplicate regular completion log")
		if not critical:
			for line in lines:
				if "поручение выполнено независимо" in line: print(line)
		scene.free()
	# Different IDs, even with identical names and types, do not match.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	var kitchen_b = other_kitchen(scene)
	kitchen_b.resources.add(FOOD, 1)
	actor.data.hunger = 80
	task = add(scene, actor, &"only_a")
	check(actor.needs.try_eat_at(kitchen_b.id, 5000), "Independent action can eat at different concrete kitchen B")
	actor.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(task.state == Assignment.State.QUEUED, "Same name/type but different kitchen ID leaves A assignment queued")
	scene.free()
	# Oldest is insertion order, not lexical ID, importance or RNG.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	var tasks: Array = [add(scene, actor, &"z_oldest"), add(scene, actor, &"a_newer"), add(scene, actor, &"b_newest")]
	tasks[0].importance = Assignment.Importance.LOW
	tasks[1].importance = Assignment.Importance.HIGH
	actor.needs.try_eat(5000)
	actor.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(tasks[0].state == Assignment.State.COMPLETED and tasks[1].state == Assignment.State.QUEUED and tasks[2].state == Assignment.State.QUEUED, "One independent meal closes oldest duplicate only, not smallest ID/high importance")
	check(actor.data.assignments == tasks, "Duplicate instances retained in original chronological order")
	scene.free()
	# ACTIVE ownership takes precedence even when an older queued duplicate exists.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	var oldest = add(scene, actor, &"old_queued")
	var active = add(scene, actor, &"selected_active")
	check(actor.assignments.start(active.id), "Start newer ACTIVE assignment")
	listen(scene)
	actor.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(active.state == Assignment.State.COMPLETED and oldest.state == Assignment.State.QUEUED, "Owned ACTIVE completion never additionally completes older QUEUED duplicate")
	check(lines.filter(func(line): return "поручение выполнено —" in line).size() == 1 and not lines.any(func(line): return "поручение выполнено независимо" in line), "ACTIVE path emits only its original completion INFO")
	scene.free()
	# Interrupts never emit a successful result, whether independent or assignment-owned.
	for assigned in [false, true]:
		for eating in [false, true]:
			scene = Setup.make_scene(self)
			actor = scene.resident_runtimes[1]
			scene.kitchen_data.resources.add(FOOD, 1)
			actor.data.hunger = 80
			task = add(scene, actor, &"interrupted")
			if assigned: actor.assignments.start(task.id)
			else: actor.needs.try_eat(5000)
			if eating: actor.view._process(20)
			listen(scene)
			scene.player_control.move_to(actor.data.id, Vector2(-500, 300))
			scene.game_time.debug_skip_minutes(31)
			check(task.state == Assignment.State.QUEUED and not lines.any(func(line): return "поручение выполнено" in line), "Player-interrupted route/meal cannot satisfy request")
			check(scene.kitchen_data.resources.get_amount(FOOD) == (0 if eating else 1) and scene.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Reservation/consumption behavior unchanged during interrupt")
			scene.free()
	# Unavailable food / failed start never count as success.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	actor.data.hunger = 80
	task = add(scene, actor, &"no_food")
	check(not actor.needs.try_eat(5000) and not actor.assignments.start(task.id), "No FOOD means autonomous and assigned meal start both fail")
	scene.game_time.debug_skip_minutes(31)
	check(task.state == Assignment.State.QUEUED, "Failed food reservation/start cannot complete assignment")
	scene.free()
	# Skip terminal and nonmatching records; SUSPENDED is a future waiting state.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[1]
	kitchen_b = other_kitchen(scene)
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 80
	var completed = add(scene, actor, &"completed")
	completed.state = Assignment.State.COMPLETED
	var cancelled = add(scene, actor, &"cancelled")
	scene.player_control.cancel_assignment(actor.data.id, cancelled.id)
	var unmatched = add(scene, actor, &"other_target", kitchen_b.id)
	var suspended = add(scene, actor, &"suspended")
	suspended.state = Assignment.State.SUSPENDED
	var later = add(scene, actor, &"later")
	actor.needs.try_eat(5000)
	actor.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(completed.state == Assignment.State.COMPLETED and cancelled.state == Assignment.State.CANCELLED and unmatched.state == Assignment.State.QUEUED, "Terminal and nonmatching records ignored")
	check(suspended.state == Assignment.State.COMPLETED and later.state == Assignment.State.QUEUED, "First matching waiting instance completes; later queued duplicate remains")
	scene.free()
	print("Assignment results: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
