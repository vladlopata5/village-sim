extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const Data = preload("res://scripts/resident_data.gd")
const Ops = preload("res://scripts/work_operation_skills.gd")
const S = preload("res://scripts/skill_type.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const D = preload("res://scripts/building_definition.gd")
const Phase = preload("res://scripts/resident_recipe_controller.gd").Phase
const Batch = preload("res://scripts/production_batch.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	catalog()
	await recipes()
	await extraction_handoff()
	print("Work operation skills: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
func catalog() -> void:
	var resident := Data.new("new", "Тест", 20)
	var real_recipes: Dictionary = {}
	for type in T.values():
		for recipe in D.for_type(type).production_recipes: real_recipes[recipe.id] = true
	check(real_recipes.size() == Ops.RECIPES.size() and real_recipes.keys().all(func(id): return Ops.RECIPES.has(id)), "Every actual recipe is covered, without invented recipe awards")
	for operation in Ops.OPERATIONS:
		var rules := Ops.for_operation(operation)
		check(rules.is_valid() and rules.can_perform(resident), "Base operation accepts zero XP: " + operation)
		check(rules.efficiency_weights.size() == 1 and rules.efficiency_weights[0].weight_percent == 100, "Secondary training never changes extraction efficiency")
	for operation in [&"chop_tree", &"mine_stone"]:
		var primary: int = S.FORESTRY if operation == &"chop_tree" else S.MINING
		var secondary: int = S.WOODWORKING if operation == &"chop_tree" else S.STONEWORKING
		var rules := Ops.for_operation(operation)
		resident.add_skill_xp(secondary, 999)
		check(resident.award_skill_xp(rules) and resident.get_skill_xp(primary) == 8 and resident.get_skill_xp(secondary) == 1000, "Secondary reward is partially capped at 1000")
		check(resident.award_skill_xp(rules) and resident.get_skill_xp(primary) == 16 and resident.get_skill_xp(secondary) == 1000, "Primary reward continues after secondary training cap")
		resident.add_skill_xp(secondary, 200)
		resident.award_skill_xp(rules)
		check(resident.get_skill_xp(secondary) == 1200 and resident.get_skill_xp(primary) == 24, "Extraction never reduces later workshop XP")
	var clay := Ops.for_operation(&"mine_clay")
	check(clay.xp_rewards == [Ops.reward(S.MINING, 8)], "Clay has no invented secondary reward")
	var changed := Ops.for_operation(&"delivery"); changed.xp_rewards[0].amount = 999
	check(Ops.for_operation(&"delivery").xp_rewards[0].amount == 3, "One consumer cannot mutate catalog rules")
	check(Ops.for_operation(&"loading").xp_rewards.is_empty() and Ops.for_operation(&"unloading").xp_rewards.is_empty(), "Handling stages have no additional XP")

func recipes() -> void:
	var cases := [
		[T.SAWMILL, &"sawmill_plank", S.WOODWORKING, 3, 1, 30],
		[T.STONEMASON_WORKSHOP, &"cut_stone_brick", S.STONEWORKING, 3, 1, 30],
		[T.POTTERY_WORKSHOP, &"fire_brick", S.POTTERY, 3, 1, 30],
		[T.WEAVER_WORKSHOP, &"wool_cloth", S.WEAVING, 6, 2, 60],
		[T.TAILOR_WORKSHOP, &"wool_clothing", S.TAILORING, 12, 4, 120],
		[T.WINDMILL, &"mill_flour", S.MILLING, 6, 2, 60],
		[T.FOOD, &"fried_mushroom", S.COOKING, 4, 0, 30],
		[T.FOOD, &"bake_bread", S.COOKING, 4, 0, 30],
		[T.FARM, &"thresh_wheat", S.FARMING, 4, 0, 30]]
	for row in cases:
		var world := F.create(self)
		var place: RefCounted = F.building(world, row[0], Vector3(-10, 0, 16))
		var first: Node = world.resident_runtimes[0]
		var last: Node = world.resident_runtimes[1]
		var recipe: RefCounted
		for value in place.definition.production_recipes:
			if value.id == row[1]: recipe = value
		check(recipe != null and recipe.work_required == row[5], "Existing recipe and unchanged duration " + row[1])
		for resource in recipe.inputs: place.resources.add(resource, recipe.inputs[resource])
		for key in recipe.consumables:
			var stock: RefCounted = place.consumable_stocks[key]
			var material: int = stock.conversions.keys()[0]
			check(stock.reserve_in(material, 1) and stock.deliver(material, 1), "Real consumable receipt")
		check(world.player_control.assign_workplace(first.data.id, place.id), "First worker assigned")
		if row[1] == &"sawmill_plank": first.data.add_skill_xp(row[2], 10000)
		var before: Dictionary = first.data._skill_xp.duplicate()
		var rules := Ops.for_operation(row[1])
		check(rules.is_valid() and rules.can_perform(last.data) and rules.efficiency_weights[0].weight_percent == (80 if row[4] > 0 else 100), "Approved recipe weights and zero-XP admission")
		check(first.recipe_work.request_work(), "Real production controller starts " + row[1])
		F.walk(world, first)
		check(first.recipe_work.phase == Phase.WORKING, "Physical work arrival")
		var batch: RefCounted = first.recipe_work.batch
		world.game_time.debug_skip_minutes(row[5] - 1)
		check(batch.progress == row[5] - 1 and batch.state == Batch.State.RUNNING and first.data._skill_xp == before, "No premature output/XP or skill-based acceleration")
		first.recipe_work.abort()
		check(batch.state == Batch.State.PAUSED and first.data._skill_xp == before, "Interrupted owner receives no XP; progress persists")
		world.player_control.assign_profession(first.data.id, preload("res://scripts/resident_profession.gd").Type.NONE)
		check(world.player_control.assign_workplace(last.data.id, place.id) and last.recipe_work.request_work(), "Another worker resumes paid batch")
		F.walk(world, last)
		check(last.recipe_work.batch == batch and batch.progress == row[5] - 1, "Same batch, no new material payment")
		var nested := func(_skill, _amount, _previous):
			last.recipe_work._on_minute(world.game_time.total_minutes)
			last.recipe_work.abort()
		last.data.skill_changed.connect(nested, CONNECT_ONE_SHOT)
		world.game_time.debug_skip_minutes(1)
		check(batch.state == Batch.State.COMPLETED and first.data._skill_xp == before, "Commit survives nested interruption; original owner is not awarded")
		check(last.data.get_skill_xp(row[2]) == row[3] and last.data.get_skill_xp(S.CRAFTING) == row[4], "Exactly one multi-skill award to completing worker")
		for resource in recipe.outputs: check(place.resources.get_amount(resource) == recipe.outputs[resource], "Output quantity is unchanged and does not multiply XP")
		var after: Dictionary = last.data._skill_xp.duplicate()
		last.recipe_work._on_minute(world.game_time.total_minutes)
		last.recipe_work.abort(); batch.finish(last.data.id)
		check(last.data._skill_xp == after, "Repeated finish/cleanup cannot award again")
		world.free()
		await process_frame

func extraction_handoff() -> void:
	var professions = preload("res://scripts/resident_profession.gd").Type
	var resources = preload("res://scripts/resource_type.gd").Type
	for kind in [&"tree", &"stone", &"clay"]:
		var world := F.create(self)
		var first: Node = world.resident_runtimes[0]
		var last: Node = world.resident_runtimes[1]
		var profession: int = professions.LUMBERJACK if kind == &"tree" else professions.MINER if kind == &"stone" else professions.CLAY_DIGGER
		world.player_control.assign_profession(first.data.id, profession)
		var first_work: Node = first.get_node("Lumberjack" if kind == &"tree" else "Miner")
		if kind == &"clay":
			check(world.debug_spawn.spawn_clay_deposit(Vector3(-17, 0, 16)).ok, "Use existing debug fixture API for a real clay deposit")
		var source: RefCounted = world.trees[0] if kind == &"tree" else first_work.rocks.filter(func(rock): return rock.resource_type == (resources.STONE if kind == &"stone" else resources.CLAY))[0]
		var area: RefCounted = world.work_areas.create(source.position, 100.0)
		check(world.player_control.assign_work_area(first.data.id, area.id) and first_work.request_work(), "Actual free extraction starts: " + kind)
		F.walk(world, first)
		if kind == &"tree": source = first_work.tree
		else: source = first_work.rock
		world.game_time.debug_skip_minutes(59)
		check(source.work_done == 59, "No acceleration of actual extraction time")
		first_work.abort(false)
		var primary: int = S.FORESTRY if kind == &"tree" else S.MINING
		check(first.data.get_skill_xp(primary) == 0, "Interrupted extractor receives no contribution XP")
		world.player_control.assign_profession(first.data.id, professions.NONE)
		for other in world.trees if kind == &"tree" else first_work.rocks:
			if other != source: other.claim(&"handoff_fixture")
		world.player_control.assign_profession(last.data.id, profession)
		world.player_control.assign_work_area(last.data.id, area.id)
		var last_work: Node = last.get_node("Lumberjack" if kind == &"tree" else "Miner")
		check(last_work.request_work(), "Different worker claims remaining extraction")
		check((last_work.tree if kind == &"tree" else last_work.rock) == source, "Same persistent target, not a fresh task")
		F.walk(world, last)
		last.data.skill_changed.connect(func(_skill, _amount, _previous):
			last_work._minute(world.game_time.total_minutes)
			last_work.abort(false), CONNECT_ONE_SHOT)
		world.game_time.debug_skip_minutes(1)
		check(first.data.get_skill_xp(primary) == 0 and last.data.get_skill_xp(primary) == 8 and last.data.get_skill_xp(S.GATHERING) == 0, "Full reward belongs to the extractor finishing the last minute")
		check(last.data.get_skill_xp(S.WOODWORKING) == (2 if kind == &"tree" else 0) and last.data.get_skill_xp(S.STONEWORKING) == (2 if kind == &"stone" else 0), "Only approved secondary skill is awarded")
		last_work._minute(world.game_time.total_minutes)
		check(last.data.get_skill_xp(primary) == 8, "Repeated/nested extraction completion cannot award twice")
		world.free()
		await process_frame
