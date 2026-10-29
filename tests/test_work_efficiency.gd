extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const Work = preload("res://scripts/work_progress.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Skills = preload("res://scripts/work_operation_skills.gd")
const S = preload("res://scripts/skill_type.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Data = preload("res://scripts/resident_data.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	math_and_handling()
	await builders()
	await fields()
	await planting()
	await gathering_handling()
	await builder_handling()
	print("Work efficiency: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func math_and_handling() -> void:
	var data := Data.new("worker", "Тест", 20)
	for xp in [0,2500,10000]:
		data._skill_xp[S.CONSTRUCTION] = xp
		var rate := Modifiers.work_rate(data,Skills.for_operation(&"construction"))
		check(is_equal_approx(rate,1.0+0.5*sqrt(float(xp)/10000.0)),"Existing formula, without rank/trait bonuses")
		for required in [10,30,60,120]:
			var progress := 0.0
			var duration := ceili(required/rate)
			for minute in duration-1: progress=Work.advance(progress,rate,required)
			check(not Work.reached(progress,required),"Incomplete until final whole-minute tick")
			progress=Work.advance(progress,rate,required)
			check(progress==required,"Exact clipped threshold; no excess work bank")
		var handling=preload("res://scripts/resource_handling.gd").new()
		var ticks := ceili(10.0/rate)
		check(handling.start(&"loading",100,10,rate),"Accepted handling rate")
		check(not handling.advance(100) and not handling.advance(100+ticks-1),"No same-minute or early completion")
		check(handling.advance(100+ticks) and not handling.advance(100+ticks),"One consumed completion")
		check(handling.start(&"unloading",100+ticks,10,rate) and handling.progress==0.0,"No carry between stages")
		handling.advance(101+ticks);handling.cancel()
		check(not handling.advance(1000) and handling.progress==0.0,"Cancel discards only local handling work")
	data._skill_xp[S.WOODWORKING]=10000
	check(is_equal_approx(Modifiers.work_rate(data,Skills.for_operation(&"sawmill_plank")),1.4),"80/20 averages percentages, not XP")
	check(Modifiers.work_rate(null,Skills.for_operation(&"loading"))<0.0,"Invalid resident is not neutral work")
	var p := 0.0
	for step in 100: p=Work.advance(p,0.1,10.0)
	check(p==10.0 and not Work.reached(9.999,10.0),"Absolute tolerance fixes roundoff without skipping real work")
	check(Work.whole_ceil(15.0*8.25/120.0)==2,"Shearing keeps fractional removal near ceil boundary")
	check(Work.whole_floor(4.0*29.75/120.0)==0 and Work.whole_floor(4.0*30.0/120.0)==1,"Partial wool floor threshold")
	var tree=preload("res://scripts/tree_data.gd").new(&"tree",Vector2.ZERO)
	tree.claim(&"A");tree.add_work(&"A",1.25);tree.release(&"A")
	tree.claim(&"B");tree.add_work(&"B",1.5)
	check(tree.work_done==2.75,"Persistent fractional work survives worker change")
	var rock=preload("res://scripts/rock_data.gd").new(&"rock",Vector2.ZERO)
	rock.claim(&"A");rock.add_work(&"A",59.75)
	check(rock.add_work(&"A",1.5)==1 and rock.work_done==0.0 and rock.completed_cycles==1,"One receipt and no next-cycle excess")
	check(rock.add_work(&"A",1.5)==0,"Old claim cannot repeat completion")
	var timer=preload("res://scripts/resource_handling.gd").new()
	timer.start(&"loading",100,10,1.25)
	check(not timer.advance(110,false) and not timer.advance(111) and timer.progress==1.25,"Inactive handling does not bank catch-up work")

func site(world: Node, missing: int = -1) -> RefCounted:
	var definition=preload("res://scripts/building_definition.gd").for_type(T.HOME)
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	world.placement.select(definition);world.placement.update_world_position(Vector3(-12,0,14))
	var result=world.placement.confirm()
	for resource in definition.construction_requirements: result.add_delivered_material(resource,result.get_required_amount(resource)-(1 if resource==missing else 0))
	return result
func start_builder(world: Node, index: int, xp: int) -> Node:
	var actor: Node=world.resident_runtimes[index]
	actor.data.add_skill_xp(S.CONSTRUCTION,xp)
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	check(actor.builder.request_work(),"Builder accepts ordinary task")
	F.walk(world,actor)
	check(actor.builder.phase==actor.builder.Phase.BUILDING,"Actual structural work starts after arrival")
	return actor
func builders() -> void:
	var world: Node
	var target: RefCounted
	var actor: Node
	for xp in [0,2500,10000]:
		world=F.create(self);target=site(world)
		actor=start_builder(world,0,xp)
		var rate := Modifiers.work_rate(actor.data,Skills.for_operation(&"construction"))
		world.game_time.debug_skip_minutes(59)
		check(is_equal_approx(target.construction_progress,59*rate) and actor.builder.work_minutes==59 and actor.data.get_skill_xp(S.CONSTRUCTION)==xp,"Volume differs from personal active minutes")
		world.game_time.debug_skip_minutes(1)
		check(is_equal_approx(target.construction_progress,60*rate) and actor.data.get_skill_xp(S.CONSTRUCTION)==mini(10000,xp+8),"Sixty real minutes give one unchanged award")
		actor.builder._on_minute(world.game_time.total_minutes)
		check(is_equal_approx(target.construction_progress,60*rate),"Repeated builder tick cannot contribute again")
		world.free();await process_frame

	for reverse in [false,true]:
		world=F.create(self);target=site(world)
		var first:=start_builder(world,0,2500);var second:=start_builder(world,1,10000)
		if reverse:
			world.game_time.minute_changed.disconnect(first.builder._on_minute)
			world.game_time.minute_changed.connect(first.builder._on_minute)
		world.game_time.debug_skip_minutes(10)
		check(target.construction_progress==27.5 and first.builder.work_minutes==10 and second.builder.work_minutes==10,"Concurrent 125/150 rates add without per-worker rounding")
		first.builder.abort("handoff",false)
		world.game_time.debug_skip_minutes(1)
		check(target.construction_progress==29.0 and first.data.get_skill_xp(S.CONSTRUCTION)==2500,"Cancelled contribution persists; other builder keeps own rate")
		target.construction_progress=179.5
		world.game_time.debug_skip_minutes(1)
		check(target.is_built() and target.construction_progress==180.0 and target.active_builder_ids.is_empty(),"Clipped final half minute completes once and clears all claims")
		world.free();await process_frame
	world=F.create(self);target=site(world)
	target.construction_progress=105.0
	actor=start_builder(world,0,2500)
	world.game_time.debug_skip_minutes(59)
	target.construction_progress=179.5
	world.game_time.debug_skip_minutes(1)
	check(target.is_built() and actor.data.get_skill_xp(S.CONSTRUCTION)==2508,"Last accepted clipped tick counts as personal minute sixty")
	world.free();await process_frame
	world=F.create(self);target=site(world);actor=start_builder(world,0,2500)
	world.game_time.debug_skip_minutes(1)
	actor.builder.abort("cancel",false)
	check(target.construction_progress==1.25 and actor.data.get_skill_xp(S.CONSTRUCTION)==2500,"Abort preserves fractional building work without partial XP")
	check(target.set_work_direction(target.WorkDirection.DEMOLISH),"Reverse existing fractional structure")
	target.work_paused=false
	target.add_construction_work(0.75)
	check(target.construction_progress==0.5 and not target.ready_for_removal(),"Fractional remainder cannot be demolished by integer projection")
	target.add_construction_work(1.5)
	check(target.construction_progress==0.0 and target.ready_for_removal(),"Demolition clips at true zero")
	world.free();await process_frame
	world=F.create(self);target=site(world);actor=start_builder(world,0,2500)
	world.game_time.debug_skip_minutes(1)
	actor.data.add_skill_xp(S.CONSTRUCTION,7500)
	world.game_time.debug_skip_minutes(1)
	check(target.construction_progress==2.5,"Rate is fixed at active start, not recalculated by a mid-operation award")
	actor.builder.abort("restart",false)
	check(actor.builder.request_work(),"Resume structural work normally")
	F.walk(world,actor)
	world.game_time.debug_skip_minutes(1)
	check(target.construction_progress==4.0,"New active operation samples new skill, without recalculating old work")
	world.free();await process_frame
	world=F.create(self);target=site(world);actor=start_builder(world,0,2500)
	world.game_time.debug_skip_minutes(59)
	target._updating_progress=true
	world.game_time.debug_skip_minutes(1)
	check(actor.builder.work_minutes==59 and actor.data.get_skill_xp(S.CONSTRUCTION)==2500,"Rejected contribution cannot earn the sixtieth personal minute")
	target._updating_progress=false
	actor.builder._on_minute(world.game_time.total_minutes)
	check(actor.data.get_skill_xp(S.CONSTRUCTION)==2508 and target.construction_progress==75.0,"One retry accepts the original tick exactly once")
	world.free();await process_frame

func planting() -> void:
	for xp in [0,2500,10000]:
		var world:=F.create(self)
		var hut=preload("res://tests/forestry_fixture.gd").hut(world)
		hut.definition.target_tree_count=30
		var actor: Node=world.resident_runtimes[0]
		actor.data.add_skill_xp(S.FORESTRY,xp)
		world.player_control.assign_workplace(actor.data.id,hut.id)
		for tree in world.trees: tree.claim(&"plant_fixture")
		var worker: Node=actor.get_node("Lumberjack")
		worker.trees=[]
		check(worker.request_work() and worker.kind==&"PLANT","Real hut planting, without changing selection priorities")
		F.walk(world,actor)
		var rate: float=worker._work_rate
		world.game_time.debug_skip_minutes(1)
		check(worker.work_minutes==rate,"Planting accumulates a fractional local work minute")
		worker.abort(false)
		check(worker.work_minutes==0.0 and not world.forestry_area.claims.has(actor.data.id),"Plant cancel clears progress and position claim")
		check(worker.request_work(),"New planting starts from zero")
		F.walk(world,actor)
		var before: int=world.trees.size()
		var duration:=ceili(30.0/rate)
		world.game_time.debug_skip_minutes(duration-1)
		check(world.trees.size()==before,"No sapling before final minute")
		world.game_time.debug_skip_minutes(1)
		check(world.trees.size()==before+1 and actor.data.get_skill_xp(S.FORESTRY)==mini(10000,xp+4),"One confirmed sapling and unchanged Plant award")
		worker._minute(world.game_time.total_minutes)
		check(world.trees.size()==before+1,"No duplicate planting callback")
		world.free();await process_frame
func fields() -> void:
	for xp in [0,2500,10000]:
		var world:=F.create(self)
		var farm: RefCounted=F.building(world,T.FARM,Vector3(-10,0,16))
		var actor: Node=world.resident_runtimes[0]
		actor.data.add_skill_xp(S.FARMING,xp)
		world.player_control.assign_workplace(actor.data.id,farm.id,P.FARMER);farm.set_stock_target(preload("res://scripts/resource_type.gd").Type.WHEAT,0)
		check(actor.farmer.request_work(),"Real field operation starts")
		for step in 20000:
			if actor.farmer.phase==actor.farmer.Phase.WORKING: break
			actor.view._physics_process(0.05)
		var cell: Vector2i=actor.farmer._target
		var duration := ceili(10.0/actor.farmer._work_rate)
		world.game_time.debug_skip_minutes(duration-1)
		check(world.farm_fields.state(cell)==0,"Cell unfinished before final tick")
		world.game_time.debug_skip_minutes(1)
		check(world.farm_fields.state(cell)==1 and actor.data.get_skill_xp(S.FARMING)==mini(10000,xp+1),"Exact one completed cell and unchanged XP")
		check(actor.farmer.request_work(),"New cell starts without excess")
		for step in 20000:
			if actor.farmer.phase==actor.farmer.Phase.WORKING: break
			actor.view._physics_process(0.05)
		world.game_time.debug_skip_minutes(1)
		var next: Vector2i=actor.farmer._target
		actor.farmer.cancel()
		check(world.farm_fields.state(next)==0 and not world.farm_fields.claimed(next),"Partial field cancellation does not persist new labour")
		world.free();await process_frame

func gathering_handling() -> void:
	var world:=F.create(self)
	var actor: Node=world.resident_runtimes[0]
	var hut=preload("res://scripts/building_instance.gd").new(&"skill_gatherer",preload("res://scripts/building_definition.gd").for_type(T.GATHERER_HUT),preload("res://scripts/world_3d/world_coordinates.gd").to_sim(Vector3(-3,0,-5)))
	world.buildings.append(hut);world._show_building(hut)
	world.mycelium.clear_cells(world.mycelium.mushroom_cells())
	var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-4.25,0,2.25))
	world.mycelium.add_mushrooms(cell,1)
	actor.data.add_skill_xp(S.GATHERING,2500)
	world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER)
	check(actor.self_logistics.request_work(),"Natural gathering uses the existing accepted hauling job")
	var executor: RefCounted=world.logistics._executors[actor.data.id]
	for stage in [0,1]:
		for step in 18000:
			if executor.handling.is_active(): break
			actor.view._physics_process(0.05)
		var expected: float=1.25 if stage==0 else 1.0
		check(executor.handling.is_active() and executor.handling._rate==expected,"Natural loading uses Gathering, unloading uses Logistics")
		var duration:=ceili(10.0/expected)
		world.game_time.debug_skip_minutes(duration-1)
		check(actor.data.inventory.amount==stage,"No premature natural pickup or unload")
		world.game_time.debug_skip_minutes(1)
	check(actor.data.get_skill_xp(S.GATHERING)==2503 and actor.data.get_skill_xp(S.LOGISTICS)==0,"Natural trip retains only its S2 Gathering reward")
	check(hut.resources.get_amount(preload("res://scripts/resource_type.gd").Type.MUSHROOM)==1 and actor.data.inventory.amount==0,"One physical mushroom delivered once")
	world.free();await process_frame

