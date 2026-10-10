extends SceneTree
const Handling = preload("res://scripts/resource_handling.gd")
const Def = preload("res://scripts/building_definition.gd")
const B = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const S = preload("res://scripts/resource_source_ref.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const G = preload("res://scripts/world_3d/world_geometry.gd")
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
const Job = preload("res://scripts/haul_job.gd")
var checks := 0
var failures := 0
var world: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(3000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func minutes(amount: int) -> void: world.game_time.advance(float(amount)/world.game_time.speed_multiplier)
func building(type: int, point: Vector3, built: bool = true, turns: int = 0):
	var data = B.new(StringName("handling_%d"%world.buildings.size()),Def.for_type(type),C.to_sim(point),B.State.BUILT if built else B.State.UNDER_CONSTRUCTION)
	data.quarter_turns=turns
	world.buildings.append(data)
	world._show_building(data)
	return data
func reset(actor: Node) -> void:
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.activity=0
	for need in actor.data.needs.values(): need.value=0
func haul(actor: Node, source: RefCounted, target: RefCounted, resource: int):
	var job = world.logistics.claim_transport(actor.data.id,source,target,resource,func(): return true)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Real committed transport starts")
	return job
func capture(label: String, actor: Node) -> void:
	if not "--render-qa" in OS.get_cmdline_user_args(): return
	world.game_time.phase_changed.emit(world.game_time.get_phase())
	world.game_time.minute_changed.emit(world.game_time.total_minutes)
	world.resident_selection.select(actor.data)
	var camera := world.get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z
	var center := camera.global_position + forward*(-camera.global_position.y/forward.y)
	var focus: Vector3 = actor.view.global_position
	camera.global_position += Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.size=18
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/courier_qa")
	world.get_viewport().get_texture().get_image().save_png("res://.godot/courier_qa/%s.png"%label)

func run() -> void:
	var timer=Handling.new()
	check(timer.start(&"loading",100,10) and not timer.start(&"unloading",100,10),"Timer is one active operation")
	check(not timer.advance(109) and timer.advance(110) and not timer.advance(110),"9/10 and repeated callback boundary")
	timer.start(&"loading",200,10)
	timer.cancel()
	check(not timer.advance(300),"Cancellation consumes timer")
	world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for resident in world.resident_runtimes:
		resident.decision._deciding=true
		resident.view.set_physics_process(false)
		reset(resident)
	await physics_frame
	var source=world.buildings[0]
	var kitchen=building(Types.FOOD,Vector3(22,0,-5))
	var actor=world.resident_runtimes[0]
	for speed in [1,2,4,10,20]:
		world.game_time.set_speed(speed)
		var before: int=kitchen.resources.get_amount(R.FOOD)
		var stock: int=source.resources.get_amount(R.FOOD)
		var job=haul(actor,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
		walk(actor)
		check(actor.view.global_position.is_equal_approx(world.building_uses.courier_position(source.id)) and not G.footprint(source).has_point(C.world_plane(actor.view.global_position)),"Loading physically reaches exterior Courier, no teleport")
		check(world.building_uses.occupied_by(source.id,actor.data.id,Purpose.COURIER) and world.world_locations.get_view(source.id).inside_count==0,"Courier stays occupied without interior transparency")
		if speed==1: await capture("source_loading",actor)
		minutes(9)
		check(source.resources.get_amount(R.FOOD)==stock and actor.data.inventory.amount==0,"9 minutes leaves stock at source")
		paused=true
		minutes(100)
		check(actor.data.inventory.amount==0,"Pause cannot advance handling")
		paused=false
		minutes(1)
		check(actor.data.inventory.amount==1 and source.resources.get_amount(R.FOOD)==stock-1,"10 minutes transfers once to inventory at every speed")
		world.logistics._executors[actor.data.id]._on_minute(world.game_time.total_minutes)
		check(source.resources.get_amount(R.FOOD)==stock-1,"Duplicate minute cannot repeat pickup")
		walk(actor)
		if speed==1: await capture("kitchen_unloading",actor)
		minutes(9)
		check(actor.data.inventory.amount==1 and kitchen.resources.get_amount(R.FOOD)==before,"9 unload minutes retains cargo and inbound")
		minutes(1)
		check(job.state==Job.State.COMPLETED and actor.data.inventory.amount==0 and kitchen.resources.get_amount(R.FOOD)==before+1,"Unloading commits exactly once")
		check(source.resources.get_reserved_out(R.FOOD)==0 and kitchen.resources.get_reserved_in(R.FOOD)==0 and actor.view._marker==null,"Completion releases reservations and physical slot")
		reset(actor)
	# Two genuine executors compete; the waiting job retains its resource promises.
	var second=world.resident_runtimes[3]
	reset(second)
	kitchen.resources.try_take(R.FOOD,kitchen.resources.get_amount(R.FOOD))
	var first_job=haul(actor,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
	walk(actor)
	var second_job=haul(second,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
	walk(second)
	check(world.building_uses.occupied_by(source.id,actor.data.id,Purpose.COURIER) and not world.building_uses.occupied_by(source.id,second.data.id,Purpose.COURIER),"One Courier occupant; competing resident waits outside")
	check(not world.logistics._executors[second.data.id].handling.is_active() and source.resources.get_reserved_out(R.FOOD)==2,"Waiting does not start timer or lose reservations")
	await capture("courier_competition",actor)
	minutes(10)
	await process_frame # Slot availability is deliberately retried through deferred events.
	walk(second)
	check(world.building_uses.occupied_by(source.id,second.data.id,Purpose.COURIER) and world.logistics._executors[second.data.id].handling.is_active(),"Slot release event starts waiting courier")
	reset(actor)
	reset(second)
	check(first_job.state==Job.State.CANCELLED and second_job.state==Job.State.CANCELLED and source.resources.get_reserved_out(R.FOOD)==0 and kitchen.resources.get_reserved_in(R.FOOD)==0,"Competing cancellation cleans both jobs and slot")
	# Courier geometry remains walkable for every orientation and construction lifecycle.
	for type in Types.values():
		var layout=preload("res://scripts/world_3d/building_layouts_3d.gd").create(Def.for_type(type))
		check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(layout,Def.for_type(type)),"Authored external courier geometry validated")
		layout.free()
	for type in Types.values():
		for turn in range(4):
			var house=building(type,Vector3(-45+turn*10,0,26),false,turn)
			check(world.building_uses.courier_position(house.id) is Vector3,"Every building type/rotation has walkable construction Courier")
			var marker=world.building_uses.acquire(house.id,Purpose.COURIER,"courier_probe",Vector3.ZERO)
			check(marker!=null and world.building_uses.acquire(house.id,Purpose.COURIER,"courier_probe",Vector3.ZERO)==null,"No duplicate acquisition")
			world.building_uses.release(house.id,marker,"courier_probe")
			world.cancel_construction(house.id)
	# Ground expiration during timed loading releases inbound, creates no cargo.
	var loose=world.ground_resources.create_drop(R.FOOD,1,C.to_sim(Vector3(-8,0,20)))
	var job=haul(actor,S.new(S.Kind.GROUND,loose.id),kitchen,R.FOOD)
	walk(actor)
	minutes(9)
	world.ground_resources._on_minute(loose.created_at+loose.lifetime)
	minutes(1)
	check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and kitchen.resources.get_reserved_in(R.FOOD)==0,"Despawn during loading cleans both promises")
	reset(actor)
	# Forced command during either operation cleans timer, slot, reservations.
	for after_pickup in [false,true]:
		job=haul(actor,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
		walk(actor)
		if after_pickup:
			minutes(10)
			walk(actor)
		minutes(4)
		var drops: int=world.ground_resources.drops.size()
		world.player_control.move_to(actor.data.id,C.to_sim(Vector3(0,0,-10)))
		check(job.state==Job.State.CANCELLED and actor.view._marker==null and not world.logistics._executors[actor.data.id].handling.is_active(),"MOVE_TO cancels handling and physical occupancy")
		check(world.ground_resources.drops.size()==drops+(1 if after_pickup else 0) and kitchen.resources.get_reserved_in(R.FOOD)==0,"Only already picked cargo becomes Ground")
		actor.commands.cancel_current()
		reset(actor)
	# Critical fatigue interrupts both timed stages through the normal needs pipeline.
	for after_pickup in [false,true]:
		job=haul(actor,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
		walk(actor)
		if after_pickup:
			minutes(10)
			walk(actor)
		minutes(4)
		var drops: int=world.ground_resources.drops.size()
		actor.decision._deciding=false
		actor.data.fatigue=100
		actor.decision._deciding=true
		check(job.state==Job.State.CANCELLED and actor.view._marker==null and not world.logistics._executors[actor.data.id].handling.is_active(),"Critical fatigue cancels timer and Courier at either stage")
		check(world.ground_resources.drops.size()==drops+(1 if after_pickup else 0) and kitchen.resources.get_reserved_in(R.FOOD)==0,"Critical cleanup drops only actual picked cargo")
		reset(actor)
	# Committed delivery crosses 17:00; work eligibility still rejects new tasks.
	world.game_time.total_minutes=1015
	job=haul(actor,S.new(S.Kind.CONTAINER,source.id),kitchen,R.FOOD)
	walk(actor)
	minutes(10)
	walk(actor)
	minutes(10)
	check(job.state==Job.State.COMPLETED and not world.logistics._executors[actor.data.id].can_start(),"Delivery finishes after17, no new evening delivery")
	# Lumberjack's separate Ground collect flow uses the same one-shot delay.
	world.game_time.total_minutes=420
	var lumberjack=world.resident_runtimes[3]
	reset(lumberjack)
	var hut=building(Types.LUMBERJACK_HUT,Vector3(35,0,-20))
	check(world.player_control.assign_profession(lumberjack.data.id,P.LUMBERJACK) and world.player_control.assign_workplace(lumberjack.data.id,hut.id),"Lumberjack assigned through existing management")
	var logs=world.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(28,0,-20)))
	reset(lumberjack)
	var collector=lumberjack.get_node("Lumberjack")
	check(collector.request_work() and collector.kind==&"COLLECT","Lumberjack chooses Ground collection")
	walk(lumberjack)
	await capture("lumberjack_ground_loading",lumberjack)
	minutes(9)
	check(logs.amount==1 and lumberjack.data.inventory.amount==0,"Lumberjack Ground stock remains until loading end")
	minutes(1)
	walk(lumberjack)
	check(world.building_uses.occupied_by(hut.id,lumberjack.data.id,Purpose.COURIER),"Lumberjack unloads at external Hut Courier")
	await capture("hut_unloading",lumberjack)
	minutes(9)
	check(hut.resources.get_amount(R.LOG)==0 and lumberjack.data.inventory.amount==1,"Lumberjack keeps cargo until unloading end")
	minutes(1)
	check(hut.resources.get_amount(R.LOG)==1 and lumberjack.data.inventory.amount==0,"Lumberjack completes exactly one LOG delivery")
	reset(lumberjack)
	# Ground Builder loading and construction-only Courier unloading are separate from work.
	world.game_time.total_minutes=420
	var builder=world.resident_runtimes[1]
	reset(builder)
	world.player_control.assign_profession(builder.data.id,P.BUILDER)
	var site=building(Types.HOME,Vector3(-20,0,-20),false)
	site.add_delivered_material(R.PLANK,9)
	var planks=world.ground_resources.create_drop(R.PLANK,1,C.to_sim(Vector3(-10,0,-20)))
	reset(builder)
	check(builder.builder.request_work(),"Builder starts Ground material workflow")
	walk(builder)
	minutes(9)
	await capture("builder_ground_loading",builder)
	check(planks.amount==1 and builder.data.inventory.amount==0,"Builder waits before Ground pickup")
	minutes(1)
	walk(builder)
	check(world.building_uses.occupied_by(site.id,builder.data.id,Purpose.COURIER) and not world.building_uses.occupied_by(site.id,builder.data.id,Purpose.CONSTRUCTION),"Builder unloads at Courier, not work slot")
	await capture("construction_unloading",builder)
	minutes(9)
	check(site.get_delivered_amount(R.PLANK)==9 and site.construction_progress==0 and builder.data.inventory.amount==1,"Unloading does not accrue construction work")
	minutes(1)
	walk(builder)
	check(site.are_construction_materials_complete() and builder.builder.phase==4 and world.building_uses.occupied_by(site.id,builder.data.id,Purpose.CONSTRUCTION),"Delivery resumes actual construction at separate slot")
	await capture("construction_work",builder)
	reset(builder)
	world.cancel_construction(site.id)
	var cancelled_site=building(Types.HOME,Vector3(-25,0,-20),false)
	cancelled_site.add_delivered_material(R.PLANK,9)
	world.ground_resources.create_drop(R.PLANK,1,C.to_sim(Vector3(-17,0,-20)))
	check(builder.builder.request_work(),"Builder claims another construction delivery")
	walk(builder)
	minutes(10)
	walk(builder)
	check(builder.data.inventory.amount==1 and world.building_uses.occupied_by(cancelled_site.id,builder.data.id,Purpose.COURIER),"Cancellation fixture reaches active construction unloading")
	var drops: int=world.ground_resources.drops.size()
	check(world.cancel_construction(cancelled_site.id),"Construction cancellation follows existing lifecycle")
	check(builder.data.inventory.amount==0 and not builder.builder.handling.is_active() and builder.view._marker==null and cancelled_site.get_construction_reserved_in(R.PLANK)==0,"UC cancellation clears handling, cargo, slot and construction ledger")
	check(world.ground_resources.drops.size()==drops+1 and cancelled_site.construction_progress==0,"UC cancellation drops carried material without work contribution")
	world.free()
	print("Resource handling: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
