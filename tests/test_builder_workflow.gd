extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const Resources = preload("res://scripts/resource_type.gd")
const PLANK = Resources.Type.PLANK
const FOOD = Resources.Type.FOOD
const Builder = preload("res://scripts/resident_builder_controller.gd")
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
	var scene = Setup.make_scene(self)
	scene.game_time.total_minutes = 420
	for runtime in scene.resident_runtimes: runtime.schedule._phase = "День"
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	return scene
func place(scene: Node, category: int = Types.HOME, point: Vector2 = Vector2(-500, 200)) -> Instance:
	scene.placement.select(Definition.for_type(category))
	scene.placement.update_position(point)
	return scene.placement.confirm()
func builder(scene: Node, index: int = 1) -> Node:
	var runtime = scene.resident_runtimes[index]
	scene.player_control.assign_profession(runtime.data.id, Profession.Type.BUILDER)
	return runtime
func arrive(runtime: Node) -> void: runtime.view._process(100)
func stock(site: Instance) -> void: site.add_delivered_material(PLANK, site.get_required_amount(PLANK))
func _run() -> void:
	check(Profession.display_name(Profession.Type.BUILDER) == "Строитель", "BUILDER exists with display name")
	var scene = scenario()
	check(scene.warehouse_data.resources.get_amount(PLANK) == 35 and scene.warehouse_data.resources.get_amount(FOOD) == 10, "Prototype warehouse has 35 PLANK; FOOD unchanged")
	var actor = builder(scene)
	check(actor.data.profession == Profession.Type.BUILDER and actor.data.work_location_id.is_empty(), "Player API assigns mobile builder without fixed workplace")
	var card = scene.get_node("HUD/ResidentCard")
	check(card.profession_choice.get_item_index(Profession.Type.BUILDER) >= 0, "Existing profession UI exposes BUILDER")
	var site = place(scene)
	var far = place(scene, Types.HOME, Vector2(-900, 200))
	var base: float = actor.builder.site_priority(site, site.position)
	site.add_delivered_material(PLANK, 8)
	check(is_equal_approx(actor.builder.site_priority(site, site.position) - base, 1600), "Delivered material fraction adds 1600")
	site.add_construction_work(90)
	check(is_equal_approx(actor.builder.site_priority(site, site.position), 2600), "Construction half-progress adds 1000")
	site.claim_builder_slot("other")
	check(is_equal_approx(actor.builder.site_priority(site, site.position), 3600), "Existing active builder adds 1000")
	check(is_equal_approx(actor.builder.site_priority(site, site.position + Vector2(300, 0)), 2600) and is_equal_approx(actor.builder.site_priority(site, site.position + Vector2(600, 0)), -400), "Quadratic distance: 300 costs 1000, 600 costs 4000")
	stock(far)
	far.claim_builder_slot("other_far")
	check(actor.builder.site_priority(far, far.position + Vector2(600, 0)) < 1600, "Full materials + one builder at 600 loses to nearby 80% materials")
	for distance in [0, 150, 300, 600, 900]:
		print("Calibration: materials=0.8 progress=0.5 builders=1 distance=%d score=%.0f" % [distance, actor.builder.site_priority(site, site.position + Vector2(distance, 0))])
	check(actor.builder.best_site() != scene.warehouse_data, "BUILT buildings excluded from site selection")
	site.claim_builder_slot("third")
	check(actor.builder.best_site() != site, "Full builder slots excluded")
	site.release_builder_slot("third")
	site.release_builder_slot("other")
	far.release_builder_slot("other_far")
	actor.view.global_position = site.position
	check(actor.builder.best_site() == site, "Near advanced site selected by unified score")
	actor.decision.work_available = scene._work_available.bind(actor)
	actor.decision.work_request = scene._request_work.bind(actor)
	check(actor.decision.collect_actions(scene._work_available(actor)).any(func(row): return row.id == "WORK" and row.priority == Balance.WORK_PRIORITY), "Builder WORK category utility is 7000 regardless of site score")
	actor.decision.request_decision("builder_test")
	check(actor.builder.site == site and actor.builder.phase == Builder.Phase.GOING_TO_SOURCE and actor.data.id in site.active_builder_ids, "Normal UtilitySelector selects WORK then builder chooses/claims site")
	check(scene.warehouse_data.resources.get_reserved_out(PLANK) == 1 and site.get_construction_reserved_in(PLANK) == 1 and actor.data.inventory.amount == 0, "Before pickup both reservations exist, resident carries nothing")
	check(actor.builder.phase != Builder.Phase.BUILDING, "Incomplete materials prevent building")
	arrive(actor)
	check(actor.data.inventory.amount == 1 and actor.data.inventory.resource_type == PLANK and actor.data.activity == Activity.HAULING and scene.warehouse_data.resources.get_amount(PLANK) == 34, "Pickup physically transfers one PLANK to inventory")
	check(actor.builder.phase == Builder.Phase.CARRYING_TO_SITE and actor.view.target_position == site.position, "Cargo moves toward chosen concrete site")
	scene.player_control.assign_profession(actor.data.id, Profession.Type.NONE)
	arrive(actor)
	check(site.get_delivered_amount(PLANK) == 9 and site.get_construction_reserved_in(PLANK) == 0 and scene.warehouse_data.resources.get_reserved_out(PLANK) == 0 and actor.data.inventory.amount == 0, "Delivery commits one unit and clears reservations")
	check(actor.builder.phase == Builder.Phase.NONE and site.active_builder_ids.is_empty(), "Profession change finishes current safe trip but starts no next builder task")
	scene.free()

	# Independent workers reserve separate final units; transport never creates Porter jobs.
	scene = scenario()
	site = place(scene)
	site.add_delivered_material(PLANK, 9)
	actor = builder(scene)
	var second = builder(scene, 3)
	check(actor.builder.request_work(), "First builder reserves final unit")
	check(not second.builder.has_work() and not second.builder.request_work() and site.get_uncovered_construction_amount(PLANK) == 0, "All missing in transit: second builder exits instead of over-reserving or polling")
	check(site.get_construction_material_ratio() == 0.9 and site.get_construction_reserved_in(PLANK) == 1, "In-transit affects deficit but not site priority material fraction")
	check(not site.add_delivered_material(PLANK, 1), "Unreserved arrivals cannot steal capacity promised to another builder")
	actor.commands.move_to(Vector2(200, 0))
	check(scene.warehouse_data.resources.get_reserved_out(PLANK) == 0 and site.get_construction_reserved_in(PLANK) == 0 and site.active_builder_ids.is_empty() and scene.ground_resources.drops.is_empty(), "PlayerCommand before pickup releases both reservations and slot without drop")
	check(second.builder.has_work(), "Released reservations immediately expose construction work")
	second.builder.request_work()
	arrive(second)
	var drop_position: Vector2 = second.view.global_position
	second.commands.move_to(Vector2(100, 0))
	check(scene.warehouse_data.resources.get_amount(PLANK) == 34 and second.data.inventory.amount == 0 and site.get_construction_reserved_in(PLANK) == 0 and site.active_builder_ids.is_empty(), "PlayerCommand after pickup keeps source consumed, releases inbound/slot")
	check(scene.ground_resources.drops.size() == 1 and scene.ground_resources.drops[0].resource_type == PLANK and scene.ground_resources.drops[0].world_position == drop_position, "Carried PLANK drops physically at interruption position")
	check(scene.logistics.jobs.all(func(job): return job.resource_type == FOOD), "Builder transport creates no Porter HaulJob")
	scene.free()

	for after_pickup in [false, true]:
		scene = scenario()
		site = place(scene)
		actor = builder(scene)
		actor.builder.request_work()
		if after_pickup: arrive(actor)
		actor.data.fatigue = 100
		check(actor.builder.phase == Builder.Phase.NONE and site.active_builder_ids.is_empty() and site.get_construction_reserved_in(PLANK) == 0 and scene.warehouse_data.resources.get_reserved_out(PLANK) == 0, "Critical fatigue cleans reservations and slot in either transport phase")
		check(scene.ground_resources.drops.size() == (1 if after_pickup else 0), "Critical fatigue drops only physically picked-up cargo")
		scene.free()

	scene = scenario()
	site = place(scene)
	actor = builder(scene)
	scene.warehouse_data.resources.try_take(PLANK, 35)
	check(not actor.builder.has_work() and not actor.builder.request_work(), "No available PLANK means no stuck builder task")
	var searches: int = actor.builder.source_search_count
	for _i in range(10): actor.builder.has_work()
	check(actor.builder.source_search_count == searches, "Repeated normal availability reads do not poll an unavailable PLANK source")
	actor.decision.work_available = scene._work_available.bind(actor)
	actor.decision.work_request = scene._request_work.bind(actor)
	var decision_before: int = actor.decision.decision_count
	for _i in range(3): actor.builder._on_world_changed()
	await process_frame
	check(actor.decision.decision_count == decision_before, "No-world-change/no-material state generates no retry decision loop")
	scene.warehouse_data.resources.add(PLANK, 1)
	await process_frame
	check(actor.builder.phase == Builder.Phase.GOING_TO_SOURCE, "PLANK availability event wakes free builder through ordinary decision flow")
	scene.free()

	# Nearest physical source and concurrent reservations on an uncovered deficit.
	scene = scenario()
	site = place(scene)
	actor = builder(scene)
	second = builder(scene, 3)
	var near_source = place(scene, Types.STORAGE, Vector2(200, -300))
	stock(near_source)
	near_source.add_construction_work(near_source.definition.construction_work_required)
	near_source.complete_construction()
	near_source.resources.add(PLANK, 2)
	actor.view.global_position = near_source.position + Vector2(0, 10)
	check(actor.builder.nearest_source(PLANK, actor.view.global_position) == near_source, "Nearest BUILT available PLANK source wins")
	check(actor.builder.request_work() and second.builder.request_work() and site.get_construction_reserved_in(PLANK) == 2 and site.active_builder_ids.size() == 2, "Two builders reserve different units within uncovered deficit")
	arrive(actor)
	arrive(second)
	check(actor.data.inventory.amount == 1 and second.data.inventory.amount == 1, "Concurrent trips keep separate resident cargo")
	arrive(actor)
	arrive(second)
	check(site.get_delivered_amount(PLANK) == 2 and site.get_construction_reserved_in(PLANK) == 2 and site.active_builder_ids.size() == 2, "Slots retained across trips; new reservations cover remaining deficit only")
	actor.commands.move_to(Vector2.ZERO)
	second.commands.move_to(Vector2.ZERO)
	scene.free()

	# Loss of a target / source availability uses the same ownership cleanup.
	for lost_target in [false, true]:
		scene = scenario()
		site = place(scene)
		actor = builder(scene)
		actor.builder.request_work()
		if lost_target:
			arrive(actor)
			scene.buildings.erase(site)
			actor.builder._on_world_changed()
		else:
			arrive(actor)
			scene.warehouse_data.resources.try_take(PLANK, 34)
			arrive(actor)
		check(actor.builder.phase == Builder.Phase.NONE and site.active_builder_ids.is_empty() and site.get_construction_reserved_in(PLANK) == 0, "Missing site or exhausted source ends task and releases ownership")
		check(scene.ground_resources.drops.size() == (1 if lost_target else 0), "Missing site drops picked-up cargo; valid final delivery does not")
		scene.free()

	# Critical hunger is the existing forced eat bypass, not a builder hierarchy.
	scene = scenario()
	site = place(scene)
	actor = builder(scene)
	actor.builder.request_work()
	arrive(actor)
	scene.kitchen_data.resources.add(FOOD, 1)
	actor.data.hunger = 100
	check(actor.intents.current_intent.reason_id == &"eat" and actor.builder.phase == Builder.Phase.NONE and scene.ground_resources.drops.size() == 1, "Critical hunger uses ordinary forced cleanup and drops PLANK")
	scene.free()

	# Full unassisted pipeline, ten physical trips and three normal work selections.
	scene = scenario()
	site = place(scene)
	actor = builder(scene)
	actor.decision.work_available = scene._work_available.bind(actor)
	actor.decision.work_request = scene._request_work.bind(actor)
	actor.decision.request_decision("full_construction")
	for _trip in range(10):
		arrive(actor)
		arrive(actor)
	check(site.get_delivered_amount(PLANK) == 10 and scene.warehouse_data.resources.get_amount(PLANK) == 25 and site.get_construction_reserved_in(PLANK) == 0 and actor.builder.phase == Builder.Phase.BUILDING, "Full physical material pipeline: warehouse -> resident -> delivered site")
	var cycle_decisions: int = actor.decision.decision_count
	scene.game_time.debug_skip_minutes(180)
	check(site.is_built() and actor.decision.decision_count == cycle_decisions + 3 and actor.builder.phase == Builder.Phase.NONE, "Three 60-minute cycles each pass normal UtilitySelector; automatic completion after 180 work-minutes")
	check(actor.data.inventory.amount == 0 and site.active_builder_ids.is_empty() and scene.ground_resources.drops.is_empty(), "Completed full pipeline has no orphan cargo/reservations/slots")
	scene.free()

	# Work is physical, building-owned, pause/speed-safe and committed for 60 minutes.
	for speed in [1, 10, 20]:
		scene = scenario()
		site = place(scene)
		stock(site)
		actor = builder(scene)
		actor.builder.request_work()
		check(actor.builder.phase == Builder.Phase.GOING_TO_SITE and site.construction_progress == 0, "Complete materials produce route, not remote construction work")
		scene.game_time.set_speed(speed)
		scene.game_time.advance(5.0 / speed)
		check(site.construction_progress == 0 and actor.builder.work_minutes == 0, "Walking contributes zero work")
		arrive(actor)
		check(actor.data.activity == Activity.WORKING and actor.builder.phase == Builder.Phase.BUILDING, "Actual arrival starts construction cycle")
		paused = true
		scene.game_time.advance(100)
		paused = false
		check(actor.builder.work_minutes == 0, "Pause freezes construction")
		var count: int = actor.decision.decision_count
		scene.game_time.advance(59.0 / speed)
		actor.data.get_need(preload("res://scripts/need_type.gd").Type.LEISURE).value = 100
		actor.decision.request_decision("normal_need_growth")
		check(site.construction_progress == 59 and actor.builder.work_minutes == 59 and actor.decision.decision_count == count, "Ordinary needs do not interrupt committed 59-minute cycle")
		scene.player_control.assign_profession(actor.data.id, Profession.Type.NONE)
		scene.game_time.advance(1.0 / speed)
		check(site.construction_progress == 60 and actor.builder.phase == Builder.Phase.NONE and actor.decision.decision_count == count + 1 and site.active_builder_ids.is_empty(), "60-minute cycle credits +60 and exactly one normal decision, respects profession change")
		scene.free()

	scene = scenario()
	site = place(scene)
	stock(site)
	actor = builder(scene)
	second = builder(scene, 3)
	actor.builder.request_work()
	second.builder.request_work()
	arrive(actor)
	arrive(second)
	check(site.active_builder_ids.size() == 2, "Two builders own separate slots at same site")
	scene.game_time.debug_skip_minutes(60)
	check(site.construction_progress == 120 and site.active_builder_ids.is_empty(), "Two builders each credit +60, cumulative +120 with independent boundaries")
	actor.builder.request_work()
	arrive(actor)
	scene.game_time.debug_skip_minutes(15)
	actor.commands.move_to(Vector2(0, 0))
	check(site.construction_progress == 135 and site.active_builder_ids.is_empty(), "Partial interrupted cycle preserves 15 actual work-minutes in building")
	arrive(actor)
	actor.builder.request_work()
	arrive(actor)
	scene.game_time.debug_skip_minutes(60)
	check(site.is_built() and site.construction_progress == 180 and site.id == &"building_0001" and site.active_builder_ids.is_empty(), "Completion clamps required, preserves ID and frees slots")
	check(not actor.builder.has_work(), "BUILT no longer offers builder work")
	check(lines.any(func(line): return "начал строительный цикл" in line) and lines.any(func(line): return "доставил 1 PLANK" in line) and lines.any(func(line): return "строительство завершено" in line), "INFO logs cover transport, cycles and completion")
	scene.free()

	# Each completed type enters existing systems on the same instance/view.
	for category in [Types.STORAGE, Types.FOOD, Types.GATHERER_HUT]:
		scene = scenario()
		site = place(scene, category)
		stock(site)
		site.add_construction_work(site.definition.construction_work_required)
		scene.resident_selection.select_building(site)
		site.complete_construction()
		check(scene.world_locations.get_view(site.id).building_data == site and not scene.get_node("HUD/BuildingCard").construction_section.visible, "Same visual/card reflect completed instance immediately")
		check(not scene.interactions.get_interactions([scene.residents[1].id], site.id).is_empty(), "Completed type exposes normal context interactions")
		if category == Types.FOOD:
			check(site.resources.get_capacity(FOOD) == 20 and scene.resident_runtimes[1].needs.get_food_target(site.id) == site and scene.logistics._buildings.has(site.id), "Completed kitchen supports eating and food logistics")
		elif category == Types.STORAGE:
			check(site.resources.get_capacity(FOOD) == 20 and site.resources.get_capacity(PLANK) == 35 and scene.player_control.assign_workplace(scene.residents[1].id, site.id), "Completed warehouse supports storage and workplace API")
		else:
			check(scene.player_control.assign_workplace(scene.residents[1].id, site.id) and scene.production.can_work(scene.residents[1]), "Completed hut offers gatherer work")
			var gatherer = scene.resident_runtimes[1]
			gatherer.data.activity = Activity.WORKING
			gatherer.view.global_position = site.position
			scene.game_time.debug_skip_minutes(30)
			check(site.resources.get_amount(FOOD) == 1 and site.production_progress == 0, "New hut produces FOOD through existing production observer")
		scene.free()
	print("Builder workflow: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
