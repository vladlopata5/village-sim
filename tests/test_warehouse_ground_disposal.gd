extends SceneTree
const Service = preload("res://scripts/logistics_controller.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Player = preload("res://scripts/player_control.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
const Drop = preload("res://scripts/cargo_drop_result.gd").Status
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const R = preload("res://scripts/resource_type.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func warehouse(id: StringName, position: Vector2, quota: int = 0):
	var building = Building.new(id,Definition.for_type(T.STORAGE),position)
	building.resources.configure_warehouse(100,{R.LOG:quota})
	return building
func fixture(foreign: bool = false) -> Dictionary:
	var a = warehouse(&"a",Vector2.ZERO,3)
	a.resources.add(R.LOG,3)
	a.resources.set_quota(R.LOG,2)
	var b = warehouse(&"b",Vector2(30,0))
	var first = Resident.new("first","First",30,P.PORTER)
	var second = Resident.new("second","Second",30,P.PORTER)
	first.work_location_id = b.id if foreign else a.id
	second.work_location_id = first.work_location_id
	var player = Player.new()
	player.setup([first,second],[a,b])
	var service = Service.new()
	service.assignment_control = player
	service.position_provider = func(_id): return Vector2.ZERO
	service.setup(a,b,first)
	service.register_resident(second)
	return {"s":service,"a":a,"b":b,"first":first,"second":second,"player":player}
func ground_offer(source: RefCounted):
	var candidate = Candidate.new()
	candidate.source = source
	candidate.source_ref = Source.new(Source.Kind.CONTAINER,source.id)
	candidate.receiver_kind = Job.Receiver.GROUND
	candidate.resource_type = R.LOG
	candidate.surplus_export = true
	return candidate
func selected(f: Dictionary): return f.s._first_reachable(f.first.id,f.s._cheap_candidates(f.first.id))
func domain_checks() -> void:
	var f: Dictionary
	var job: RefCounted
	for foreign in [false,true]:
		f = fixture(foreign)
		var candidate = selected(f)
		check(candidate!=null and candidate.receiver_kind==Job.Receiver.GROUND and candidate.destination==null,"Fallback has explicit ground receiver without fake container")
		var ordinary = Candidate.new()
		ordinary.source_ref = candidate.source_ref
		ordinary.destination = f.a
		check(candidate.stable_key()!=ordinary.stable_key(),"Ground key cannot collide with a container trip")
		job = f.s.claim_best_job(f.first.id)
		check(job!=null and job.receiver_kind==Job.Receiver.GROUND and job.source_location_id==f.a.id and job.destination_location_id==f.a.id,"Own/foreign porter disposes at source, not base")
		check(job!=null and f.s.surplus_job_valid(job) and f.a.resources.get_reserved_out(R.LOG)==1 and f.s._inbound.is_empty(),"Ground claim owns only one surplus outgoing unit")
		check(f.s.claim_best_job(f.second.id)==null,"Last surplus unit is exclusive between porters")
		f.b.resources.set_quota(R.LOG,10)
		check(f.s.surplus_job_valid(job),"New receiving container does not invalidate committed ground job")
		f.s.cancel_job(job)
		check(f.a.resources.get_reserved_out(R.LOG)==0 and f.s.sources._claims.is_empty(),"Unstarted cancellation releases outgoing exactly once")
		check(selected(f).destination==f.b,"Next selection sees the new accepting warehouse")
	f = fixture()
	var saw = Building.new(&"saw",Definition.for_type(T.SAWMILL),Vector2(5,0))
	saw.resources.set_capacity(R.LOG,12)
	f.s.register_building(saw)
	check(selected(f).destination==saw,"Allowed reachable production input precedes ground")
	f.b.resources.set_quota(R.LOG,10)
	f.s.sources.route_available = func(_start,target): return target!=f.b.position
	check(selected(f).destination==saw,"One unreachable warehouse does not skip reachable production")
	var other = warehouse(&"other",Vector2(40,0),10)
	f.s.register_building(other)
	check(selected(f).destination==other,"Remaining reachable warehouses are tried before lower tiers")
	f.s.sources.route_available = func(_start,target): return target==f.a.position
	check(selected(f).receiver_kind==Job.Receiver.GROUND,"Only after all containers are unreachable does ground win")
	job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.receiver_kind==Job.Receiver.GROUND,"Unreachable containers do not prevent atomic ground claim")
	if job!=null: f.s.cancel_job(job)
	f.s.sources.route_available = func(_start,_target): return false
	check(not f.s.has_available_job(f.first.id) and f.s.claim_best_job(f.first.id)==null,"Unreachable source cannot be disposed remotely")
	f.s.sources.route_available = Callable()
	f = fixture()
	job = f.s.claim_best_job(f.first.id)
	f.a.resources.set_quota(R.LOG,3)
	check(job!=null and job.state==Job.State.CANCELLED and f.a.resources.get_reserved_out(R.LOG)==0,"Quota increase before pickup cancels owned ground reservation")
	for change in ["source","base","assignment"]:
		f = fixture(true)
		job = f.s.claim_best_job(f.first.id)
		if change=="source": f.s.remove_building(f.a.id)
		elif change=="base": f.s.remove_building(f.b.id)
		else: f.player.clear_work_assignment(f.first.id)
		check(job!=null and job.state==Job.State.CANCELLED and f.s.sources._claims.is_empty() and f.s._inbound.is_empty(),"Owned cleanup on "+change)
	f = fixture()
	var mutate = func(_resource):
		if f.a.resources.get_reserved_out(R.LOG)>0: f.a.resources.set_quota(R.LOG,3)
	f.a.resources.reservations_changed.connect(mutate)
	check(f.s.claim_best_job(f.first.id)==null and f.s.sources._claims.is_empty() and f.a.resources.get_reserved_out(R.LOG)==0,"Quota callback during claim rolls back without a phantom ground job")
	f.a.resources.reservations_changed.disconnect(mutate)
	f = fixture()
	var receiver = func(_resource):
		if f.a.resources.get_reserved_out(R.LOG)>0: f.b.resources.set_quota(R.LOG,10)
	f.a.resources.reservations_changed.connect(receiver)
	check(f.s._claim_delivery(f.first,ground_offer(f.a))==null and f.s.sources._claims.is_empty(),"Receiver appearing before publication prevents stale ground fallback")
	f.a.resources.reservations_changed.disconnect(receiver)
	f = fixture()
	var fake = ground_offer(f.a)
	fake.surplus_export = false
	check(f.s._claim_delivery(f.first,fake)==null,"No general-purpose ground hauling admission")
	f.a.resources.set_quota(R.LOG,3)
	check(f.s._claim_delivery(f.first,ground_offer(f.a))==null,"Normal stock cannot be discarded through forged surplus offer")

func walk(actor: Node) -> void:
	for step in range(6000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func units(world: Node) -> int:
	return world.ground_resources.drops.reduce(func(total,drop): return total+drop.amount,0)
func seed_source(source: RefCounted) -> void:
	source.resources.set_quota(R.LOG,10)
	source.resources.add(R.LOG,1)
	source.resources.set_quota(R.LOG,0)
func claim(world: Node, actor: Node):
	check(world._request_work(actor),"Ordinary AI work hook starts surplus task")
	return world.logistics.get_job(actor.data.id)
func capture(world: Node, label: String, source: RefCounted) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	var camera = world.get_viewport().get_camera_3d()
	var focus: Vector3 = C.to_world(source.position)
	var forward: Vector3 = -camera.global_basis.z
	var center: Vector3 = camera.global_position+forward*(-camera.global_position.y/forward.y)
	camera.global_position += Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.set_zoom_distance(12/(2*tan(deg_to_rad(camera.fov/2))))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/warehouse-e2-3b/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func physical_checks() -> void:
	var world = F.create(self)
	await process_frame
	var source = F.building(world,T.STORAGE,Vector3(30,0,24))
	var town = world.warehouse_data
	town.resources.set_quota(R.LOG,0)
	var actor = world.resident_runtimes[0]
	check(world.player_control.assign_workplace(actor.data.id,town.id,P.PORTER),"Foreign warehouse porter assignment")
	var origin: Vector2 = world.world_locations.get_resource_position(source.id)
	var placed: Dictionary = world.place_ground_resources(R.LOG,2,origin,world.ground_resources.PlacementMode.WORKER)
	check(placed.placed==0 and placed.remaining==2,"Worker placement contract still rejects multi-unit unload")
	placed = world.place_ground_resources(R.LOG,1,origin,world.ground_resources.PlacementMode.WORKER)
	var stack = world.ground_resources.get_by_id(placed.stack_ids[0])
	var stack_id: StringName = stack.id
	seed_source(source)
	var job = claim(world,actor)
	if job==null: world.free(); return
	var executor = world.logistics._executors[actor.data.id]
	check(job.receiver_kind==Job.Receiver.GROUND and job.source_location_id==source.id and job.workplace_location_id==town.id,"Real foreign ground receiver remains at source warehouse")
	check(source.resources.get_reserved_out(R.LOG)==1 and actor.data.inventory.amount==0 and stack.amount==1,"No remote pickup or placement at claim time")
	await capture(world,"01-reserved",source)
	walk(actor)
	check(actor.view._marker!=null and actor.view._marker.purpose==1 and actor.view._building==source.id and executor.handling.is_active(),"Source loading owns physical COURIER slot")
	var marker = actor.view._marker
	await capture(world,"02-loading",source)
	world.game_time.debug_skip_minutes(9)
	check(actor.data.inventory.amount==0 and source.resources.get_amount(R.LOG)==1,"Loading requires all ten game minutes")
	world.game_time.debug_skip_minutes(1)
	check(actor.data.inventory.amount==1 and source.resources.get_amount(R.LOG)==0 and job.state==Job.State.GOING_TO_DESTINATION,"Pickup transfers exactly one unit after loading")
	check(actor.view._marker==marker and marker.occupant==actor.data.id and actor.view.get_sim_position().is_equal_approx(origin),"Exterior unloading retains source COURIER ownership without a new trip")
	check(actor.intents.current_intent.courier_outside and actor.intents.current_intent.resource_handling==&"unloading" and not actor.view.movement.is_moving(),"Ground unloading starts outside without walking to a cell")
	# New quota and receiving warehouse after pickup do not steal committed cargo.
	source.resources.set_quota(R.LOG,1)
	var receiver = F.building(world,T.STORAGE,Vector3(-15,0,24))
	check(job.is_active() and actor.data.inventory.amount==1,"Quota and new receiver preserve the confirmed ground trip")
	await capture(world,"03-unloading",source)
	world.game_time.debug_skip_minutes(9)
	check(actor.data.inventory.amount==1 and stack.amount==1,"Ground placement waits for full ten-minute unloading")
	var reenter = func(_resource,_amount,_resident): executor.cancel("reentrant notification")
	world.logistics.cargo_dropped.connect(reenter)
	world.game_time.debug_skip_minutes(1)
	world.logistics.cargo_dropped.disconnect(reenter)
	check(job.state==Job.State.COMPLETED and actor.data.inventory.amount==0 and stack.amount==2 and stack.id==stack_id,"PLACED merges once and completes even with a reentrant cancel notification")
	check(source.resources.get_reserved_out(R.LOG)==0 and world.logistics.sources._claims.is_empty() and world.logistics._inbound.is_empty() and actor.view._marker==null and executor.job==null,"Successful disposal clears claims, slot and active executor")
	world.game_time.debug_skip_minutes(10)
	check(stack.amount==2 and not executor.cancel("again"),"Later minute/repeated cancel cannot drop a second unit")
	await capture(world,"04-completed-stack",source)
	# Repeated physical cancellation at each lifecycle boundary.
	receiver.resources.set_quota(R.LOG,0)
	var before: int
	for phase in ["assigned","loading","unloading"]:
		seed_source(source)
		job = claim(world,actor)
		if job==null: continue
		if phase!="assigned": walk(actor)
		if phase=="unloading": world.game_time.debug_skip_minutes(10)
		before = units(world)
		var loaded: bool = actor.data.inventory.amount==1
		check(executor.cancel("test "+phase) and not executor.cancel("repeat"),"Cancellation is idempotent at "+phase)
		check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and world.logistics.sources._claims.is_empty() and actor.view._marker==null,"Cancellation cleans resources and slot at "+phase)
		check(units(world)==before+(1 if loaded else 0),"Cancellation drops only actually owned cargo at "+phase)
		if not loaded: source.resources.try_take(R.LOG,1)
	# Valid search exhaustion is deliberate disposal, not retry.
	seed_source(source)
	job = claim(world,actor)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	before = units(world)
	world.runtime_placement_blockers.register_circle(&"no_ground",func(): return C.to_world(origin),20.0,true)
	world.game_time.debug_skip_minutes(10)
	check(job!=null and job.state==Job.State.COMPLETED and executor.last_drop_result==Drop.DISCARDED and actor.data.inventory.amount==0,"Exhausted radius-eight search discards once and completes normally")
	check(units(world)==before and actor.view._marker==null and world.logistics.jobs.is_empty(),"DISCARDED leaves no resource, slot, job or retry")
	world.runtime_placement_blockers.unregister(&"no_ground")
	# Real API failure: keep cargo, release job, and never invoke emergency retry.
	seed_source(source)
	job = claim(world,actor)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	before = units(world)
	world.ready_for_play = false
	world.game_time.debug_skip_minutes(10)
	check(job!=null and job.state==Job.State.CANCELLED and executor.last_drop_result==Drop.FAILED and actor.data.inventory.amount==1,"FAILED retains inventory instead of silently destroying it")
	check(units(world)==before and actor.view._marker==null and world.logistics.sources._claims.is_empty() and world.logistics._inbound.is_empty() and executor.job==null,"FAILED clears job/slot/reserves without secondary drop attempt")
	world.ready_for_play = true
	check(actor.data.inventory.drop_cargo(world._drop_cargo.bind(actor))==Drop.PLACED,"Retained cargo can use the existing safe cleanup contract")
	# Quota invalidation while physically loading.
	seed_source(source)
	job = claim(world,actor)
	walk(actor)
	source.resources.set_quota(R.LOG,1)
	check(job!=null and job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and actor.view._marker==null,"Quota edit during loading releases source and occupied slot immediately")
	source.resources.try_take(R.LOG,1)
	# Assignment and player interruption during unloading use the established cleanup.
	for interruption in ["assignment","player"]:
		seed_source(source)
		job = claim(world,actor)
		walk(actor)
		world.game_time.debug_skip_minutes(10)
		before = units(world)
		if interruption=="assignment": world.player_control.clear_work_assignment(actor.data.id)
		else: actor.intents.begin_player_intent(preload("res://scripts/resident_intent.gd").new())
		check(job!=null and job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and actor.view._marker==null and units(world)==before+1,"Loaded "+interruption+" interruption cleans cargo once")
		if interruption=="assignment": world.player_control.assign_workplace(actor.data.id,town.id,P.PORTER)
		else: actor.intents.abort_current(actor.intents.current_intent)
	# A source callback may cancel while Inventory.receive is still guarded.
	seed_source(source)
	job = claim(world,actor)
	walk(actor)
	before = units(world)
	var cancel_pickup = func(resource,_amount):
		if resource==R.LOG and source.resources.get_amount(R.LOG)==0: executor.cancel("pickup callback")
	source.resources.changed.connect(cancel_pickup)
	world.game_time.debug_skip_minutes(10)
	source.resources.changed.disconnect(cancel_pickup)
	check(job!=null and job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and source.resources.get_amount(R.LOG)==0 and units(world)==before+1,"Reentrant pickup cancellation transfers then cleans exactly one owned unit")
	check(actor.view._marker==null and world.logistics.sources._claims.is_empty() and executor.job==null,"Reentrant pickup cleanup releases slot and outgoing ownership")
	# Removal during a loaded exterior operation must use normal emergency cleanup.
	seed_source(source)
	job = claim(world,actor)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	before = units(world)
	world.logistics.remove_building(source.id)
	check(job!=null and job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and actor.view._marker==null and units(world)==before+1,"Source removal after pickup performs timely owned-cargo cleanup")
	world.free()
func run() -> void:
	domain_checks()
	await physical_checks()
	print("Warehouse ground disposal: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
