extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Data = preload("res://scripts/resident_data.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Definition = preload("res://scripts/building_definition.gd")
const HOME = preload("res://scripts/building_type.gd").Type.HOME
const WOOD = preload("res://scripts/resource_type.gd").Type.WOOD
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
var skill_events := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func scenario() -> Node:
	var scene = Setup.make_scene(self)
	scene.game_time.debug_next_phase()
	scene.resident_runtimes[0].data.work_location_id = scene.warehouse_data.id
	return scene
func site_in(scene: Node):
	scene.placement.select(Definition.for_type(HOME))
	scene.placement.update_position(Vector2(-500, 200))
	return scene.placement.confirm()
func become(scene: Node, actor: Node, profession: int) -> void:
	scene.player_control.assign_profession(actor.data.id, profession)
func arrive(actor: Node) -> void: actor.view._process(100)
func start_gathering(scene: Node, actor: Node) -> void:
	actor.data.work_location_id = scene.gatherer_hut_data.id
	actor.decision.work_available = scene.production.can_work.bind(actor.data)
	actor.schedule.request_work()
	arrive(actor)
	actor.decision.work_available = func(): return false
	check(actor.decision._work_cycle_active, "Gatherer starts actual committed cycle")
func _run() -> void:
	check(Balance.SKILL_XP_PER_LEVEL == 10 and Balance.MAX_SKILL_LEVEL == 10, "Prototype progression constants")
	for pair in [[0,0], [9,0], [10,1], [19,1], [20,2], [99,9], [100,10], [150,10]]:
		var sample = Data.new("skill_test", "Тест", 30)
		for skill in Skill.Type.values(): check(sample.get_skill_xp(skill) == 0, "Every new skill starts at zero")
		if pair[0] > 0: sample.add_skill_xp(Skill.Type.GATHERING, pair[0])
		check(sample.get_skill_xp(Skill.Type.GATHERING) == pair[0] and sample.get_skill_level(Skill.Type.GATHERING) == pair[1], "XP curve retains XP beyond maximum level")
		check(sample.get_skill_xp(Skill.Type.CONSTRUCTION) == 0 and sample.get_skill_xp(Skill.Type.LOGISTICS) == 0, "Skills are independent")
	var data = Data.new("skill_test", "Тест", 30)
	data.skill_changed.connect(func(_skill, _amount, _previous): skill_events += 1)
	check(not data.add_skill_xp(Skill.Type.GATHERING, -1) and not data.add_skill_xp(Skill.Type.GATHERING, 0), "Non-positive additions rejected")
	check(skill_events == 0 and data.get_skill_xp(Skill.Type.GATHERING) == 0, "Rejected XP produces no mutation or signal")
	data.add_skill_xp(Skill.Type.GATHERING, 1)
	check(skill_events == 1, "Successful XP emits one event")

	var scene = scenario()
	for runtime in scene.resident_runtimes:
		for skill in Skill.Type.values(): check(runtime.data.get_skill_xp(skill) == 0, "Starting residents receive no profession XP")
	var actor = scene.resident_runtimes[2]
	start_gathering(scene, actor)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 0, "Starting cycle grants no XP")
	scene.game_time.debug_skip_minutes(59)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 0, "Production before full cycle grants no XP")
	scene.game_time.debug_skip_minutes(1)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 1, "Completed gatherer cycle grants exactly one XP")
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 2, "Unchanged two FOOD per cycle gives no extra XP")
	start_gathering(scene, actor)
	scene.game_time.debug_skip_minutes(60)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 2, "Second full cycle grants one additional XP")
	start_gathering(scene, actor)
	scene.game_time.debug_skip_minutes(27)
	actor.commands.move_to(Vector2(200, 0))
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 2, "Interrupted gatherer cycle grants no XP")
	become(scene, actor, Profession.Type.BUILDER)
	actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 4)
	become(scene, actor, Profession.Type.GATHERER)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 2 and actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 4, "Profession switch preserves all XP")
	scene.free()
	# Profession at the start of a committed gatherer cycle determines its skill.
	scene = scenario()
	actor = scene.resident_runtimes[2]
	start_gathering(scene, actor)
	become(scene, actor, Profession.Type.NONE)
	scene.game_time.debug_skip_minutes(60)
	check(actor.data.get_skill_xp(Skill.Type.GATHERING) == 1, "Safe committed cycle awards gathering after profession switch")
	scene.free()

	for interrupted in [false, true]:
		scene = scenario()
		var cycle_site = site_in(scene)
		cycle_site.add_delivered_material(WOOD, cycle_site.get_required_amount(WOOD))
		actor = scene.resident_runtimes[1]
		become(scene, actor, Profession.Type.BUILDER)
		check(actor.builder.request_work(), "Builder starts actual task")
		arrive(actor)
		check(actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 0, "Work start grants no construction XP")
		scene.game_time.debug_skip_minutes(27 if interrupted else 60)
		if interrupted: actor.commands.move_to(Vector2(200, 0))
		check(cycle_site.construction_progress == (27 if interrupted else 60), "Existing partial/full work progress retained")
		check(actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == (0 if interrupted else 1), "Only a full builder cycle awards XP")
		scene.free()
	# Multiple workers contribute their own cycles, including the cycle completing the building.
	scene = scenario()
	var site = site_in(scene)
	site.add_delivered_material(WOOD, site.get_required_amount(WOOD))
	var actors = [scene.resident_runtimes[1], scene.resident_runtimes[3]]
	for worker in actors:
		become(scene, worker, Profession.Type.BUILDER)
		worker.builder.request_work()
		arrive(worker)
	scene.game_time.debug_skip_minutes(60)
	check(site.construction_progress == 120, "Two unchanged builder cycles contribute 120 work-minutes")
	for worker in actors: check(worker.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 1, "Each worker receives XP for own completed cycle")
	actors[0].builder.request_work()
	arrive(actors[0])
	scene.game_time.debug_skip_minutes(60)
	check(site.is_built() and actors[0].data.get_skill_xp(Skill.Type.CONSTRUCTION) == 2, "Building completion grants no bonus beyond full cycle")
	scene.free()
	# Builder-owned material transport must never award either professional skill.
	scene = scenario()
	site = site_in(scene)
	actor = scene.resident_runtimes[1]
	become(scene, actor, Profession.Type.BUILDER)
	actor.builder.request_work()
	arrive(actor)
	check(actor.data.inventory.amount == 1 and actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 0 and actor.data.get_skill_xp(Skill.Type.LOGISTICS) == 0, "WOOD pickup grants no XP")
	become(scene, actor, Profession.Type.NONE)
	arrive(actor)
	check(site.get_delivered_amount(WOOD) == 1 and actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 0 and actor.data.get_skill_xp(Skill.Type.LOGISTICS) == 0, "WOOD delivery grants no XP")
	scene.free()

	scene = scenario()
	actor = scene.resident_runtimes[0]
	for index in range(10):
		check(scene._request_haul_work(actor), "Porter claims available committed delivery")
		check(actor.data.get_skill_xp(Skill.Type.LOGISTICS) == index, "Claim grants no XP")
		arrive(actor)
		check(actor.data.get_skill_xp(Skill.Type.LOGISTICS) == index, "Pickup grants no XP")
		arrive(actor)
		check(actor.data.get_skill_xp(Skill.Type.LOGISTICS) == index + 1, "Successful delivery grants one XP")
	check(actor.data.get_skill_level(Skill.Type.LOGISTICS) == 1 and scene.kitchen_data.resources.get_amount(FOOD) == 10, "Ten deliveries yield level one with unchanged physical resources")
	scene.free()
	for after_pickup in [false, true]:
		scene = scenario()
		actor = scene.resident_runtimes[0]
		scene._request_haul_work(actor)
		if after_pickup: arrive(actor)
		actor.commands.move_to(Vector2(200, 0))
		check(actor.data.get_skill_xp(Skill.Type.LOGISTICS) == 0, "Interrupted haul grants no XP")
		check(scene.ground_resources.drops.size() == (1 if after_pickup else 0), "Drop/cleanup unchanged and grants no XP")
		scene.free()

	scene = scenario()
	actor = scene.resident_runtimes[1]
	var card = scene.get_node("HUD/ResidentCard")
	card.set_process(false)
	scene.resident_selection.select(actor.data)
	for skill in Skill.Type.values(): check(card.skills_label.text.contains("%s: ур. 0 (0 XP)" % Skill.display_name(skill)), "Selected card shows every skill")
	actor.data.add_skill_xp(Skill.Type.GATHERING, 27)
	check(card.skills_label.text.contains("Собирательство: ур. 2 (27 XP)"), "XP signal immediately updates derived level and XP")
	become(scene, actor, Profession.Type.BUILDER)
	check(card.skills_label.text.contains("Собирательство: ур. 2 (27 XP)"), "Profession change neither hides nor resets skills")
	card.skills_label.text = "event-only marker"
	card._refresh()
	check(card.skills_label.text == "event-only marker", "Regular refresh does not poll skills")
	actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 150)
	check(card.skills_label.text.contains("Строительство: ур. 10 (150 XP)"), "Signal restores view; max level retains actual XP")
	var second = scene.resident_runtimes[3]
	scene.resident_selection.select(second.data)
	check(not card.skills_label.text.contains("27 XP") and card.skills_label.text.contains("0 XP"), "Selection updates skills for another resident")
	var shown: String = card.skills_label.text
	actor.data.add_skill_xp(Skill.Type.GATHERING, 1)
	check(card.skills_label.text == shown, "Old resident signal is disconnected")
	# Skills have no effect on existing score or production parameters.
	site = site_in(scene)
	var before: float = actor.builder.site_priority(site, actor.view.global_position)
	actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 100)
	check(actor.builder.site_priority(site, actor.view.global_position) == before, "Skill level does not affect construction choice")
	var porter = scene.resident_runtimes[0]
	var candidates: Array = scene.logistics.collect_candidates(porter.data.id)
	porter.data.add_skill_xp(Skill.Type.LOGISTICS, 100)
	var high: Array = scene.logistics.collect_candidates(porter.data.id)
	check(candidates.size() == high.size() and candidates[0].porter_score == high[0].porter_score, "Skill level does not affect porter score")
	scene.free()
	# Critical needs interrupt through the same cleanup and never award unfinished work.
	for profession in [Profession.Type.GATHERER, Profession.Type.BUILDER, Profession.Type.PORTER]:
		scene = scenario()
		actor = scene.resident_runtimes[1]
		become(scene, actor, profession)
		if profession == Profession.Type.GATHERER:
			start_gathering(scene, actor)
			scene.game_time.debug_skip_minutes(27)
		elif profession == Profession.Type.BUILDER:
			site = site_in(scene)
			site.add_delivered_material(WOOD, site.get_required_amount(WOOD))
			actor.builder.request_work()
			arrive(actor)
			scene.game_time.debug_skip_minutes(27)
		else:
			scene._request_haul_work(actor)
			arrive(actor)
		actor.data.fatigue = 100
		for skill in Skill.Type.values(): check(actor.data.get_skill_xp(skill) == 0, "Critical interruption awards no unfinished XP")
		if profession == Profession.Type.BUILDER: check(site.construction_progress == 27, "Critical interrupt keeps partial progress without XP")
		scene.free()
	# Level ten has the same gatherer output and cycle duration as level zero.
	scene = scenario()
	actor = scene.resident_runtimes[2]
	actor.data.add_skill_xp(Skill.Type.GATHERING, 100)
	start_gathering(scene, actor)
	scene.game_time.debug_skip_minutes(60)
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 2 and actor.data.get_skill_xp(Skill.Type.GATHERING) == 101, "Level ten has unchanged gatherer cycle/output and continues storing XP")
	scene.free()
	# Only a level increase is INFO; each +1 is DEBUG when debugging is enabled.
	scene = scenario()
	scene.game_logger.debug_enabled = true
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	actor = scene.resident_runtimes[1]
	for _index in range(10): actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 1)
	check(lines.filter(func(line): return line.contains("Строительство +1 XP")).size() == 10, "XP gain logged at DEBUG")
	check(lines.filter(func(line): return line.contains("навык «Строительство» повышен")).size() == 1, "INFO emitted only for one level increase")
	scene.free()
	print("Resident skill checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
