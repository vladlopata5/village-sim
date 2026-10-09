extends SceneTree
const Definitions = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const RecipeWork = preload("res://scripts/resident_recipe_controller.gd")
const Fixture = preload("res://tests/forestry_fixture.gd")
const ResourceBox = preload("res://scripts/resource_container.gd")
const TreeData = preload("res://scripts/tree_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func scene() -> Node:
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
	return world
func place(world: Node, point: Vector3 = Vector3(4,0,14)):
	world.placement.select(Definitions.for_type(Types.SAWMILL))
	world.placement.update_world_position(point)
	world.placement.rotate()
	return world.placement.confirm()
func finish(target: RefCounted) -> void:
	target.add_delivered_material(Resources.WOOD,target.get_required_amount(Resources.WOOD))
	target.add_construction_work(target.definition.construction_work_required)
	check(target.complete_construction(),"Existing construction completes same instance")
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(2000):
		actor.view._physics_process(0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id != reason: break
		if not actor.view.movement.is_moving(): break
func begin(world: Node, actor: Node) -> void:
	check(world._request_work(actor),"Normal workplace WORK request starts recipe")
	check(actor.recipe_work.phase == RecipeWork.Phase.GOING_TO_WORK,"Work starts with physical trip")
	walk(actor)
	check(actor.recipe_work.phase == RecipeWork.Phase.WORKING,"Physical access arrival starts actual work")
func minute(world: Node, actor: Node, amount: int) -> void:
	for tick in range(amount):
		world.game_time.total_minutes += 1
		actor.recipe_work._on_minute(world.game_time.total_minutes)
func run() -> void:
	var world = scene()
	var saw = place(world)
	var actor = world.resident_runtimes[1]
	check(preload("res://scripts/resource_type.gd").display_name(Resources.PLANK)=="Доски","PLANK exists/display name")
	check(saw.definition.footprint_cells==Vector2i(12,8) and saw.quarter_turns==1,"12x8 build cells, normal quarter-turn placement")
	check(world.build_grid.occupied_cells(saw.id).size()==96 and not world.navigation.is_world_walkable(Coordinates.to_world(saw.position)),"Construction occupies footprint and navigation immediately")
	check(not world.player_control.assign_workplace(actor.data.id,saw.id),"UNDER_CONSTRUCTION cannot employ Sawyer")
	check(saw.definition.worker_capacity==1 and saw.get_required_amount(Resources.WOOD)==15,"Single-worker ordinary construction WOOD balance")
	var recipe: RefCounted = saw.definition.production_recipe
	check(recipe.inputs=={Resources.LOG:1} and recipe.outputs=={Resources.PLANK:1} and recipe.work_required==30,"Recipe is data: 1 LOG -> 1 PLANK /30 actual work-minutes")
	finish(saw)
	check(saw.resources.get_capacity(Resources.LOG)==12 and saw.resources.get_capacity(Resources.PLANK)==12,"Separate input/output buffers use existing per-resource capacity")
	check(not saw.resources.allows_resource(Resources.FOOD) and not saw.resources.allows_resource(Resources.WOOD),"Only LOG/PLANK functional storage, WOOD remains construction-only")
	check(world.player_control.assign_workplace(actor.data.id,saw.id) and actor.data.profession==Profession.SAWYER,"Player workplace API assigns SAWYER to exact built sawmill")
	check(not world.player_control.assign_workplace(world.resident_runtimes[2].data.id,saw.id),"Second Sawyer rejected")
	check(preload("res://scripts/resident_profession.gd").display_name(Profession.SAWYER)=="Пильщик","Existing profession UI label")
	check(not world._work_available(actor) and not actor.recipe_work.request_work(),"No input means no fake WORK")
	var hut = Fixture.hut(world)
	var second_hut = Fixture.hut(world,&"hut_b",Vector3(-20,0,-2))
	check(world.logistics.allows_external_delivery(hut,saw,Resources.LOG),"Hut LOG -> Sawmill allowed")
	check(world.logistics.allows_external_delivery(world.warehouse_data,saw,Resources.LOG),"Storage LOG -> Sawmill allowed")
	check(not world.logistics.allows_external_delivery(saw,world.warehouse_data,Resources.LOG),"Sawmill LOG external export forbidden")
	check(not world.logistics.allows_external_delivery(world.warehouse_data,saw,Resources.PLANK),"Sawmill PLANK external import forbidden")
	check(world.logistics.allows_external_delivery(saw,world.warehouse_data,Resources.PLANK),"Sawmill local PLANK -> Storage allowed")
	check(not world.logistics.allows_external_delivery(hut,second_hut,Resources.LOG),"Two-hut policy regression")
	saw.resources.add(Resources.LOG,3)
	check(world._work_available(actor) and actor.decision.collect_actions(true).any(func(row): return row.id=="WORK" and row.priority==7000),"SAWYER participates in normal WORK category")
	begin(world,actor)
	check(saw.resources.get_amount(Resources.LOG)==3 and saw.resources.get_reserved_out(Resources.LOG)==1 and saw.resources.get_reserved_in(Resources.PLANK)==1,"Start protects input and output capacity without consumption")
	check(not world.resident_runtimes[2].recipe_work.has_work(),"Recipe cannot have second owner")
	minute(world,actor,15)
	check(saw.production_progress==15 and saw.resources.get_amount(Resources.PLANK)==0,"15 actual minutes preserve incomplete recipe")
	actor.commands.move_to(Vector2(0,500))
	check(saw.production_progress==15 and saw.resources.get_amount(Resources.LOG)==3 and saw.resources.get_reserved_out(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0,"PlayerCommand releases both reservations; partial work/input preserved")
	actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
	begin(world,actor)
	minute(world,actor,15)
	check(saw.production_progress==0 and saw.resources.get_amount(Resources.LOG)==2 and saw.resources.get_amount(Resources.PLANK)==1,"Resumed 15 minutes complete exactly one recipe")
	check(saw.production_worker_id.is_empty() and not actor.intents.has_current_action(),"Completion releases owner and creates normal decision boundary")
	for cycle in range(2):
		begin(world,actor)
		minute(world,actor,30)
	check(saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_amount(Resources.PLANK)==3 and saw.resources.get_reserved_out(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0,"Three cycles consume3/produce3 without leaked reservations")
	check(not actor.recipe_work.has_work(),"No-input state stops naturally")
	saw.resources.add(Resources.LOG,1)
	saw.resources.add(Resources.PLANK,9)
	check(not actor.recipe_work.has_work() and not actor.recipe_work.request_work() and saw.resources.get_amount(Resources.LOG)==1,"Full output prevents work, protects input")
	saw.resources.try_take(Resources.PLANK,1)
	check(actor.recipe_work.has_work(),"Capacity event exposes work again")
	begin(world,actor)
	minute(world,actor,7)
	actor.decision._deciding=false
	actor.data.fatigue=100
	check(actor.recipe_work.phase==RecipeWork.Phase.NONE and saw.production_progress==7 and saw.resources.get_reserved_out(Resources.LOG)==0,"Critical interrupt preserves work/releases input")
	actor.decision._deciding=true
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.fatigue=0
	begin(world,actor)
	minute(world,actor,8)
	world.game_time.total_minutes=1020
	world.game_time.phase_changed.emit("Вечер")
	check(actor.recipe_work.phase==RecipeWork.Phase.NONE and saw.resources.get_reserved_in(Resources.PLANK)==0 and saw.production_progress==15,"Schedule end releases task, preserves partial progress")
	check(not actor.recipe_work.request_work(),"No production after WORK phase")
	world.resident_selection.select_building(saw)
	var card = world.get_node("HUD/BuildingCard")
	card._refresh()
	check("Бревно" in card.resources_label.text and "Доски" in card.resources_label.text and "Анна" in card.resources_label.text and "15 / 30" in card.production_label.text,"Existing card shows storage, Sawyer and progress")
	world.free()

	# Real event-driven normal AI, no forced WORK and no retry polling.
	world = scene()
	saw = place(world)
	finish(saw)
	actor = world.resident_runtimes[1]
	world.player_control.assign_workplace(actor.data.id,saw.id)
	actor.wander.target_provider = Callable()
	actor.decision._deciding = false
	actor.decision.request_decision("empty_recipe")
	check(not actor.intents.has_current_action(),"No input permits ordinary idle/personal decision without hanging work")
	saw.resources.add(Resources.LOG,1)
	await process_frame
	check(actor.recipe_work.phase==RecipeWork.Phase.GOING_TO_WORK and actor.decision.last_selection.candidates.any(func(row): return row.id=="WORK"),"Input availability event triggers normal UtilitySelector WORK")
	walk(actor)
	actor.decision._deciding = true
	minute(world,actor,30)
	saw.resources.add(Resources.LOG,1)
	saw.resources.add(Resources.PLANK,11)
	await process_frame
	check(not actor.recipe_work.has_work(),"Full output forbids a new candidate")
	actor.decision._deciding = false
	saw.resources.try_take(Resources.PLANK,1)
	await process_frame
	check(actor.recipe_work.phase==RecipeWork.Phase.GOING_TO_WORK,"Released output capacity event starts ordinary WORK again")
	walk(actor)
	actor.decision._deciding = true
	world.player_control.assign_profession(actor.data.id,Profession.NONE)
	minute(world,actor,30)
	check(saw.resources.get_amount(Resources.LOG)==0 and not actor.recipe_work.has_work(),"Profession change finishes safe recipe but cannot begin another")
	world.free()

	# Storage-owned outbound LOG uses the same physical Porter executor.
	world = scene()
	saw = place(world)
	finish(saw)
	var outbound = world.resident_runtimes[0]
	world.warehouse_data.resources.try_take(Resources.FOOD,10)
	world.warehouse_data.resources.add(Resources.LOG,1)
	check(world._request_work(outbound),"Own Storage Porter claims LOG outbound to Sawmill")
	var outgoing = world.logistics.get_job(outbound.data.id)
	check(outgoing.source_location_id==world.warehouse_data.id and outgoing.destination_location_id==saw.id and outgoing.resource_type==Resources.LOG,"Porter outbound uses its own workplace source")
	walk(outbound,&"haul_source")
	walk(outbound)
	check(world.warehouse_data.resources.get_amount(Resources.LOG)==0 and saw.resources.get_amount(Resources.LOG)==1,"Physical Storage LOG reaches Sawmill")
	actor = world.resident_runtimes[1]
	world.player_control.assign_workplace(actor.data.id,saw.id)
	begin(world,actor)
	# Force interrupt inside synchronous completion callbacks: conversion must remain atomic.
	saw.resources.changed.connect(func(resource,amount):
		if resource==Resources.LOG and amount==0: actor.commands.move_to(Vector2(0,500)))
	minute(world,actor,30)
	check(saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_amount(Resources.PLANK)==1 and saw.production_progress==0,"Interrupt inside completion cannot duplicate/lose output")
	check(actor.commands.active_command!=null and saw.production_worker_id.is_empty() and saw.resources.get_reserved_in(Resources.PLANK)==0 and saw.resources.get_reserved_out(Resources.LOG)==0,"Atomic completion preserves PlayerCommand and cleans recipe ownership")
	world.free()

	# Atomic transformation exposes only complete ledgers, even to synchronous interruptions.
	var box = ResourceBox.new(&"recipe_atomic")
	box.set_capacity(Resources.LOG,2)
	box.set_capacity(Resources.PLANK,2)
	box.add(Resources.LOG,1)
	box.reserve_out(Resources.LOG,1)
	box.reserve_in(Resources.PLANK,1)
	box.changed.connect(func(_resource,_amount): check(box.get_amount(Resources.LOG)==0 and box.get_amount(Resources.PLANK)==1,"Synchronous callback never sees half-consumed recipe"))
	check(box.transform_reserved({Resources.LOG:1},{Resources.PLANK:1}),"Local atomic reservation conversion succeeds")
	check(not box.transform_reserved({Resources.LOG:1},{Resources.PLANK:1}),"Same reservations cannot convert twice")

	# Full forestry chain with real tree, three collection trips, export and Porter delivery.
	world = scene()
	hut = Fixture.hut(world)
	saw = place(world,Vector3(-12,0,-14))
	finish(saw)
	actor = world.resident_runtimes[1]
	var lumber = world.resident_runtimes[3]
	var forestry = lumber.get_node("Lumberjack")
	world.player_control.assign_workplace(lumber.data.id,hut.id)
	world.player_control.assign_workplace(actor.data.id,saw.id)
	check(forestry.request_work(),"Real forestry CHOP request")
	var tree: RefCounted = forestry.tree
	walk(lumber)
	world.game_time.debug_skip_minutes(60)
	check(tree.state==TreeData.State.DEPLETED and world.ground_resources.drops.size()==3,"One tree yields3 Ground LOG")
	for trip in range(3):
		check(forestry.request_work(),"Collect LOG through own-hut workflow")
		walk(lumber,&"collect_log")
		walk(lumber)
	check(hut.resources.get_amount(Resources.LOG)==3,"Three physical ground trips reach hut")
	world.trees.clear() # Isolate export after harvesting; no more chop/plant candidates.
	hut.definition.target_tree_count=0
	check(forestry.best_task().kind==&"EXPORT" and forestry.best_task().destination==saw,"Fallback chooses nearby Sawmill destination")
	check(forestry.request_work(),"Existing Lumberjack export starts")
	walk(lumber,&"haul_source")
	walk(lumber)
	check(saw.resources.get_amount(Resources.LOG)==1,"Real export physically supplies Sawmill")
	begin(world,actor)
	minute(world,actor,30)
	check(saw.resources.get_amount(Resources.PLANK)==1,"Forestry LOG becomes local PLANK")
	var second_storage = preload("res://scripts/building_instance.gd").new(&"storage_b",Definitions.for_type(Types.STORAGE),Coordinates.to_sim(Vector3(28,0,18)))
	world.buildings.append(second_storage)
	world._show_building(second_storage)
	check(not world.logistics.allows_external_delivery(world.warehouse_data,second_storage,Resources.PLANK),"Storage->Storage PLANK remains forbidden")
	var porter = world.resident_runtimes[0]
	hut.resources.try_take(Resources.LOG,2)
	world.warehouse_data.resources.try_take(Resources.FOOD,10)
	check(world._request_work(porter),"Own-storage Porter claims produced PLANK")
	var job = world.logistics.get_job(porter.data.id)
	check(job.resource_type==Resources.PLANK and job.source_location_id==saw.id and job.destination_location_id==world.warehouse_data.id,"Porter endpoint stays own Storage")
	walk(porter,&"haul_source")
	walk(porter)
	check(saw.resources.get_amount(Resources.PLANK)==0 and world.warehouse_data.resources.get_amount(Resources.PLANK)==1,"Physical PLANK delivery reaches Storage")
	world.free()
	print("Sawmill: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
