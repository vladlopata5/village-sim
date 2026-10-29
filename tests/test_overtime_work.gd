extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Trait = preload("res://scripts/trait_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const S = preload("res://scripts/skill_type.gd").Type
const Intent = preload("res://scripts/resident_intent.gd")
var checks := 0
var failures := 0
var starts := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func phase(world: Node, minute: int) -> void:
	world.game_time.total_minutes=minute
	for actor in world.resident_runtimes:
		actor.schedule._on_phase_changed(world.game_time.get_phase())
func prepare(world: Node) -> Node:
	var actor: Node=world.resident_runtimes[0]
	actor.data.traits.clear();actor.data.add_trait(Trait.INDUSTRIOUS)
	actor.wander.target_available=func():return false
	actor.decision.overtime_started.connect(func(_intent):starts+=1)
	return actor
func choose(actor: Node) -> void:
	actor.decision._deciding=false
	actor.decision._decide_now()
	actor.decision._deciding=true
func walk(actor: Node, ready: Callable) -> void:
	for step in 20000:
		if ready.call():return
		if actor.view._resume_after_frame==Engine.get_physics_frames():
			await physics_frame;await process_frame
		actor.view._physics_process(0.05)
	check(false,"Physical worker reaches its accepted target")
func sawmill(world: Node) -> RefCounted:
	var building: RefCounted=F.building(world,T.SAWMILL,Vector3(-10,0,16))
	building.resources.add(R.LOG,4)
	return building
func offered(actor: Node) -> bool:
	return actor.decision.collect_actions(false).any(func(row):return row.id=="OVERTIME_WORK")
func run() -> void:
	await availability_and_needs()
	await recipe_lifecycle()
	await structural_lifecycle()
	await extraction_and_fields()
	await carrier()
	await recipe_catalog()
	await shepherd()
	await stale_admission()
	await critical_interruptions()
	await natural_gathering_and_planting()
	await sowing_group()
	await builder_materials()
	print("Overtime work: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func availability_and_needs() -> void:
	var world:=F.create(self);var actor:=prepare(world);var place:=sawmill(world)
	world.player_control.assign_workplace(actor.data.id,place.id)
	for traits in [[],[Trait.LAZY],[Trait.INDUSTRIOUS]]:
		actor.data.traits.clear()
		for trait_type in traits:actor.data.add_trait(trait_type)
		for minute in [359,360,419,420,1019,1020,1379,1380]:
			phase(world,minute)
			var wanted: bool=traits==[Trait.INDUSTRIOUS] and minute in [360,419,1020,1379]
			check(offered(actor)==wanted,"Trait and phase bounds select exactly morning/evening")
			check(not actor.intents.overtime_admission and not actor.intents.has_current_action() and place.resources.get_reserved_out(R.LOG)==0 and place.resources.get_reserved_in(R.PLANK)==0 and place.production_batches.is_empty(),"Availability probe never leaves authorization or claims")
	phase(world,1020)
	actor.data.traits.clear();actor.data.add_trait(Trait.INDUSTRIOUS)
	check(not actor.recipe_work.request_work(),"Industrious cannot bypass the normal off-shift start gate")
	actor.data.get_need(preload("res://scripts/need_type.gd").Type.FATIGUE).base_weight=100
	actor.data.fatigue=90;choose(actor)
	check(actor.intents.current_intent.reason_id==&"rest" and not actor.intents.current_intent.overtime_work,"High fatigue REST excludes medium overtime from the selector")
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.fatigue=100;actor.decision._deciding=false;actor.decision.check_critical();actor.decision._deciding=true
	check(actor.intents.forced_priority>0 and actor.intents.current_intent.reason_id==&"critical_sleep" and not actor.intents.current_intent.overtime_work,"Critical fatigue keeps immediate forced sleep")
	world.free();await process_frame
	world=F.create(self);actor=prepare(world);place=sawmill(world)
	world.player_control.assign_workplace(actor.data.id,place.id);phase(world,1020)
	var before:=starts
	actor.decision.work_request=func():return false
	choose(actor)
	check(starts==before and not actor.intents.has_current_action() and not actor.intents.overtime_admission,"Invalidated work is not a successful start and leaves no permission")
	world.free();await process_frame
	world=F.create(self);actor=prepare(world);phase(world,1020)
	world.player_control.assign_profession(actor.data.id,P.NONE)
	check(not offered(actor),"No available ordinary job means no overtime candidate")
	world.free();await process_frame

func recipe_lifecycle() -> void:
	for minute in [360,410,1020,1370]:
		var world:=F.create(self);var actor:=prepare(world);var place:=sawmill(world)
		world.player_control.assign_workplace(actor.data.id,place.id);phase(world,minute)
		var before:=starts
		choose(actor)
		check(starts==before+1 and actor.intents.current_intent.overtime_work,"Normal utility selection accepts one real recipe task")
		await walk(actor,func():return actor.recipe_work.phase==actor.recipe_work.Phase.WORKING)
		var batch: RefCounted=actor.recipe_work.batch
		world.game_time.debug_skip_minutes(29)
		check(batch.progress==29 and place.resources.get_amount(R.PLANK)==0,"Overtime uses the unchanged skill rate and recipe progress")
		world.game_time.debug_skip_minutes(1)
		check(batch.is_terminal() and place.resources.get_amount(R.PLANK)==1 and actor.data.get_skill_xp(S.WOODWORKING)==3 and actor.data.get_skill_xp(S.CRAFTING)==1,"One real batch, unchanged multi-skill XP")
		check(not actor.intents.has_current_action() and not actor.intents.overtime_admission,"Completed task ends the permission")
		choose(actor)
		if world.game_time.get_phase() in ["Утро","Вечер"]:
			check(starts==before+2 and actor.intents.current_intent.overtime_work,"A second overtime selection has no cooldown or daily quota")
		elif world.game_time.get_phase()=="День":
			check(starts==before+1 and not actor.intents.current_intent.overtime_work,"After morning task normal shift selection resumes")
		else:
			check(starts==before+1 and actor.intents.current_intent.reason_id in [&"night_home",&"night_outdoor"] and not actor.intents.current_intent.overtime_work,"Night waits for accepted work, then normal sleep wins")
		world.free();await process_frame

func structural_lifecycle() -> void:
	var world:=F.create(self);var actor:=prepare(world)
	var definition=preload("res://scripts/building_definition.gd").for_type(T.HOME)
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	world.placement.select(definition);world.placement.update_world_position(Vector3(-12,0,14))
	var place: RefCounted=world.placement.confirm()
	for resource in definition.construction_requirements:place.add_delivered_material(resource,place.get_required_amount(resource))
	world.player_control.assign_profession(actor.data.id,P.BUILDER);phase(world,1370)
	choose(actor)
	await walk(actor,func():return actor.builder.phase==actor.builder.Phase.BUILDING)
	world.game_time.debug_skip_minutes(59)
	check(place.construction_progress==59 and actor.builder.work_minutes==59 and actor.intents.current_intent.overtime_work,"Accepted Builder cycle accrues at night without the ordinary daytime cutoff")
	world.game_time.debug_skip_minutes(1)
	check(place.construction_progress==60 and actor.builder.phase==actor.builder.Phase.NONE and actor.data.get_skill_xp(S.CONSTRUCTION)==8 and place.active_builder_ids.is_empty(),"One personal cycle ends normally and releases the slot")
	check(not actor.builder.request_work(),"Expired permission cannot start another nighttime cycle")
	world.free();await process_frame

func extraction_and_fields() -> void:
	for profession in [P.LUMBERJACK,P.MINER,P.CLAY_DIGGER,P.FARMER]:
		var world:=F.create(self);var actor:=prepare(world);phase(world,1370)
		var worker: Node
		if profession==P.FARMER:
			var farm: RefCounted=F.building(world,T.FARM,Vector3(-10,0,16));farm.set_stock_target(R.WHEAT,0)
			world.player_control.assign_workplace(actor.data.id,farm.id,P.FARMER);worker=actor.farmer
		else:
			world.player_control.assign_profession(actor.data.id,profession)
			worker=actor.get_node("Lumberjack" if profession==P.LUMBERJACK else "Miner")
			if profession==P.CLAY_DIGGER:world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16))
			var source: RefCounted=world.trees[0] if profession==P.LUMBERJACK else worker.rocks.filter(func(value):return value.resource_type==(R.CLAY if profession==P.CLAY_DIGGER else R.STONE))[0]
			var area: RefCounted=world.work_areas.create(source.position,100.0)
			world.player_control.assign_work_area(actor.data.id,area.id)
		choose(actor)
		check(actor.intents.current_intent.overtime_work,"Existing profession provider accepts the overtime request")
		await walk(actor,func():return actor.data.activity==preload("res://scripts/resident_activity.gd").Type.WORKING)
		var skill: int=S.FARMING if profession==P.FARMER else S.FORESTRY if profession==P.LUMBERJACK else S.MINING
		world.game_time.debug_skip_minutes(10 if profession==P.FARMER else 60)
		check(not actor.intents.has_current_action() and actor.data.get_skill_xp(skill)==(1 if profession==P.FARMER else 8),"Real field/extraction finishes one task across night with unchanged XP")
		check(not worker.request_work(),"Another task cannot inherit the completed permission")
		world.free();await process_frame

