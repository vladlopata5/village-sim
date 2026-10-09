extends SceneTree
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Builder = preload("res://scripts/resident_builder_controller.gd")
const RecipeWork = preload("res://scripts/resident_recipe_controller.gd")
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func place(world: Node, category: int, point: Vector3):
	world.placement.select(Definition.for_type(category))
	world.placement.update_world_position(point)
	return world.placement.confirm()
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(12000):
		actor.view._physics_process(0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id != reason: break
		if not actor.view.movement.is_moving(): break
func work_minutes(world: Node, actor: Node, minutes: int) -> void:
	for minute in range(minutes):
		world.game_time.total_minutes += 1
		actor.builder._on_minute(world.game_time.total_minutes)
func construct(world: Node, actor: Node, category: int, point: Vector3):
	var site = place(world,category,point)
	check(site != null,"Ordinary placement creates real construction")
	for cycle in range(site.definition.construction_work_required / Balance.BUILDER_WORK_CYCLE_MINUTES):
		check(world._request_work(actor),"Ordinary Builder work request")
		walk(actor)
		check(actor.builder.phase == Builder.Phase.BUILDING,"Physical material trips reach work phase")
		work_minutes(world,actor,Balance.BUILDER_WORK_CYCLE_MINUTES)
	check(site.is_built(),"Actual delivered PLANK plus actual work completes construction")
	return site
func run() -> void:
	check(not preload("res://scripts/resource_type.gd").Type.has("WOOD"),"Dead WOOD resource removed")
	for category in Types.values():
		var definition = Definition.for_type(category)
		var small: bool = category in [Types.HOME,Types.GATHERER_HUT,Types.LUMBERJACK_HUT]
		check(definition.construction_requirements == {Resources.PLANK:10 if small else 15},"Every current type uses original amount in PLANK")
	var synthetic = Definition.for_type(Types.HOME)
	synthetic.construction_requirements = {Resources.PLANK:2,Resources.FOOD:1}
	var site = Instance.new(&"multi_resource",synthetic,Vector2.ZERO,Instance.State.UNDER_CONSTRUCTION)
	check(site.reserve_construction_material(Resources.PLANK,2) and site.reserve_construction_material(Resources.FOOD,1),"Independent inbound reservations for multiple materials")
	check(site.deliver_reserved_construction_material(Resources.PLANK,2) and not site.are_construction_materials_complete(),"First material alone cannot complete set")
	check(site.deliver_reserved_construction_material(Resources.FOOD,1) and site.are_construction_materials_complete(),"Second material completes generic requirements")
	site.add_construction_work(synthetic.construction_work_required)
	check(site.complete_construction(),"Multi-resource completion uses existing lifecycle")
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes = 420
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.schedule._phase = "День"
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value = 0
	var storage = world.warehouse_data.resources
	var hut_cost: int = Definition.for_type(Types.LUMBERJACK_HUT).construction_requirements[Resources.PLANK]
	var saw_cost: int = Definition.for_type(Types.SAWMILL).construction_requirements[Resources.PLANK]
	var starting: int = Balance.starter_plank_amount(hut_cost,saw_cost)
	check(storage.get_amount(Resources.PLANK) == starting and starting == hut_cost+saw_cost+Balance.STARTER_PLANK_RESERVE,"Bootstrap derives from current definitions and explicit reserve")
	check(starting >= hut_cost+saw_cost and starting <= storage.get_capacity(Resources.PLANK),"Bootstrap sufficient and physically fits Storage")
	check(storage.get_amount(Resources.FOOD)==10 and storage.get_amount(Resources.LOG)==0,"FOOD unchanged, no starter LOG")
	var builder = world.resident_runtimes[2]
	world.player_control.assign_profession(builder.data.id,Profession.BUILDER)
	var hut = construct(world,builder,Types.LUMBERJACK_HUT,Vector3(-20,0,-8))
	var saw = construct(world,builder,Types.SAWMILL,Vector3(-12,0,-14))
	check(storage.get_amount(Resources.PLANK)==Balance.STARTER_PLANK_RESERVE,"Hut and Sawmill consume actual bootstrap stock")
	# Hold one remaining starter unit aside: the final delivered unit must come from production.
	check(storage.reserve_out(Resources.PLANK,1),"Isolate one starter unit with ordinary reservation")
	var home = place(world,Types.HOME,Vector3(4,0,14))
	check(world._request_work(builder),"New House consumes available starter remainder")
	walk(builder)
	check(home.get_delivered_amount(Resources.PLANK)==Balance.STARTER_PLANK_RESERVE-1 and not home.are_construction_materials_complete() and builder.builder.phase==Builder.Phase.NONE,"Nine physical deliveries stop without available tenth PLANK")
	var lumber = world.resident_runtimes[3]
	var sawyer = world.resident_runtimes[1]
	world.player_control.assign_workplace(lumber.data.id,hut.id)
	world.player_control.assign_workplace(sawyer.data.id,saw.id)
	check(world._request_work(lumber),"Normal WORK chooses actual tree")
	walk(lumber)
	world.game_time.debug_skip_minutes(60)
	check(world.ground_resources.drops.size()==3,"Tree yields three actual LOG")
	for trip in range(3):
		check(world._request_work(lumber),"Normal local LOG collection")
		walk(lumber,&"collect_log")
		walk(lumber)
	check(hut.resources.get_amount(Resources.LOG)==3,"Physical Ground LOG reaches hut")
	world.trees.clear() # Isolate fallback export from more chopping/planting in this fixture.
	hut.definition.target_tree_count = 0
	check(world._request_work(lumber),"Fallback export starts through shared haul execution")
	walk(lumber,&"haul_source")
	walk(lumber)
	check(saw.resources.get_amount(Resources.LOG)==1,"Physical LOG export supplies Sawmill")
	check(world._request_work(sawyer),"Normal WORK reserves recipe input/output")
	check(saw.resources.get_reserved_out(Resources.LOG)==1 and saw.resources.get_reserved_in(Resources.PLANK)==1,"Existing recipe reservation semantics unchanged")
	walk(sawyer)
	check(sawyer.recipe_work.phase==RecipeWork.Phase.WORKING,"Sawyer arrives physically before work")
	for minute in range(30):
		world.game_time.total_minutes += 1
		sawyer.recipe_work._on_minute(world.game_time.total_minutes)
	check(saw.resources.get_amount(Resources.PLANK)==1 and saw.resources.get_amount(Resources.LOG)==0,"Unchanged 1 LOG to 1 PLANK in thirty work-minutes")
	check(storage.get_available_amount(Resources.PLANK)==0,"Storage has no available unit before Porter delivery")
	# Keep normal Porter candidate choice focused on the produced output.
	hut.resources.try_take(Resources.LOG,2)
	storage.try_take(Resources.FOOD,10)
	var porter = world.resident_runtimes[0]
	check(world._request_work(porter),"Own-base Porter claims produced PLANK")
	var job = world.logistics.get_job(porter.data.id)
	check(job.resource_type==Resources.PLANK and job.source_location_id==saw.id and job.destination_location_id==world.warehouse_data.id,"Production output route ends at assigned Storage")
	walk(porter,&"haul_source")
	walk(porter)
	check(storage.get_available_amount(Resources.PLANK)==1 and saw.resources.get_amount(Resources.PLANK)==0,"Produced unit physically reaches Storage")
	# Start a fresh WORK window: fixture elapsed work must not become an evening request.
	world.game_time.total_minutes = 420
	for cycle in range(home.definition.construction_work_required / Balance.BUILDER_WORK_CYCLE_MINUTES):
		check(world._request_work(builder),"Builder resumes ordinary House construction")
		walk(builder)
		check(builder.builder.phase==Builder.Phase.BUILDING,"Produced material delivery starts construction work")
		work_minutes(world,builder,Balance.BUILDER_WORK_CYCLE_MINUTES)
	check(home.is_built() and home.get_delivered_amount(Resources.PLANK)==10,"Last House requires and consumes physically produced PLANK")
	check(storage.get_amount(Resources.PLANK)==1 and storage.get_reserved_out(Resources.PLANK)==1,"Held starter unit was never used for final construction delivery")
	storage.release_out(Resources.PLANK,1)
	world.free()
	print("Construction economy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
