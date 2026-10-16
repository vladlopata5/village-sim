extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(4000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes = 420
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.view.set_physics_process(false)
		actor.intents.abort_current(actor.intents.current_intent)
		for need in actor.data.needs.values(): need.value=0
	await physics_frame
	var hut = preload("res://scripts/building_instance.gd").new(&"internal_hut",preload("res://scripts/building_definition.gd").for_type(BT.LUMBERJACK_HUT),C.to_sim(Vector3(12,0,-12)))
	world.buildings.append(hut)
	world._show_building(hut)
	var actor = world.resident_runtimes[3]
	check(world.player_control.assign_workplace(actor.data.id,hut.id),"Assign worker through player control")
	var drop = Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(8,0,-12)))
	var ref := Source.new(Source.Kind.GROUND,drop.id)
	var job = world.logistics.claim_internal(actor.data.id,ref,hut,R.LOG,func(): return true)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Internal physical haul starts")
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1,"Loading consumes ground exactly once")
	world.player_control.clear_work_assignment(actor.data.id)
	walk(actor)
	check((actor.view._marker!=null),"Captured destination enters internal courier slot")
	world.game_time.debug_skip_minutes(10)
	check(job.state==Job.State.COMPLETED and hut.resources.get_amount(R.LOG)==1 and actor.data.inventory.amount==0,"Delivery finishes after reassignment")
	check(not (actor.view._marker!=null) and hut.resources.get_reserved_in(R.LOG)==0,"Portal exit and inbound release")
	world.player_control.assign_workplace(actor.data.id,hut.id)
	drop = Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(8,0,-12)))
	ref = Source.new(Source.Kind.GROUND,drop.id)
	job = world.logistics.claim_internal(actor.data.id,ref,hut,R.LOG,func(): return true)
	world.logistics.start_claimed_job(job,actor.data.id)
	check(world.logistics._executors[actor.data.id].cancel("before pickup"),"Forced cancellation before pickup")
	check(drop.reservation_owner_id.is_empty() and hut.resources.get_reserved_in(R.LOG)==0,"Ground claim and inbound released")
	job = world.logistics.claim_internal(actor.data.id,ref,hut,R.LOG,func(): return true)
	world.logistics.start_claimed_job(job,actor.data.id)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	world.logistics._executors[actor.data.id].cancel("after pickup")
	check(actor.data.inventory.amount==0 and hut.resources.get_reserved_in(R.LOG)==0,"Cargo cleanup after pickup")
	check(Stacks.total(world.ground_resources)==1 and world.ground_resources.drops[0].amount==1,"Cancelled cargo remains exactly once")
	var export_job = world.logistics.claim_own_export(actor.data.id,world.warehouse_data)
	check(export_job!=null and world.logistics.start_claimed_job(export_job,actor.data.id),"Legacy forestry export delegates generic mechanism")
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	check(export_job.state==Job.State.COMPLETED and actor.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.LOGISTICS)==1,"Legacy completed export XP preserved")
	# An occupied interior courier waits without starting unload, then forced command cleans cargo.
	drop = Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(8,0,-12)))
	ref = Source.new(Source.Kind.GROUND,drop.id)
	job = world.logistics.claim_internal(actor.data.id,ref,hut,R.LOG,func(): return true)
	world.logistics.start_claimed_job(job,actor.data.id)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	var holder = world.building_uses.acquire(hut.id,1,"fixture_holder",C.to_world(hut.position))
	walk(actor)
	check(actor.view._waiting and not world.logistics._executors[actor.data.id].handling.is_active(),"Occupied courier waits before unloading")
	world.player_control.move_to(actor.data.id,C.to_sim(Vector3(0,0,-10)))
	check(job.state==Job.State.CANCELLED and hut.resources.get_reserved_in(R.LOG)==0 and actor.data.inventory.amount==0,"Forced cancel while waiting releases inbound and drops cargo")
	world.building_uses.release(hut.id,holder,"fixture_holder")
	await process_frame
	check(actor.view._marker==null,"Deferred slot wake cannot reenter cancelled delivery")
	actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
	# Reentrant interruption exactly during portal acquisition must release the new marker too.
	drop = Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(8,0,-12)))
	ref = Source.new(Source.Kind.GROUND,drop.id)
	job = world.logistics.claim_internal(actor.data.id,ref,hut,R.LOG,func(): return true)
	world.logistics.start_claimed_job(job,actor.data.id)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	var entry_interrupt := func(id: StringName, purpose: int):
		if id==hut.id and purpose==1 and world.building_uses.occupied_by(id,actor.data.id,1): world.player_control.move_to(actor.data.id,C.to_sim(Vector3(0,0,-10)))
	world.building_uses.slots_changed.connect(entry_interrupt)
	walk(actor)
	world.building_uses.slots_changed.disconnect(entry_interrupt)
	check(job.state==Job.State.CANCELLED and actor.view._marker==null and not world.building_uses.occupied_by(hut.id,actor.data.id,1),"Portal entry interruption releases newly acquired marker")
	check(hut.resources.get_reserved_in(R.LOG)==0 and actor.data.inventory.amount==0,"Portal entry interruption preserves cleanup invariants")
	actor.commands.cancel_current()
	world.free()
	print("Internal physical haul: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
