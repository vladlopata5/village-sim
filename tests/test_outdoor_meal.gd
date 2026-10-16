extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const B = preload("res://scripts/building_instance.gd")
const Def = preload("res://scripts/building_definition.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const A = preload("res://scripts/resident_activity.gd").Type
var checks := 0
var failures := 0
var trace: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes = 420
	world.game_ui.time_controls.request_clock_refresh()
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
		actor.data.hunger = 80
	for place in world.buildings: place.resources.try_take(R.FOOD,place.resources.get_available_amount(R.FOOD))
	return world
func building(world: Node, type: int):
	if type == T.TOWN_CENTER: return world.warehouse_data
	var data = B.new(StringName("outdoor_%d" % world.buildings.size()),Def.for_type(type),C.to_sim(Vector3(-10,0,16)))
	world.buildings.append(data)
	world._show_building(data)
	return data
func walk(actor: Node) -> void:
	var expected = actor.intents.current_intent
	for step in range(12000):
		if actor.intents.current_intent != expected or actor.needs._meal_active or actor.view._waiting or not actor.view.movement.is_moving(): break
		actor.view._physics_process(0.05)
func transport_walk(actor: Node) -> void:
	for step in range(12000):
		if actor.view._waiting or not actor.view.movement.is_moving(): break
		actor.view._physics_process(0.05)
func remove(world: Node, data: RefCounted) -> void:
	var view = world.world_locations.get_view(data.id)
	world.buildings.erase(data)
	world.logistics.remove_building(data.id)
	world.building_uses.unregister(data.id)
	world.world_locations.unregister(data.id)
	world.build_grid.release(data.id)
	world.entrance_zones.release(data.id)
	world.navigation.remove_blocker(data.id)
	if is_instance_valid(view): view.free()
func capture(world: Node, actor: Node, label: String) -> void:
	if not "--rendered" in OS.get_cmdline_user_args(): return
	world.resident_selection.select(actor.data)
	world.get_node("HUD").find_child("ExtendedContent",true,false).visible = false
	var camera := root.get_camera_3d()
	var forward := -camera.global_basis.z
	var center := camera.global_position + forward*(-camera.global_position.y/forward.y)
	var focus: Vector3 = actor.view.global_position
	camera.global_position += Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.set_zoom_distance(14 / (2 * tan(deg_to_rad(camera.fov / 2))))
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/outdoor-meal-lifecycle/"+label+".png") == OK,"Rendered lifecycle snapshot")
func run() -> void:
	var world: Node
	var actor: Node
	var intent: RefCounted
	var source: RefCounted
	# Real Kitchen/Other sources, portal callbacks and committed action parameters.
	for type in [T.FOOD,T.TOWN_CENTER,T.STORAGE,T.GATHERER_HUT]:
		world = fixture()
		actor = world.resident_runtimes[1]
		source = building(world,type)
		source.resources.add(R.FOOD,1)
		var receipt: Array = []
		var releases: Array = []
		var on_take := func(resource, _available):
			if resource == R.FOOD and actor.needs._food_received:
				receipt.append(actor.view.get_world_position())
				check(not actor.needs._meal_active and actor.needs._minutes_left == 0,"Pickup does not start timer/satiety before exit")
				check(world.building_uses.occupied_by(source.id,actor.data.id,2 if type==T.FOOD else 1),"Pickup owns the original interior slot")
				actor.needs._on_arrival(actor.intents.current_intent)
		var on_release := func(id, purpose):
			if type != T.FOOD and id == source.id and purpose == 1 and actor.needs._food_received and not world.building_uses.occupied_by(id,actor.data.id,1):
				releases.append(actor.view.get_world_position())
				check(not actor.needs._meal_active and actor.needs._minutes_left == 0 and actor.needs.get_hunger_eating_rate()==0,"Release callbacks occur before outdoor EAT timer/rate")
				check(actor.view._marker == null and actor.view._building.is_empty() and world.navigation.is_world_walkable(actor.view.global_position),"Portal position outside before release notification")
		source.resources.changed.connect(on_take)
		world.building_uses.slots_changed.connect(on_release)
		check(actor.needs.try_eat(8000),"Food source starts normal EAT")
		intent = actor.intents.current_intent
		check(source.resources.get_amount(R.FOOD)==1 and source.resources.get_reserved_out(R.FOOD)==1,"Trip only reserves")
		walk(actor)
		var minutes := 30 if type == T.FOOD else 10
		check(actor.needs._meal_active and actor.needs._minutes_left == minutes and actor.data.hunger==80,"Timer begins once after real arrival/exit")
		check(source.resources.get_amount(R.FOOD)==0 and source.resources.get_reserved_out(R.FOOD)==0 and receipt.size()==1,"Exactly one physical FOOD pickup")
		if type == T.FOOD:
			check(actor.view._marker!=null and releases.is_empty() and actor.needs.meal_location_id()==source.id and actor.needs.get_hunger_eating_rate()==-120,"Kitchen retains original VISITOR/context/rate")
		else:
			check(actor.view._marker==null and releases.size()==1 and actor.needs.meal_location_id().is_empty() and actor.needs.get_hunger_eating_rate()==-360,"Other building EAT has no interior slot/context")
			check(not receipt[0].is_equal_approx(releases[0]) and releases[0].is_equal_approx(world.building_uses.entrance(source.id)),"Executor moved through its existing portal to entrance")
			check(actor.view.exit_for_action(intent) and releases.size()==1,"Repeated exit is idempotent and does not release twice")
		await capture(world,actor,"source_%d_outside" % type)
		world.game_time.advance(float(minutes-1))
		check(actor.needs._meal_active and actor.needs._minutes_left==1 and actor.data.hunger==80-(minutes-1)*(2 if type==T.FOOD else 6),"Game-time rate and exact last minute")
		world.game_time.advance(1.0)
		check(actor.data.hunger==20 and not actor.needs._meal_active and not actor.needs._food_received and actor.view._marker==null,"Full meal delivers same sixty-point effect and cleanup")
		world.game_time.advance(1.0)
		check(actor.data.hunger==20,"No second satiety after completion")
		trace.append({"type":type,"pickup":str(receipt[0]),"outside":str(releases[0]) if not releases.is_empty() else "Kitchen","minutes":minutes})
		source.resources.changed.disconnect(on_take)
		world.building_uses.slots_changed.disconnect(on_release)
		world.free()
	# Ground multi-amount, critical merge and pause/speed changes.
	world = fixture()
	actor = world.resident_runtimes[1]
	var drop = Stacks.create(world.ground_resources,R.FOOD,4,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000),"Ground action starts")
	walk(actor)
	intent = actor.intents.current_intent
	check(drop.amount==3 and drop.reservation_owner_id.is_empty() and actor.data.inventory.amount==0 and actor.view._marker==null,"Ground takes one portion without cargo/COURIER")
	check(actor.needs.try_eat(8000,200) and actor.intents.current_intent==intent and actor.needs._minutes_left==10,"Critical merge retains outdoor timer and single pickup")
	paused=true
	world.game_time.advance(100.0)
	check(actor.needs._minutes_left==10 and actor.data.hunger==80,"Pause does not advance meal")
	paused=false
	world.game_time.advance(2.0)
	world.game_time.set_speed(4)
	world.game_time.advance(1.0)
	world.game_time.set_speed(20)
	world.game_time.advance(0.2)
	check(not actor.needs._meal_active and actor.data.hunger==20 and drop.amount==3,"x1/x4/x20 change preserves exactly ten game minutes")
	world.free()
	# Interrupt before pickup, after paid exit and during outdoor eating.
	for stage in ["reserved","release","eating"]:
		world=fixture()
		actor=world.resident_runtimes[1]
		source = building(world,T.STORAGE)
		source.resources.add(R.FOOD,1)
		var on_release := func(id,purpose):
			if stage=="release" and id==source.id and purpose==1 and actor.needs._food_received and not world.building_uses.occupied_by(id,actor.data.id,1): actor.commands.move_to(C.to_sim(Vector3(0,0,20)))
		world.building_uses.slots_changed.connect(on_release)
		check(actor.needs.try_eat(8000),"Interrupt scenario begins")
		if stage != "reserved": walk(actor)
		if stage=="eating": world.game_time.advance(3.0)
		if stage != "release": actor.commands.move_to(C.to_sim(Vector3(0,0,20)))
		check(source.resources.get_amount(R.FOOD)==(1 if stage=="reserved" else 0) and source.resources.get_reserved_out(R.FOOD)==0,"Cancel refunds only an unreceived reserve")
		check(not actor.needs._meal_active and not actor.needs._food_received and actor.needs._active_intent==null and actor.view._marker==null and not actor.view._waiting,"Cancellation clears paid stage/timer/COURIER")
		check(actor.data.hunger==(62 if stage=="eating" else 80) and actor.commands.active_command!=null,"Forced command preserves only earned benefit")
		world.game_time.advance(3.0)
		check(actor.data.hunger==(62 if stage=="eating" else 80),"Cancelled meal does not continue recovery")
		transport_walk(actor)
		check(actor.commands.active_command==null,"Forced movement completes after cancellation")
		world.building_uses.slots_changed.disconnect(on_release)
		world.free()
	# Real Porter waits while FOOD is taken, then unloads during the outside meal.
	world=fixture()
	actor=world.resident_runtimes[1]
	var porter=world.resident_runtimes[0]
	porter.data.hunger=0
	world.warehouse_data.resources.add(R.FOOD,1)
	Stacks.create(world.ground_resources,R.LOG,1,porter.view.get_drop_sim_position()+Vector2(25,0))
	var job=world.logistics.claim_best_job(porter.data.id)
	check(job!=null and world.logistics.start_claimed_job(job,porter.data.id),"Ordinary valid Porter haul is physically started")
	transport_walk(porter)
	world.game_time.advance(10.0)
	var callback := func(resource,_available):
		if resource==R.FOOD and actor.needs._food_received and not actor.needs._meal_active:
			transport_walk(porter)
			check(porter.view._waiting and actor.view._marker!=null,"Porter waits at occupied COURIER during actual FOOD pickup")
	world.warehouse_data.resources.changed.connect(callback)
	check(actor.needs.try_eat(8000),"Eater competes with Porter for actual Town Center")
	walk(actor)
	check(actor.needs._meal_active and actor.view._marker==null and actor.view._building.is_empty(),"Eater outside without interior ownership")
	await process_frame
	check(porter.view._marker!=null and not porter.view._waiting and actor.needs._minutes_left==10,"Porter enters before eater has consumed any outdoor meal minutes")
	await capture(world,actor,"porter_inside_eater_outside")
	var before: int=actor.data.hunger
	world.game_time.advance(10.0)
	check(job.state==preload("res://scripts/haul_job.gd").State.COMPLETED and porter.data.inventory.amount==0 and world.warehouse_data.resources.get_amount(R.LOG)==1,"Physical Porter unloading completes with exactly one LOG")
	check(not actor.needs._meal_active and actor.data.hunger in [before-60,before-59],"Independent outdoor EAT completes with existing fixed-point rounding")
	check(world.building_uses.inside_count(world.warehouse_data.id)==0 and world.warehouse_data.resources.get_reserved_in(R.LOG)==0,"Both visits leave no occupancy or inbound")
	world.warehouse_data.resources.changed.disconnect(callback)
	world.free()
	# Removal before pickup/wait and after paid pickup on both sides of portal release.
	for stage in ["reserved","waiting","pickup","release","eating"]:
		world=fixture()
		actor=world.resident_runtimes[1]
		source=building(world,T.STORAGE)
		source.resources.add(R.FOOD,1)
		if stage=="waiting": world.building_uses.acquire(source.id,1,"held",Vector3.ZERO)
		var on_take := func(resource,_amount):
			if stage=="pickup" and resource==R.FOOD and actor.needs._food_received: remove(world,source)
		var on_release := func(id,purpose):
			if stage=="release" and id==source.id and purpose==1 and actor.needs._food_received and source in world.buildings and not world.building_uses.occupied_by(id,actor.data.id,1): remove(world,source)
		source.resources.changed.connect(on_take)
		world.building_uses.slots_changed.connect(on_release)
		check(actor.needs.try_eat(8000),"Removal stage starts with owned FOOD")
		if stage!="reserved": walk(actor)
		if stage in ["reserved","waiting","eating"]: remove(world,source)
		if stage in ["release","eating"]:
			check(actor.needs._meal_active and actor.view._marker==null,"Removed source after exit does not cancel paid outside meal")
			world.game_time.advance(10.0)
			check(actor.data.hunger==20 and not actor.needs._meal_active,"Paid meal survives source/view deletion")
		else:
			check(actor.needs._active_intent==null and actor.view._marker==null and not actor.view._waiting and actor.data.hunger==80,"Removal during visit cancels safely without free satiety")
		check(source.resources.get_amount(R.FOOD)==(1 if stage in ["reserved","waiting"] else 0) and source.resources.get_reserved_out(R.FOOD)==0,"Removal preserves exact received/unreceived resource semantics")
		source.resources.changed.disconnect(on_take)
		world.building_uses.slots_changed.disconnect(on_release)
		world.free()
	# Critical hunger from the exit callback protects paid FOOD without a timer restart.
	world=fixture()
	actor=world.resident_runtimes[1]
	source=building(world,T.STORAGE)
	source.resources.add(R.FOOD,1)
	var saved: Array=[]
	var critical_on_release := func(id,purpose):
		if id==source.id and purpose==1 and actor.needs._food_received and not world.building_uses.occupied_by(id,actor.data.id,1):
			check(not actor.needs._meal_active and actor.needs._minutes_left==0,"Critical callback observes paid-exit stage, not eating")
			actor.data.hunger=100
			check(actor.intents.current_intent==saved[0] and actor.intents.forced_priority==200 and source.resources.get_amount(R.FOOD)==0,"Critical signal merges the same paid action during exit")
	world.building_uses.slots_changed.connect(critical_on_release)
	actor.decision._deciding=false
	check(actor.needs.try_eat(8000),"Critical exit scenario begins")
	saved.append(actor.intents.current_intent)
	walk(actor)
	actor.decision._deciding=true
	check(actor.needs._minutes_left==10 and actor.needs._meal_active and actor.view._marker==null,"One timer starts only after critical exit callback returns")
	world.game_time.advance(10.0)
	check(actor.data.hunger==40 and actor.intents.forced_priority==0,"Critical paid outdoor meal completes normally")
	world.building_uses.slots_changed.disconnect(critical_on_release)
	world.free()
	# Ten-minute meals crossing WORK end and night retain their committed duration.
	for minute in [1015,1378]:
		world=fixture()
		actor=world.resident_runtimes[1]
		world.game_time.total_minutes=minute
		Stacks.create(world.ground_resources,R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
		check(actor.needs.try_eat(8000),"Schedule-boundary Ground meal begins")
		walk(actor)
		world.game_time.advance(10.0)
		check(not actor.needs._meal_active and actor.data.hunger==20,"Phase boundary does not change committed duration/benefit")
		world.free()
	# Saturation clamp and resident lifecycle cleanup use the existing need/Node owners.
	world=fixture()
	actor=world.resident_runtimes[1]
	actor.data.hunger=40
	Stacks.create(world.ground_resources,R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000,200),"Clamp fixture starts paid Ground meal")
	walk(actor)
	world.game_time.advance(10.0)
	check(actor.data.hunger==0 and not actor.needs._meal_active,"Outside benefit clamps at existing zero minimum")
	world.free()
	for received in [false,true]:
		world=fixture()
		actor=world.resident_runtimes[1]
		source=building(world,T.STORAGE)
		source.resources.add(R.FOOD,1)
		check(actor.needs.try_eat(8000),"Resident removal fixture begins")
		if received: walk(actor)
		var data=actor.data
		world.resident_runtimes.erase(actor)
		actor.view.free()
		actor.free()
		world.game_time.advance(10.0)
		check(source.resources.get_amount(R.FOOD)==(0 if received else 1) and source.resources.get_reserved_out(R.FOOD)==0 and world.building_uses.inside_count(source.id)==0,"Resident deletion releases unpaid reserve/slot and never refunds paid FOOD")
		check(data.hunger==80,"Deleted controller does not continue satiety ticks")
		world.free()
	var file=FileAccess.open("C:/Users/SW/Documents/Codex/outputs/outdoor-meal-lifecycle/portal-trace.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(trace,"\t"))
	print("Outdoor meal lifecycle: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
