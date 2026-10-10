extends SceneTree
## Real main_3d controllers/executor; controlled time isolates the construction boundary.
const Builder = preload("res://scripts/resident_builder_controller.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd")
const Resources = preload("res://scripts/resource_type.gd").Type
const Intent = preload("res://scripts/resident_intent.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var checks := 0
var failures := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func scenario() -> Node:
	var scene = preload("res://tests/legacy_starter_3d.gd").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.game_time.total_minutes = 420
	scene.game_logger.console_enabled = false
	scene.social_events.enabled = false
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	for actor in scene.resident_runtimes:
		actor.view.set_physics_process(false)
		actor.decision._deciding = true
		actor.schedule._phase = "День"
		actor.intents.abort_current(actor.intents.current_intent)
		for need in actor.data.needs.values(): need.value = 0
	return scene
func place(scene: Node, point: Vector3):
	scene.placement.select(Definition.for_type(Types.HOME))
	scene.placement.update_world_position(point)
	return scene.placement.confirm()
func worker(scene: Node, index: int = 1) -> Node:
	var actor = scene.resident_runtimes[index]
	scene.player_control.assign_profession(actor.data.id, Profession.Type.BUILDER)
	actor.intents.abort_current(actor.intents.current_intent)
	return actor
func assign_wait(scene: Node, site: RefCounted, actor: Node, at_site: bool = true) -> void:
	# A already-committed assignment, not a new global A-vs-B choice.
	check(site.claim_builder_slot(actor.data.id), "Existing assignment has a real builder slot")
	actor.builder.site = site
	if at_site: actor.view.global_position = Coordinates.to_world(scene.world_locations.get_position(site.id))
	check(actor.builder._continue_task(), "Committed assignment can enter waiting")
func walk(actor: Node, phase: int) -> void:
	for step in range(1500):
		if actor.builder.phase != phase: break
		actor.view._physics_process(0.05)
	check(actor.builder.phase != phase, "Real NavigationGrid movement reaches access point")
func _run() -> void:
	var scene = scenario()
	var a = place(scene, Vector3(4,0,14))
	a.add_delivered_material(Resources.PLANK,8)
	a.reserve_construction_material(Resources.PLANK,2)
	var b = place(scene,Vector3(10,0,18))
	b.add_delivered_material(Resources.PLANK,10)
	var actor = worker(scene)
	assign_wait(scene,a,actor)
	check(actor.builder.phase == Builder.Phase.WAITING_FOR_MATERIALS and actor.builder.site == a, "A8+2 stays committed instead of choosing material-ready B")
	check(actor.intents.current_intent.type == Intent.Type.NONE and actor.intents.current_intent.interruptible and actor.intents.has_current_action(), "Wait uses interruptible stationary action, not forced priority")
	check(actor.view.get_sim_position().distance_to(scene.world_locations.get_position(a.id)) <= 8, "Wait remains at shared action location")
	var searches: int = actor.builder.source_search_count
	var wait_logs: int = lines.filter(func(line): return "ждёт материалы" in line).size()
	for minute in range(60): actor.builder._on_minute(420+minute)
	check(a.construction_progress == 0, "Sixty waiting minutes never contribute construction work")
	check(actor.builder.source_search_count == searches and lines.filter(func(line): return "ждёт материалы" in line).size() == wait_logs, "Waiting never polls sources or logs per minute")
	a.deliver_reserved_construction_material(Resources.PLANK,1)
	await process_frame
	check(actor.builder.phase == Builder.Phase.WAITING_FOR_MATERIALS and a.get_delivered_amount(Resources.PLANK) == 9 and a.get_construction_reserved_in(Resources.PLANK) == 1, "First arrival 9+1 keeps same assignment")
	a.deliver_reserved_construction_material(Resources.PLANK,1)
	await process_frame
	walk(actor,Builder.Phase.GOING_TO_SITE)
	check(actor.builder.site == a and actor.builder.phase == Builder.Phase.BUILDING and b.active_builder_ids.is_empty(), "Second arrival resumes construction A through its event")
	check(scene.warehouse_data.resources.get_reserved_out(Resources.PLANK) == 0 and a.get_construction_reserved_in(Resources.PLANK) == 0, "Wait never creates duplicate reservations")
	scene.free()

	# Two real builders carrying the last units: first waits, second still delivers.
	scene = scenario()
	a = place(scene,Vector3(4,0,14))
	a.add_delivered_material(Resources.PLANK,8)
	actor = worker(scene)
	var carrier = worker(scene,3)
	check(scene._request_work(actor) and scene._request_work(carrier), "Both normal WORK requests reserve their own last unit")
	check(a.get_construction_reserved_in(Resources.PLANK) == 2 and a.active_builder_ids.size() == 2, "Real inbound transport owns both existing slots")
	b = place(scene,Vector3(10,0,18))
	b.add_delivered_material(Resources.PLANK,10)
	walk(actor,Builder.Phase.GOING_TO_SOURCE)
	walk(actor,Builder.Phase.CARRYING_TO_SITE)
	check(actor.builder.phase == Builder.Phase.WAITING_FOR_MATERIALS and carrier.builder.phase == Builder.Phase.GOING_TO_SOURCE, "First carrier waits while other carrier remains active; no slot deadlock")
	walk(carrier,Builder.Phase.GOING_TO_SOURCE)
	walk(carrier,Builder.Phase.CARRYING_TO_SITE)
	await process_frame
	walk(actor,Builder.Phase.GOING_TO_SITE)
	walk(carrier,Builder.Phase.GOING_TO_SITE)
	check(actor.builder.phase == Builder.Phase.BUILDING and carrier.builder.phase == Builder.Phase.BUILDING and actor.builder.site == a and carrier.builder.site == a, "Both original builders resume A, not B")
	check(a.get_delivered_amount(Resources.PLANK) == 10 and a.active_builder_ids.size() == 2 and scene.warehouse_data.resources.get_amount(Resources.PLANK) == 33, "Two physical deliveries retain capacity=2 and exact material counts")
	scene.game_time.total_minutes += 60
	actor.builder._on_minute(scene.game_time.total_minutes)
	carrier.builder._on_minute(scene.game_time.total_minutes)
	check(a.construction_progress == 120 and a.active_builder_ids.is_empty(), "Independent cycles add120 then normal decision boundary releases slots")
	scene.free()

	# Real carrier interruption releases its inbound commitment and wakes the waiter.
	for after_pickup in [false,true]:
		scene = scenario()
		a = place(scene,Vector3(4,0,14))
		a.add_delivered_material(Resources.PLANK,8)
		actor = worker(scene)
		carrier = worker(scene,3)
		actor.builder.request_work()
		carrier.builder.request_work()
		walk(actor,Builder.Phase.GOING_TO_SOURCE)
		walk(actor,Builder.Phase.CARRYING_TO_SITE)
		if after_pickup: walk(carrier,Builder.Phase.GOING_TO_SOURCE)
		carrier.commands.move_to(Vector2(0,500))
		await process_frame
		check(actor.builder.site == a and actor.builder.phase == Builder.Phase.GOING_TO_SOURCE, "Actual carrier cancellation wakes A waiter into fetch")
		check(a.get_construction_reserved_in(Resources.PLANK) == 1 and scene.warehouse_data.resources.get_reserved_out(Resources.PLANK) == 1, "Cleanup and resumed fetch leave exactly one current reservation")
		check(scene.ground_resources.drops.size() == (1 if after_pickup else 0), "Carrier cleanup preserves physical before/after pickup semantics")
		scene.free()

	# Reservation loss resumes the same fetch flow, or releases impossible commitment.
	for has_source in [true,false]:
		scene = scenario()
		a = place(scene,Vector3(4,0,14))
		a.add_delivered_material(Resources.PLANK,8)
		a.reserve_construction_material(Resources.PLANK,2)
		b = place(scene,Vector3(10,0,18))
		b.add_delivered_material(Resources.PLANK,10)
		actor = worker(scene)
		assign_wait(scene,a,actor)
		if not has_source: scene.warehouse_data.resources.try_take(Resources.PLANK,35)
		a.release_construction_material(Resources.PLANK,2)
		await process_frame
		if has_source:
			check(actor.builder.site == a and actor.builder.phase == Builder.Phase.GOING_TO_SOURCE and a.get_construction_reserved_in(Resources.PLANK) == 1, "Lost inbound reservation invokes existing one-unit fetch on A")
			check(scene.warehouse_data.resources.get_reserved_out(Resources.PLANK) == 1, "Fetch reserves real source stock")
		else:
			check(actor.builder.site == null and a.active_builder_ids.is_empty() and not actor.intents.has_current_action(), "No source/no inbound releases impossible wait")
			check(actor.builder.best_site() == b, "Fresh global choice can select B after abandonment")
		scene.free()

	scene = scenario()
	a = place(scene,Vector3(4,0,14))
	a.add_delivered_material(Resources.PLANK,8)
	a.reserve_construction_material(Resources.PLANK,1)
	actor = worker(scene)
	check(actor.builder.request_work() and actor.builder.phase == Builder.Phase.GOING_TO_SOURCE and a.get_construction_reserved_in(Resources.PLANK) == 2, "8+1 is partial coverage: reserve/fetch uncovered last unit, never waiting-only")
	scene.free()

	# Multiple already-assigned waiters and arrival from away share the same access resolver.
	scene = scenario()
	a = place(scene,Vector3(4,0,14))
	a.add_delivered_material(Resources.PLANK,8)
	a.reserve_construction_material(Resources.PLANK,2)
	actor = worker(scene)
	carrier = worker(scene,3)
	assign_wait(scene,a,actor,false)
	check(actor.builder.phase == Builder.Phase.GOING_TO_WAIT, "Waiting assignment walks back if away from its access point")
	walk(actor,Builder.Phase.GOING_TO_WAIT)
	assign_wait(scene,a,carrier)
	check(actor.builder.phase == Builder.Phase.WAITING_FOR_MATERIALS and carrier.builder.phase == Builder.Phase.WAITING_FOR_MATERIALS, "Two assigned waiters hold their own slots")
	a.deliver_reserved_construction_material(Resources.PLANK,2)
	await process_frame
	walk(actor,Builder.Phase.GOING_TO_SITE)
	walk(carrier,Builder.Phase.GOING_TO_SITE)
	check(actor.builder.phase == Builder.Phase.BUILDING and carrier.builder.phase == Builder.Phase.BUILDING and a.active_builder_ids.size() == 2, "Two waiters independently resume without new inbound reservations")
	scene.free()

	for ending in ["player","critical","schedule","complete","cancel","profession"]:
		scene = scenario()
		a = place(scene,Vector3(4,0,14))
		a.add_delivered_material(Resources.PLANK,8)
		a.add_construction_work(27)
		a.reserve_construction_material(Resources.PLANK,2)
		actor = worker(scene)
		assign_wait(scene,a,actor)
		match ending:
			"profession": scene.player_control.assign_profession(actor.data.id,Profession.Type.NONE)
			"player": actor.commands.move_to(Vector2(0,500))
			"critical":
				actor.decision._deciding = false
				actor.data.fatigue = 100
			"schedule":
				scene.game_time.total_minutes = 1020
				scene.game_time.phase_changed.emit("Вечер")
			"complete":
				a.deliver_reserved_construction_material(Resources.PLANK,2)
				a.add_construction_work(180)
				a.complete_construction()
			"cancel": check(scene.cancel_construction(a.id), "Construction cancellation succeeds")
		await process_frame
		check(actor.builder.phase == Builder.Phase.NONE and actor.builder.site == null and a.active_builder_ids.is_empty(), "Wait cleanup after " + ending)
		check(a.construction_progress == (180 if ending == "complete" else 27), "Stored building progress survives " + ending)
		if ending == "player": check(actor.commands.active_command != null, "Absolute PlayerCommand priority retained")
		if ending == "critical": check(actor.intents.current_intent.reason_id == &"critical_sleep", "Critical fatigue retains existing forced sleep")
		scene.free()
	check(lines.any(func(line): return "материалы доставлены" in line) and lines.any(func(line): return "ожидаемая поставка отменена" in line), "Transition logs explain resume and loss")
	print("Builder waiting: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
