extends "res://tests/test_work_efficiency.gd"
const Trait = preload("res://scripts/trait_type.gd").Type
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Need = preload("res://scripts/need_type.gd").Type
const Ops = preload("res://scripts/work_operation_skills.gd")
func neutral_world() -> Node:
	var result := F.create(self)
	for actor in result.resident_runtimes: actor.data.set_traits([])
	return result
func run() -> void:
	rates_and_needs()
	await construction()
	await all_recipes()
	await extraction()
	await field_and_plant()
	await gathering_and_transport()
	await ordinary_builder_transport()
	generation()
	print("HASTY: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func rates_and_needs() -> void:
	var person := Data.new("hasty", "Hasty", 25); person.add_trait(Trait.HASTY)
	for xp in [0,1600,10000]:
		for skill in S.values(): person._skill_xp[skill] = xp
		for operation in Ops.OPERATIONS.keys()+Ops.RECIPES.keys()+[&"gather_loading"]:
			if operation == &"delivery": continue # No work-progress stage for a whole delivery.
			var rules = Ops.for_operation(operation)
			check(is_equal_approx(Modifiers.work_rate(person,rules),rules.efficiency_percent(person)/100.0*1.15), "Every work kind composes skill efficiency and HASTY once")
		for operation in [&"loading",&"unloading"]:
			check(is_equal_approx(Modifiers.work_rate(person,Ops.for_operation(operation),false),1.0+0.5*sqrt(float(xp)/10000)), "Ordinary logistics keeps skills and excludes HASTY")
	check(is_equal_approx(Modifiers.work_rate(person,Ops.for_operation(&"construction")),1.725), "No accidental 150 percent cap on combined speed")
	check(Modifiers.movement_speed(person,100)==100, "No movement bonus")
	for action in Modifiers.Action.values(): check(Modifiers.action_utility(person,action,5000)==5000, "No utility bonus")
	var baseline_needs: Dictionary={}
	for hasty in [false,true]:
		for activity in Dynamics.FATIGUE_RATES:
			for active in [false,true]:
				var data := Data.new("needs", "Needs", 25)
				if hasty: data.add_trait(Trait.HASTY)
				data.activity=activity;data.current_sleep_quality=0.5
				for need in 4: data.get_need(need).value=50
				var dynamics := Dynamics.new(); dynamics._data=data; dynamics.active_work_provider=func():return active
				for minute in 60: dynamics._on_minute_changed(minute)
				var base: float=Dynamics.FATIGUE_RATES[activity]
				var expected: float=base*(1.3 if hasty and active and activity in [Activity.WORKING,Activity.HAULING] else 1.0)*(0.5 if activity==Activity.SLEEPING else 1.0)
				check(is_equal_approx((data.fatigue-50)*60+dynamics._fractions[Need.FATIGUE],expected*60), "Only actual positive work rate changes, preserving existing fractional account")
				check(Modifiers.fatigue_need_rate(data,-10,active)==-10, "Recovery never accelerated")
				var key:=str(activity)+":"+str(active)
				var other_needs: Array=[]
				for need in [Need.HUNGER,Need.SOCIAL,Need.LEISURE]:other_needs.append([data.get_need(need).value,dynamics._fractions[need]])
				if not hasty:baseline_needs[key]=other_needs
				else:check(other_needs==baseline_needs[key],"Other needs and their fractions unchanged in every activity")
				dynamics.free()
	var long_run := Dynamics.new(); long_run._data=person; long_run.active_work_provider=func():return true
	person.activity=Activity.WORKING;person.fatigue=0
	for minute in 600: long_run._on_minute_changed(minute)
	check(person.fatigue==52 and absf(long_run._fractions[Need.FATIGUE])<0.000001, "Six hundred active minutes retain exact 52 fatigue points without drift")
	long_run.free()
func construction(working_trait: int = Trait.HASTY, multiplier: float = 1.15) -> void:
	var world:=neutral_world(); var target:=site(world)
	world.resident_runtimes[0].data.add_trait(working_trait)
	var actor:=start_builder(world,0,0)
	check(actor.is_actively_working(), "Actual builder contribution is active work")
	var old_phase: int=actor.builder.phase
	actor.builder.phase=actor.builder.Phase.WAITING_FOR_MATERIALS
	actor.data.fatigue=50;actor.need_dynamics._fractions[Need.FATIGUE]=0
	actor.need_dynamics._on_minute_changed(world.game_time.total_minutes)
	check(not actor.is_actively_working() and actor.need_dynamics._fractions[Need.FATIGUE]==4,"WORKING marker during a material pause gives only baseline fatigue")
	actor.builder.phase=old_phase
	world.game_time.debug_skip_minutes(59)
	check(is_equal_approx(target.construction_progress,59*multiplier) and actor.builder.work_minutes==59 and actor.data.get_skill_xp(S.CONSTRUCTION)==0, "Builder speeds volume, not personal XP minutes")
	world.game_time.debug_skip_minutes(1)
	check(is_equal_approx(target.construction_progress,60*multiplier) and actor.data.get_skill_xp(S.CONSTRUCTION)==8 and not actor.is_actively_working(), "One sixty-minute cycle keeps eight XP and cleans active work")
	world.free();await process_frame
	world=neutral_world();target=site(world)
	world.resident_runtimes[0].data.add_trait(working_trait)
	var first:=start_builder(world,0,0);var second:=start_builder(world,1,0)
	world.game_time.debug_skip_minutes(10)
	check(is_equal_approx(target.construction_progress,10*(1+multiplier)), "Two builders contribute independent volumes")
	first.builder.abort("test",false);second.builder.abort("test",false)
	check(first.data.get_skill_xp(S.CONSTRUCTION)==0 and not first.is_actively_working(), "Partial personal work gives no XP; cancel releases work")
	first.data._skill_xp[S.CONSTRUCTION]=1600
	check(first.builder.request_work(), "Same site resumes")
	F.walk(world,first);world.game_time.debug_skip_minutes(10)
	check(is_equal_approx(target.construction_progress,10+22*multiplier) and is_equal_approx(first.builder._work_rate,1.2*multiplier), "Resume snapshots new skill times trait without rescaling old progress")
	world.free();await process_frame
func all_recipes(working_trait: int = Trait.HASTY, multiplier: float = 1.15) -> void:
	var cases := [[T.SAWMILL,&"sawmill_plank"],[T.STONEMASON_WORKSHOP,&"cut_stone_brick"],[T.POTTERY_WORKSHOP,&"fire_brick"],[T.WEAVER_WORKSHOP,&"wool_cloth"],[T.TAILOR_WORKSHOP,&"wool_clothing"],[T.WINDMILL,&"mill_flour"],[T.FOOD,&"fried_mushroom"],[T.FOOD,&"bake_bread"],[T.FARM,&"thresh_wheat"]]
	for row in cases:
		var world:=neutral_world();var place=F.building(world,row[0],Vector3(-10,0,16))
		var first: Node=world.resident_runtimes[0];first.data.add_trait(working_trait)
		var recipe: RefCounted
		for value in place.definition.production_recipes:
			if value.id==row[1]:recipe=value
		for resource in recipe.inputs:place.resources.add(resource,recipe.inputs[resource])
		for key in recipe.consumables:
			var stock: RefCounted=place.consumable_stocks[key];var material: int=stock.conversions.keys()[0]
			check(stock.reserve_in(material,1) and stock.deliver(material,1), "Real recipe fuel/water supplied")
		world.player_control.assign_workplace(first.data.id,place.id)
		check(first.recipe_work.request_work(), "Real recipe starts: "+row[1]);F.walk(world,first)
		var batch=first.recipe_work.batch
		check(first.is_actively_working() and is_equal_approx(first.recipe_work._work_rate,multiplier), "All nine recipes capture HASTY at active start")
		world.game_time.debug_skip_minutes(10)
		check(is_equal_approx(batch.progress,10*multiplier), "Ten active minutes give 11.5 units")
		for skill in S.values():first.data._skill_xp[skill]=1600
		world.game_time.debug_skip_minutes(1)
		check(is_equal_approx(batch.progress,11*multiplier), "Running rate is frozen despite changed skills")
		first.recipe_work.abort();world.player_control.assign_profession(first.data.id,P.NONE)
		var last: Node=world.resident_runtimes[1]
		world.player_control.assign_workplace(last.data.id,place.id)
		check(last.recipe_work.request_work(), "Paid batch accepts different finishing worker");F.walk(world,last)
		check(last.recipe_work.batch==batch and last.recipe_work._work_rate==1.0 and is_equal_approx(batch.progress,11*multiplier), "New worker continues preserved fraction at own speed")
		world.game_time.debug_skip_minutes(ceili(recipe.work_required-11*multiplier))
		var rewards=Ops.for_operation(row[1]).xp_rewards
		for reward in rewards:check(last.data.get_skill_xp(reward.skill)==reward.amount and first.data.get_skill_xp(reward.skill)==1600, "Finisher receives fixed S2 XP once")
		for resource in recipe.outputs:check(place.resources.get_amount(resource)==recipe.outputs[resource], "No output duplication")
		last.recipe_work._on_minute(world.game_time.total_minutes)
		for reward in rewards:check(last.data.get_skill_xp(reward.skill)==reward.amount, "Repeat completion does not award again")
		world.free();await process_frame
func extraction(working_trait: int = Trait.HASTY, multiplier: float = 1.15) -> void:
	var resources=preload("res://scripts/resource_type.gd").Type
	for kind in [&"tree",&"stone",&"clay"]:
		var world:=neutral_world();var actor: Node=world.resident_runtimes[0];actor.data.add_trait(working_trait)
		world.player_control.assign_profession(actor.data.id,P.LUMBERJACK if kind==&"tree" else P.MINER if kind==&"stone" else P.CLAY_DIGGER)
		var worker: Node=actor.get_node("Lumberjack" if kind==&"tree" else "Miner")
		if kind==&"clay":check(world.debug_spawn.spawn_clay_deposit(Vector3(-17,0,16)).ok,"Real clay fixture")
		var source=world.trees[0] if kind==&"tree" else worker.rocks.filter(func(rock):return rock.resource_type==(resources.STONE if kind==&"stone" else resources.CLAY))[0]
		var area=world.work_areas.create(source.position,100.0);world.player_control.assign_work_area(actor.data.id,area.id)
		check(worker.request_work(), "Actual extraction starts: "+kind);F.walk(world,actor)
		source=worker.tree if kind==&"tree" else worker.rock
		check(actor.is_actively_working(), "Extractor accepts active work")
		world.game_time.debug_skip_minutes(10)
		check(is_equal_approx(source.work_done,10*multiplier), "Extraction receives HASTY volume")
		worker.abort(false)
		check(not actor.is_actively_working() and is_equal_approx(source.work_done,10*multiplier), "Extraction cancellation preserves target progress and disables fatigue bonus")
		world.free();await process_frame
func field_and_plant(working_trait: int = Trait.HASTY, multiplier: float = 1.15) -> void:
	var world:=neutral_world();var farm=F.building(world,T.FARM,Vector3(-10,0,16));var actor: Node=world.resident_runtimes[0]
	actor.data.add_trait(working_trait);world.player_control.assign_workplace(actor.data.id,farm.id,P.FARMER);farm.set_stock_target(preload("res://scripts/resource_type.gd").Type.WHEAT,0)
	check(actor.farmer.request_work(), "Field operation starts")
	for step in 20000:
		if actor.farmer.phase==actor.farmer.Phase.WORKING:break
		actor.view._physics_process(0.05)
	var cell: Vector2i=actor.farmer._target
	check(actor.is_actively_working(), "Field phase is active work")
	world.game_time.debug_skip_minutes(ceili(10.0/multiplier)-1);check(world.farm_fields.state(cell)==0,"No early completion of 10-unit cell")
	world.game_time.debug_skip_minutes(1);check(world.farm_fields.state(cell)==1 and actor.data.get_skill_xp(S.FARMING)==1,"Cell finishes after nine minutes and one XP")
	world.free();await process_frame
	world=neutral_world();var hut=preload("res://tests/forestry_fixture.gd").hut(world);hut.definition.target_tree_count=30;actor=world.resident_runtimes[0]
	actor.data.add_trait(working_trait);world.player_control.assign_workplace(actor.data.id,hut.id)
	for tree in world.trees:tree.claim(&"plant_fixture")
	var worker: Node=actor.get_node("Lumberjack");worker.trees=[]
	check(worker.request_work() and worker.kind==&"PLANT","Real planting selected");F.walk(world,actor)
	world.game_time.debug_skip_minutes(1);check(is_equal_approx(worker.work_minutes,multiplier) and actor.is_actively_working(),"PLANT gets same rate")
	worker.abort(false);check(worker.work_minutes==0.0 and not world.forestry_area.claims.has(actor.data.id),"PLANT cancel releases local progress/claim")
	world.free();await process_frame
func gathering_and_transport(working_trait: int = Trait.HASTY, multiplier: float = 1.15) -> void:
	for xp in [0,10000]:
		var world:=neutral_world();var actor: Node=world.resident_runtimes[0];actor.data.add_trait(working_trait)
		var hut=preload("res://scripts/building_instance.gd").new(&"hasty_gatherer",preload("res://scripts/building_definition.gd").for_type(T.GATHERER_HUT),preload("res://scripts/world_3d/world_coordinates.gd").to_sim(Vector3(-3,0,-5)))
		world.buildings.append(hut);world._show_building(hut);world.mycelium.clear_cells(world.mycelium.mushroom_cells())
		world.mycelium.add_mushrooms(world.build_grid.world_to_cell(Vector3(-4.25,0,2.25)),1)
		actor.data._skill_xp[S.GATHERING]=xp;actor.data._skill_xp[S.LOGISTICS]=xp
		world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER)
		check(actor.self_logistics.request_work(),"Natural gathering accepted")
		var executor: RefCounted=world.logistics._executors[actor.data.id]
		check(not actor.is_actively_working(),"Trip to mushroom is not active gathering")
		for stage in [0,1]:
			for step in 18000:
				if executor.handling.is_active():break
				actor.view._physics_process(0.05)
			var expected: float=(1.0 if xp==0 else 1.5)*(multiplier if stage==0 else 1.0)
			check(is_equal_approx(executor.handling._rate,expected) and actor.is_actively_working()==(stage==0),"Gathering boosted, unloading unchanged by purpose")
			world.game_time.debug_skip_minutes(ceili(10.0/expected))
		check(actor.data.inventory.amount==0 and hut.resources.get_amount(preload("res://scripts/resource_type.gd").Type.MUSHROOM)==1 and actor.data.get_skill_xp(S.GATHERING)==mini(10000,xp+3),"One mushroom delivered; reward unchanged")
		world.free();await process_frame