func carrier() -> void:
	var world:=F.create(self);var actor:=prepare(world)
	world.place_ground_resources(R.LOG,2,actor.view.get_sim_position())
	world.player_control.assign_workplace(actor.data.id,world.warehouse_data.id,P.PORTER)
	phase(world,1020);choose(actor)
	var job: RefCounted=world.logistics.get_job(actor.data.id)
	check(job!=null and actor.intents.current_intent.overtime_work,"Porter accepts a real reserved delivery")
	for tick in 16000:
		if job==null or not job.is_active():break
		if actor.view._resume_after_frame==Engine.get_physics_frames():await physics_frame;await process_frame
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
	check(job!=null and job.state==job.State.COMPLETED and actor.data.get_skill_xp(S.LOGISTICS)==3 and actor.data.inventory.amount==0,"Original executor preserves delivery and XP")
	check(not actor.intents.has_current_action() and not actor.intents.overtime_admission,"Carrier releases the action-scoped permission")
	world.free();await process_frame

func recipe_catalog() -> void:
	var cases=[[T.SAWMILL,&"sawmill_plank"],[T.STONEMASON_WORKSHOP,&"cut_stone_brick"],[T.POTTERY_WORKSHOP,&"fire_brick"],[T.WEAVER_WORKSHOP,&"wool_cloth"],[T.TAILOR_WORKSHOP,&"wool_clothing"],[T.WINDMILL,&"mill_flour"],[T.FOOD,&"fried_mushroom"],[T.FOOD,&"bake_bread"],[T.FARM,&"thresh_wheat"]]
	for row in cases:
		var world:=F.create(self);var actor:=prepare(world)
		var place: RefCounted=F.building(world,row[0],Vector3(-10,0,16))
		var recipe: RefCounted=place.definition.get_production_recipe(row[1])
		for value in place.definition.production_recipes:
			if value.id!=row[1]:place.set_recipe_mode(value.id,place.ProductionMode.OFF)
		for resource in recipe.inputs:place.resources.add(resource,recipe.inputs[resource])
		for key in recipe.consumables:
			var stock: RefCounted=place.consumable_stocks[key];var material: int=stock.conversions.keys()[0]
			stock.reserve_in(material,1);stock.deliver(material,1)
		if row[0]==T.FARM:place.set_stock_target(R.WHEAT,0)
		world.player_control.assign_workplace(actor.data.id,place.id);phase(world,9*1440+1020 if row[0]==T.FARM else 1020)
		choose(actor)
		check(actor.intents.current_intent.overtime_work and actor.recipe_work.batch!=null and actor.recipe_work.batch.recipe_id==row[1],"Overtime routes through the real profession selector: "+row[1])
		await walk(actor,func():return actor.recipe_work.phase==actor.recipe_work.Phase.WORKING)
		world.game_time.debug_skip_minutes(recipe.work_required)
		for resource in recipe.outputs:check(place.resources.get_amount(resource)==recipe.outputs[resource],"Unchanged recipe output: "+row[1])
		check(not actor.intents.has_current_action() and place.production_worker_id.is_empty(),"Recipe ends one authorized task, not a continuous overtime shift")
		world.free();await process_frame

