extends SceneTree
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const B = preload("res://scripts/resident_builder_controller.gd")
const Skill = preload("res://scripts/skill_type.gd").Type
var failures := 0
var checks := 0
var starts := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
	world.placement.select(Def.for_type(Types.HOME))
	world.placement.update_world_position(Vector3(-12,0,14))
	var site = world.placement.confirm()
	site.add_delivered_material(R.PLANK,10)
	return world
func target_for(world: Node): return world.buildings[-1]
func start(world: Node, index: int = 1) -> Node:
	var actor = world.resident_runtimes[index]
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	actor.builder.work_cycle_started.connect(func(_id): starts+=1)
	check(world._request_work(actor),"Normal Builder work request")
	for step in range(2000):
		actor.view._physics_process(0.05)
		if actor.builder.phase==B.Phase.BUILDING: break
	check(actor.builder.phase==B.Phase.BUILDING,"Physical access arrival starts cycle")
	return actor
func resume(world: Node, actor: Node) -> void:
	if actor.commands.active_command!=null: actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
	check(world._request_work(actor),"Resume is a new normal action")
	for step in range(2000):
		actor.view._physics_process(0.05)
		if actor.builder.phase==B.Phase.BUILDING: break
func run() -> void:
	var world = fixture()
	var target = target_for(world)
	var actor = start(world)
	world.resident_selection.select_building(target)
	var card = world.get_node("HUD/BuildingCard")
	world.game_time.debug_skip_minutes(10)
	check(target.construction_progress==10 and actor.builder.work_minutes==10,"10 minutes immediately become10 domain work")
	check("10 / 180" in card.construction_work.text,"Existing card updates from construction_changed during cycle")
	world.game_time.debug_skip_minutes(20)
	check(target.construction_progress==30 and actor.data.get_skill_xp(Skill.CONSTRUCTION)==0 and starts==1,"Progress30, XP0, only one WORK start")
	actor.builder._on_minute(world.game_time.total_minutes)
	check(target.construction_progress==30,"Duplicate same-minute update cannot double apply")
	var actual_position: Vector3 = actor.view.global_position
	actor.view.global_position+=Vector3(10,0,0)
	world.game_time.debug_skip_minutes(5)
	check(target.construction_progress==30,"Remote worker cannot contribute or bank catch-up time")
	actor.view.global_position=actual_position
	world.game_time.debug_skip_minutes(1)
	check(target.construction_progress==31,"Return credits only the next actual working minute")
	check(world.cancel_construction(target.id) and target.construction_progress==31 and actor.builder.phase==B.Phase.NONE,"Cancellation preserves applied work and cleans assignment")
	world.free()
	world=fixture()
	target=target_for(world)
	actor=start(world)
	world.game_time.debug_skip_minutes(17)
	actor.commands.move_to(Vector2(0,500))
	check(target.construction_progress==17 and target.active_builder_ids.is_empty(),"PlayerCommand preserves17 and cleans slot")
	world.game_time.debug_skip_minutes(10)
	check(target.construction_progress==17,"No contribution after interrupt")
	resume(world,actor)
	world.game_time.debug_skip_minutes(13)
	check(target.construction_progress==30 and actor.data.get_skill_xp(Skill.CONSTRUCTION)==0,"Resume adds13, no partial-cycle XP")
	world.free()
	world=fixture()
	target=target_for(world)
	actor=start(world)
	var second=start(world,3)
	world.game_time.debug_skip_minutes(10)
	check(target.construction_progress==20,"Two independent Builders add20 in10minutes")
	world.game_time.debug_skip_minutes(50)
	check(target.construction_progress==120 and actor.data.get_skill_xp(Skill.CONSTRUCTION)==1 and second.data.get_skill_xp(Skill.CONSTRUCTION)==1,"Two full cycles give120 and one XP each")
	world.free()
	world=fixture()
	target=target_for(world)
	target.add_construction_work(177)
	actor=start(world)
	world.game_time.debug_skip_minutes(3)
	check(target.is_built() and target.construction_progress==180 and actor.builder.phase==B.Phase.NONE and target.active_builder_ids.is_empty(),"Mid-cycle completion after3 immediately cleans lifecycle")
	check(actor.data.get_skill_xp(Skill.CONSTRUCTION)==0,"Completion in partial cycle grants no bonus XP")
	world.free()
	for before_tick in [true,false]:
		world=fixture()
		target=target_for(world)
		target.add_construction_work(179)
		actor=start(world)
		var edge: Callable = func():
			if target.construction_progress==180: actor.commands.move_to(Vector2(0,500))
		if before_tick: actor.commands.move_to(Vector2(0,500))
		else: target.construction_changed.connect(edge)
		world.game_time.debug_skip_minutes(1)
		check(target.construction_progress==(179 if before_tick else 180) and target.is_built()==not before_tick and actor.builder.phase==B.Phase.NONE and target.active_builder_ids.is_empty(),"Deterministic interruption/completion edge")
		if not before_tick: target.construction_changed.disconnect(edge)
		edge=Callable()
		world.free()
	world=fixture()
	target=target_for(world)
	world.game_time.total_minutes=1008
	actor=start(world)
	world.game_time.debug_skip_minutes(12)
	check(target.construction_progress==12 and actor.builder.phase==B.Phase.NONE,"Last12 working minutes preserved at17:00")
	world.game_time.debug_skip_minutes(15)
	check(target.construction_progress==12,"No evening contribution")
	world.free()
	world=fixture()
	target=target_for(world)
	actor=start(world)
	world.game_time.debug_skip_minutes(17)
	actor.decision._deciding=false
	actor.data.fatigue=100
	check(target.construction_progress==17 and actor.builder.phase==B.Phase.NONE,"Critical sleep preserves already applied17")
	actor.decision._deciding=true
	world.game_time.debug_skip_minutes(10)
	check(target.construction_progress==17,"No work during critical sleep")
	world.free()
	for fps in [30,144]:
		for speed in [1,20]:
			world=fixture()
			target=target_for(world)
			actor=start(world)
			world.game_time.set_speed(speed)
			for frame in range(fps*30): world.game_time.advance(1.000001/float(fps*speed))
			check(target.construction_progress==30,"Equal game time at30/144FPS andx1/x20")
			paused=true
			world.game_time.advance(10)
			paused=false
			check(target.construction_progress==30,"Pause cannot accrue work")
			world.free()
	print("Incremental construction: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