func ordinary_builder_transport(working_trait: int = Trait.HASTY) -> void:
	var world:=neutral_world();var resource=preload("res://scripts/resource_type.gd").Type.STONE
	var target:=site(world,resource);world.warehouse_data.resources.add(resource,1)
	var actor: Node=world.resident_runtimes[0];actor.data.add_trait(working_trait)
	actor.data._skill_xp[S.CONSTRUCTION]=10000;actor.data._skill_xp[S.LOGISTICS]=2500
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	check(actor.builder.request_work(),"HASTY builder reserves material normally")
	for stage in [0,1]:
		for step in 18000:
			if actor.builder.handling.is_active():break
			if actor.view._resume_after_frame==Engine.get_physics_frames():await physics_frame;await process_frame
			actor.view._physics_process(0.05)
		check(actor.builder.handling._rate==1.25 and not actor.is_actively_working(),"Both loading and unloading keep only Logistics skill and no extra fatigue")
		world.game_time.debug_skip_minutes(8)
	check(actor.data.get_skill_xp(S.LOGISTICS)==2503 and actor.data.inventory.amount==0 and target.get_construction_reserved_in(resource)==0,"Builder delivery XP/reserves unchanged")
	world.free();await process_frame
func generation() -> void:
	var traits=preload("res://scripts/trait_type.gd");var generator=preload("res://scripts/resident_generator.gd").new(42);var found:=0
	for index in 200:
		var person=generator.generate();check(traits.compatible(person.traits),"Generated pair compatible")
		for type in person.traits+person.liked_traits+person.disliked_traits:check(type not in [Trait.CARING],"CARING is excluded")
		if person.has_trait(Trait.HASTY):found+=1;check(not person.add_trait(Trait.DELIBERATE),"HASTY rejects DELIBERATE")
	check(found>0 and traits.GENERATION_POOL.size()==12 and traits.description([Trait.HASTY,Trait.PRUDENT])=="Торопливый прагматик","HASTY generated and description stable")