func shepherd() -> void:
	for cancelled in [false,true]:
		var world:=F.create(self);var actor:=prepare(world)
		var hut: RefCounted=F.building(world,T.SHEPHERD_HUT,Vector3(-10,0,16))
		world.player_control.assign_workplace(actor.data.id,hut.id)
		var animal: Node3D=world.animal_executors[0]
		for value in world.animal_executors:value.set_physics_process(false)
		check(animal.assign_home(hut,world.building_uses,world.work_areas),"Existing domestic sheep assignment")
		animal.behavior.cancel_behavior();animal.data.wool_growth=15
		phase(world,1370);choose(actor)
		check(actor.intents.current_intent.overtime_work,"Shepherd accepts normal shearing as overtime")
		for step in 18000:
			if actor.shepherd.phase==actor.shepherd.Phase.SHEARING:break
			if actor.view._resume_after_frame==Engine.get_physics_frames():await physics_frame;await process_frame
			actor.view._physics_process(0.05);animal._physics_process(0.05)
			if is_instance_valid(actor.shepherd.pair):actor.shepherd.pair.advance(0.05)
			actor.shepherd._physics_process(0.05)
		check(actor.shepherd.phase==actor.shepherd.Phase.SHEARING and actor.intents.current_intent.overtime_work,"Permission survives escort and service stages")
		world.game_time.debug_skip_minutes(60 if cancelled else 120)
		if cancelled:actor.commands.move_to(Vector2(0,500))
		check(actor.data.get_skill_xp(S.ANIMAL_HUSBANDRY)==(0 if cancelled else 16) and hut.resources.get_reserved_in(R.WOOL)==0,"Original full/partial shearing and XP rules remain intact")
		check(not actor.intents.current_intent.overtime_work and animal.data.operation_id.is_empty(),"Completion or command releases sheep and authorization")
		world.free();await process_frame

