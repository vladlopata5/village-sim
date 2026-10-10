extends SceneTree
const Types = preload("res://scripts/building_type.gd").Type
const Def = preload("res://scripts/building_definition.gd")
const R = preload("res://scripts/resource_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const Phase = preload("res://scripts/resident_builder_controller.gd").Phase
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(message,": ",ok)
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(8000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func construct(world: Node, actor: Node, type: int, point: Vector3):
	world.placement.select(Def.for_type(type))
	world.placement.update_world_position(point)
	var site = world.placement.confirm()
	check(site != null,"Bootstrap building placed through existing BuildGrid")
	if site == null: return null
	for cycle in range(8):
		if site.is_built(): break
		world.game_time.total_minutes = 420
		actor.schedule._phase = "День"
		check(world._request_work(actor),"Normal Builder request uses Town Center PLANK")
		walk(actor)
		check(actor.builder.phase==Phase.BUILDING,"Physical supply trips reach valid construction access point")
		world.game_time.total_minutes += Balance.BUILDER_WORK_CYCLE_MINUTES
		actor.builder._on_minute(world.game_time.total_minutes)
	check(site.is_built(),"Delivered materials and actual construction work complete bootstrap building")
	return site
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.game_time.total_minutes=420
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.schedule._phase="День"
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
	await physics_frame
	var center = world.buildings[0]
	var builder = world.resident_runtimes[1]
	check(world.player_control.assign_profession(builder.data.id,Profession.BUILDER),"Player assigns Builder without an artificial workplace")
	var hut = construct(world,builder,Types.LUMBERJACK_HUT,Vector3(-18,0,-5))
	var saw = construct(world,builder,Types.SAWMILL,Vector3(22,0,8))
	var gather = construct(world,builder,Types.GATHERER_HUT,Vector3(-8,0,8))
	var kitchen = construct(world,builder,Types.FOOD,Vector3(22,0,-3))
	if hut==null or saw==null or gather==null or kitchen==null:
		world.free()
		quit(1)
		return
	check(center.resources.get_amount(R.PLANK)==10,"50 PLANK physically supplied from starter stock, leaving ten")
	world.game_time.total_minutes=420
	var lumber = world.resident_runtimes[3]
	check(world.player_control.assign_workplace(lumber.data.id,hut.id) and world._request_work(lumber),"Normal Lumberjack work selects a reachable standing tree")
	walk(lumber)
	world.game_time.debug_skip_minutes(Balance.TREE_WORK_MINUTES)
	check(world.ground_resources.drops.size()==3,"Real chopping produces three LOG")
	check(world._request_work(lumber),"Normal Lumberjack collects its local physical LOG")
	walk(lumber)
	check(hut.resources.get_amount(R.LOG)==1,"LOG physically carried into built Lumberjack Hut")
	# Test existing own-export eligibility/execution independently of forestry's
	# unchanged CHOP/COLLECT/PLANT-before-EXPORT candidate ordering.
	var export = world.logistics.claim_own_export(lumber.data.id,center)
	check(export!=null and world.logistics.start_claimed_job(export,lumber.data.id),"Lumberjack own-export can target storage-capable Town Center")
	walk(lumber)
	check(center.resources.get_amount(R.LOG)==1 and hut.resources.get_amount(R.LOG)==0,"Lumberjack export physically reaches Town Center")
	var sawyer = world.resident_runtimes[2]
	check(world.player_control.assign_workplace(sawyer.data.id,saw.id) and world._request_work(sawyer),"Sawyer self-supply selects a real LOG source")
	walk(sawyer)
	check(saw.resources.get_amount(R.LOG)==1,"Sawyer physically supplies one LOG")
	check(world._request_work(sawyer),"Sawyer begins unchanged production recipe")
	walk(sawyer)
	world.game_time.debug_skip_minutes(Balance.SAWMILL_WORK_MINUTES)
	check(saw.resources.get_amount(R.PLANK)==1,"Sawyer transforms LOG into PLANK")
	# Ground is globally available; reserve the remaining two drops temporarily
	# to expose EXPORT without changing self-supply priority or resource balance.
	for drop in world.ground_resources.drops: drop.reserve(&"bootstrap_competitor")
	var held_logs: int = center.resources.get_available_amount(R.LOG)
	center.resources.reserve_out(R.LOG,held_logs)
	check(world._request_work(sawyer),"Sawyer self-export selects Town Center when supply is unavailable")
	walk(sawyer)
	check(center.resources.get_amount(R.PLANK)==11,"Produced PLANK physically returns to Town Center")
	center.resources.release_out(R.LOG,held_logs)
	for drop in world.ground_resources.drops: drop.release(&"bootstrap_competitor")
	builder.intents.abort_current(builder.intents.current_intent)
	check(world.player_control.assign_workplace(builder.data.id,gather.id) and world._request_work(builder),"Gatherer begins normal work at player-built Hut")
	walk(builder)
	world.game_time.debug_skip_minutes(Balance.WORK_CYCLE_MINUTES)
	for cycle in range(2):
		check(world._request_work(builder),"Next Gatherer cycle goes through ordinary work decision")
		walk(builder)
		world.game_time.debug_skip_minutes(Balance.WORK_CYCLE_MINUTES)
	check(gather.resources.get_amount(R.FOOD)==5,"Gatherer unchanged production fills five-unit output")
	builder.intents.abort_current(builder.intents.current_intent)
	check(world._request_work(builder),"Full output starts Gatherer self-export")
	walk(builder)
	check(center.resources.get_amount(R.FOOD)==21,"Gatherer FOOD physically reaches Town Center")
	var porter = world.resident_runtimes[0]
	check(world._request_work(porter),"Town Center-based Porter has ordinary delivery work")
	walk(porter)
	for trip in range(12):
		if kitchen.resources.get_amount(R.FOOD)>0: break
		if not world._request_work(porter): break
		walk(porter)
	check(kitchen.resources.get_amount(R.FOOD)>0,"Porter physically supplies the player-built Kitchen")
	check(world.player_control.assign_profession(builder.data.id,Profession.BUILDER),"Builder profession can be reassigned after self-export")
	var home = construct(world,builder,Types.HOME,Vector3(22,0,18))
	check(home!=null and world.player_control.assign_home(builder.data.id,home.id),"Player-built normal home can be assigned")
	for actor in world.resident_runtimes:
		actor.intents.abort_current(actor.intents.current_intent)
		actor.schedule._on_phase_changed("Ночь")
		walk(actor)
	check(builder.schedule._fallback_id.is_empty() and builder.data.current_sleep_quality==1.0 and builder.view.get_sim_position().is_equal_approx(world.world_locations.get_position(home.id)),"Assigned resident physically sleeps at HOME rather than Town Center")
	check(world.fallback_housing.count(center.id)==3 and world.resident_runtimes.all(func(actor): return actor.data.activity==preload("res://scripts/resident_activity.gd").Type.SLEEPING),"Remaining three homeless residents physically sleep at Town Center")
	world.free()
	print("Town Center bootstrap: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
