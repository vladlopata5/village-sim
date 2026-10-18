extends SceneTree
const Categories = preload("res://scripts/resource_category.gd").Type
const Stacks=preload("res://tests/ground_stack_fixture.gd")
## Real canonical extraction and construction; no debug/resource spawn.
const Def = preload("res://scripts/building_definition.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Phase = preload("res://scripts/resident_builder_controller.gd").Phase
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
var world: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(16000):
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving(): break
func window() -> void: world.game_time.total_minutes = 420
func screenshot(label: String) -> void:
	if not "--rendered" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/construction-recipes-update/" + label + ".png") == OK,"Rendered capture " + label)
func construct(actor: Node, category: int, point: Vector3):
	window()
	world.placement.select(Def.for_type(category))
	world.placement.update_world_position(point)
	var site = world.placement.confirm()
	check(site != null,"Normal BuildGrid placement succeeds")
	if site == null: return null
	world.resident_selection.select_building(site)
	await screenshot("%s_initial" % site.definition.id)
	for cycle in range(8):
		if site.is_built(): break
		window()
		check(world._request_work(actor),"Normal Builder WORK uses physical resources")
		for leg in range(40):
			if actor.builder.phase not in [Phase.GOING_TO_SOURCE,Phase.CARRYING_TO_SITE]: break
			window()
			walk(actor)
		walk(actor)
		check(actor.builder.phase == Phase.BUILDING,"Actual delivery and access-point arrival start work")
		world.game_time.debug_skip_minutes(10)
		check(site.construction_progress == mini(cycle*60+10,site.definition.construction_work_required),"Incremental work unchanged")
		await screenshot("%s_work_%d" % [site.definition.id,cycle])
		world.game_time.debug_skip_minutes(50)
	check(site.is_built(),"Exact actual materials plus actual work complete construction")
	await screenshot("%s_built" % site.definition.id)
	return site
func run() -> void:
	world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
	await physics_frame
	var center = world.warehouse_data
	check(center.resources.get_amount(R.PLANK) == 60 and center.resources.get_amount(R.FOOD) == 20 and center.resources.get_amount(R.LOG) == 0 and center.resources.get_amount(R.STONE) == 0,"Canonical starter stock unchanged")
	check(center.resources.reserve_out(R.PLANK,60),"Hold existing boards to prove manufacturing dependency")
	var lumber = world.resident_runtimes[3]
	var miner = world.resident_runtimes[2]
	var builder = world.resident_runtimes[1]
	check(world.player_control.assign_profession(lumber.data.id,P.LUMBERJACK),"Free Lumberjack assigned through PlayerControl")
	var forest = world.work_areas.create(C.to_sim(Vector3(-30,0,-9)),C.length_to_sim(15))
	check(world.player_control.assign_work_area(lumber.data.id,forest.id),"Starter forest area assigned")
	for cycle in range(5):
		window()
		check(world._request_work(lumber),"Normal FREE forestry WORK")
		walk(lumber)
		world.game_time.debug_skip_minutes(Balance.TREE_WORK_MINUTES)
	check(Stacks.total(world.ground_resources,R.LOG) == 15 and lumber.data.inventory.amount == 0,"Five natural trees yield fifteen Ground LOG")
	check(world.player_control.assign_profession(miner.data.id,P.MINER),"Free Miner assigned through PlayerControl")
	var quarry = world.work_areas.create(C.to_sim(Vector3(30,0,-9)),C.length_to_sim(15))
	check(world.player_control.assign_work_area(miner.data.id,quarry.id),"Starter rocks area assigned")
	for cycle in range(10):
		window()
		check(world._request_work(miner),"Normal FREE mining WORK")
		walk(miner)
		world.game_time.debug_skip_minutes(Balance.ROCK_WORK_MINUTES)
	check(Stacks.total(world.ground_resources,R.STONE) == 10 and miner.data.inventory.amount == 0,"Ten real Ground STONE from starter rock")
	# The approved local rule requires fetching remote extraction output first.
	# Ordinary player movement brings the Porter into its resident search circle;
	# the same real haul then deposits each unit in the globally available container.
	var porter = world.resident_runtimes[0]
	for drop in world.ground_resources.drops.duplicate():
		for unit in range(drop.amount):
			if center.resources.get_available_free_capacity(drop.resource_type)<1: break
			window()
			porter.commands.move_to(drop.world_position)
			walk(porter)
			check(world._request_work(porter),"Nearby Porter claims actual extraction output")
			walk(porter); walk(porter)
	check(center.resources.get_amount(R.LOG)==10 and center.resources.get_amount(R.STONE)==10 and Stacks.total(world.ground_resources,R.LOG)==5,"Initial quotas and total 100 preserve the remaining five logs on the ground")
	check(world.player_control.assign_profession(builder.data.id,P.BUILDER),"Builder assigned normally")
	var saw = await construct(builder,T.SAWMILL,Vector3(-10,0,16))
	if saw == null:
		world.free()
		quit(1)
		return
	check(saw.construction_delivered == {R.LOG:6,R.STONE:6} and center.resources.get_amount(R.PLANK) == 60,"Sawmill consumes six LOG/six STONE, no boards")
	# Construction frees physical room; redistribute quota and fetch the remaining
	# extraction output before manufacturing. Preserve every unit, including FOOD.
	check(center.resources.set_category_quotas({Categories.LOG:15,Categories.STONE:4,Categories.PLANK:61}),"Reallocate shared quota after consuming construction materials")
	check(saw.resources.reserve_in(R.LOG,12),"Hold Sawmill input while isolating the remaining Ground collection")
	for drop in world.ground_resources.drops.duplicate():
		for unit in range(drop.amount):
			window()
			porter.commands.move_to(drop.world_position)
			walk(porter)
			check(world._request_work(porter),"Nearby Porter claims remaining extraction output after room is freed")
			walk(porter); walk(porter)
	check(saw.resources.release_in(R.LOG,12),"Release the controlled input hold")
	check(center.resources.get_amount(R.LOG)==9 and center.resources.get_amount(R.STONE)==4 and world.ground_resources.drops.is_empty() and center.resources.get_amount(R.FOOD)==20,"All extracted units accounted for after construction, without consuming starting FOOD")
	check(world.player_control.assign_workplace(miner.data.id,saw.id),"Sawyer assigned to physically constructed Sawmill")
	for cycle in range(6):
		window()
		check(world._request_work(miner),"Sawyer normal self-supply")
		walk(miner)
		check(world._request_work(miner),"Sawyer normal production")
		walk(miner)
		world.game_time.debug_skip_minutes(Balance.SAWMILL_WORK_MINUTES)
	check(saw.resources.get_amount(R.PLANK) == 6,"Six real LOG become six PLANK")
	check(center.resources.set_category_quotas({Categories.LOG:10,Categories.PLANK:66}),"Allocate room for all six manufactured boards without exceeding total capacity")
	# Hold remaining timber for the next construction fixture, just as starter
	# PLANK is held above; ordinary Porter input supply must not consume that fixture stock.
	var held_logs: int = center.resources.get_available_amount(R.LOG)
	check(center.resources.reserve_out(R.LOG,held_logs),"Hold next construction timber during board export")
	for trip in range(20):
		if center.resources.get_amount(R.PLANK) == 66: break
		window()
		check(world._request_work(porter),"Own Town Center Porter chooses normal Ground/output delivery")
		walk(porter)
	check(center.resources.get_amount(R.PLANK) == 66 and saw.resources.get_amount(R.PLANK) == 0,"Porter physically delivers all six manufactured boards to Town Center")
	center.resources.release_out(R.LOG,held_logs)
	await screenshot("manufactured_boards_delivered")
	var storage = await construct(builder,T.STORAGE,Vector3(4,0,22))
	if storage != null:
		check(storage.construction_delivered == {R.LOG:2,R.STONE:4,R.PLANK:6},"Storage exact mixed recipe physically delivered")
		check(saw.resources.get_amount(R.PLANK) == 0 and center.resources.get_amount(R.PLANK) == 60 and center.resources.get_reserved_out(R.PLANK) == 60,"Storage uses manufactured boards, not starter stock")
		check(center.resources.get_amount(R.LOG) + world.ground_resources.drops.filter(func(drop): return drop.resource_type == R.LOG).reduce(func(total,drop): return total + drop.amount,0) == 1 and center.resources.get_amount(R.STONE) + world.ground_resources.drops.filter(func(drop): return drop.resource_type == R.STONE).reduce(func(total,drop): return total + drop.amount,0) == 0,"Conservation: 15 LOG minus 6 build/6 production/2 Storage leaves one; all ten STONE used")
		check(world.resident_runtimes.all(func(actor): return actor.data.inventory.amount == 0),"No lost/duplicated cargo")
	center.resources.release_out(R.PLANK,60)
	world.free()
	print("Construction economy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