func stale_admission() -> void:
	for interruption in ["command","phase","probe"]:
		var world:=F.create(self);var actor:=prepare(world);var place:=sawmill(world)
		world.player_control.assign_workplace(actor.data.id,place.id);phase(world,1020)
		var before:=starts
		place.resources.reservations_changed.connect(func(_resource):
			if interruption=="command":actor.commands.move_to(Vector2(0,500))
			elif interruption=="phase":phase(world,1380)
			else:
				actor.decision.collect_actions(false)
				check(not actor.decision._start_overtime(450),"Nested callbacks cannot start a second overtime request"),CONNECT_ONE_SHOT)
		choose(actor)
		if interruption=="probe":
			check(starts==before+1 and actor.intents.current_intent.overtime_work and not actor.intents.overtime_admission,"Nested read-only availability preserves the enclosing admission")
		else:
			check(starts==before and not actor.intents.overtime_admission and not actor.intents.current_intent.overtime_work,"Invalidation during claim cannot create an overtime start")
			check(place.resources.get_reserved_out(R.LOG)==0 and place.resources.get_reserved_in(R.PLANK)==0 and place.resources.get_amount(R.LOG)==4,"Failed admission releases its exact reservations without payment")
		world.free();await process_frame

func critical_interruptions() -> void:
	for hunger in [false,true]:
		var world:=F.create(self);var actor:=prepare(world);var place:=sawmill(world)
		world.player_control.assign_workplace(actor.data.id,place.id);phase(world,1020);choose(actor)
		await walk(actor,func():return actor.recipe_work.phase==actor.recipe_work.Phase.WORKING)
		var batch: RefCounted=actor.recipe_work.batch
		world.game_time.debug_skip_minutes(7)
		actor.decision._deciding=false
		if hunger:actor.data.hunger=100
		else:actor.data.fatigue=100
		actor.decision._deciding=true
		check(actor.intents.forced_priority>0 and not actor.intents.current_intent.overtime_work,"Overtime cannot protect an action from critical hunger or sleep")
		check(batch.state==batch.State.PAUSED and batch.progress==7 and batch.worker_id.is_empty() and place.resources.get_reserved_in(R.PLANK)==1,"Critical interruption preserves the original paid-batch lifecycle")
		check(actor.data.get_skill_xp(S.WOODWORKING)==0 and place.resources.get_amount(R.LOG)==3,"Interrupted overtime grants no premature XP or second input payment")
		world.free();await process_frame