func builder_handling() -> void:
	var world:=F.create(self)
	var resource=preload("res://scripts/resource_type.gd").Type.STONE
	var target:=site(world,resource)
	world.warehouse_data.resources.add(resource,1)
	var actor: Node=world.resident_runtimes[0]
	actor.data.add_skill_xp(S.CONSTRUCTION,10000);actor.data.add_skill_xp(S.LOGISTICS,2500)
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	check(actor.builder.request_work(),"Builder claims last material through normal source reservations")
	for stage in [0,1]:
		for step in 18000:
			if actor.builder.handling.is_active(): break
			if actor.view._resume_after_frame==Engine.get_physics_frames():
				await physics_frame;await process_frame
			actor.view._physics_process(0.05)
		check(actor.builder.handling.is_active() and actor.builder.handling._rate==1.25,"Builder samples Logistics rather than Construction for handling")
		world.game_time.debug_skip_minutes(7)
		check(actor.data.inventory.amount==stage and target.construction_progress==0.0,"Seven handling minutes cannot transfer or contribute structural work")
		world.game_time.debug_skip_minutes(1)
	check(actor.data.get_skill_xp(S.LOGISTICS)==2503 and actor.data.inventory.amount==0 and target.get_construction_reserved_in(resource)==0,"One Builder delivery retains the fixed XP and releases inbound reservation")
	world.free();await process_frame