func natural_gathering_and_planting() -> void:
	var world:=F.create(self);var actor:=prepare(world)
	var hut=preload("res://scripts/building_instance.gd").new(&"overtime_gatherer",preload("res://scripts/building_definition.gd").for_type(T.GATHERER_HUT),preload("res://scripts/world_3d/world_coordinates.gd").to_sim(Vector3(-3,0,-5)))
	world.buildings.append(hut);world._show_building(hut)
	world.mycelium.clear_cells(world.mycelium.mushroom_cells())
	world.mycelium.add_mushrooms(world.build_grid.world_to_cell(Vector3(-4.25,0,2.25)),1)
	world.player_control.assign_workplace(actor.data.id,hut.id);phase(world,1370);choose(actor)
	var job: RefCounted=world.logistics.get_job(actor.data.id)
	check(job!=null and actor.intents.current_intent.overtime_work,"Gatherer accepts a real natural-source trip")
	for tick in 16000:
		if job==null or not job.is_active():break
		if actor.view._resume_after_frame==Engine.get_physics_frames():await physics_frame;await process_frame
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
	check(job!=null and job.state==job.State.COMPLETED and hut.resources.get_amount(R.MUSHROOM)==1 and actor.data.get_skill_xp(S.GATHERING)==3 and actor.data.get_skill_xp(S.LOGISTICS)==0,"Gathering retains pickup, delivery and its exclusive XP across night")
	world.free();await process_frame
	world=F.create(self);actor=prepare(world);hut=preload("res://tests/forestry_fixture.gd").hut(world)
	hut.definition.target_tree_count=30
	world.player_control.assign_workplace(actor.data.id,hut.id)
	var worker: Node=actor.get_node("Lumberjack");worker.trees=[]
	phase(world,1370);choose(actor)
	check(worker.kind==&"PLANT" and actor.intents.current_intent.overtime_work,"Existing forestry policy can select a planting task")
	await walk(actor,func():return actor.data.activity==preload("res://scripts/resident_activity.gd").Type.WORKING)
	var before: int=world.trees.size();world.game_time.debug_skip_minutes(30)
	check(world.trees.size()==before+1 and actor.data.get_skill_xp(S.FORESTRY)==4 and world.forestry_area.claims.is_empty(),"Plant geometry, result, XP and claim cleanup remain unchanged")
	world.free();await process_frame

func sowing_group() -> void:
	var world:=F.create(self);var actor:=prepare(world)
	var farm: RefCounted=F.building(world,T.FARM,Vector3(-10,0,16));farm.set_stock_target(R.WHEAT,0)
	world.player_control.assign_workplace(actor.data.id,farm.id)
	var cells: Array=[]
	for index in 5:
		var cell: Vector2i=actor.farmer._first_plow(farm)
		check(world.farm_fields.reserve([cell],&"prepared",0,world._farm_cell_allowed) and world.farm_fields.plow(cell,&"prepared"),"Prepare a real five-cell patch through existing field API")
		cells.append(cell)
	farm.resources.add(R.WHEAT,1);phase(world,1370);choose(actor)
	check(actor.farmer._kind==&"SOW" and actor.intents.current_intent.overtime_work,"One ordinary sowing job owns its group of five cells")
	for cell in cells:
		await walk(actor,func():return actor.farmer.phase==actor.farmer.Phase.WORKING)
		check(actor.intents.current_intent.overtime_work,"Authorization survives the field controller's next-cell transition")
		world.game_time.debug_skip_minutes(10)
	check(cells.all(func(cell):return world.farm_fields.state(cell)==2 and not world.farm_fields.claimed(cell)) and farm.resources.get_amount(R.WHEAT)==0 and actor.data.get_skill_xp(S.FARMING)==5,"Five finished cells spend one seed and award existing per-cell XP")
	check(not actor.intents.has_current_action() and not actor.intents.overtime_admission,"The permission ends after the whole existing sowing action")
	world.free();await process_frame

func builder_materials() -> void:
	var world:=F.create(self);var actor:=prepare(world)
	var definition=preload("res://scripts/building_definition.gd").for_type(T.HOME)
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	world.placement.select(definition);world.placement.update_world_position(Vector3(-12,0,14))
	var place: RefCounted=world.placement.confirm()
	for resource in definition.construction_requirements:place.add_delivered_material(resource,place.get_required_amount(resource)-(1 if resource==R.LOG else 0))
	world.warehouse_data.resources.add(R.LOG,1)
	world.player_control.assign_profession(actor.data.id,P.BUILDER);phase(world,1370)
	var before:=starts;choose(actor)
	for stage in 2:
		await walk(actor,func():return actor.builder.handling.is_active())
		check(actor.intents.current_intent.overtime_work,"Builder material trip remains the same selected task")
		world.game_time.debug_skip_minutes(10)
	await walk(actor,func():return actor.builder.phase==actor.builder.Phase.BUILDING)
	world.game_time.debug_skip_minutes(60)
	check(starts==before+1 and place.construction_progress==60 and actor.data.get_skill_xp(S.LOGISTICS)==3 and actor.data.get_skill_xp(S.CONSTRUCTION)==8,"One overtime grant covers the existing material trip and personal work cycle")
	check(actor.data.inventory.amount==0 and place.get_construction_reserved_in(R.LOG)==0 and place.active_builder_ids.is_empty() and not actor.intents.has_current_action(),"Normal builder cleanup releases cargo, inbound hold, slot and permission")
	world.free();await process_frame
