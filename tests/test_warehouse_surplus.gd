extends SceneTree
const Service = preload("res://scripts/logistics_controller.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Player = preload("res://scripts/player_control.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
const F = preload("res://tests/residents_ui_fixture.gd")
const R = preload("res://scripts/resource_type.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func warehouse(id: StringName, position: Vector2, quota: int = 10):
	var building = Building.new(id,Definition.for_type(T.STORAGE),position)
	building.resources.configure_warehouse(100,{R.LOG:quota})
	return building
func fixture(foreign: bool = false) -> Dictionary:
	var a = warehouse(&"a",Vector2.ZERO)
	a.resources.add(R.LOG,3)
	a.resources.set_quota(R.LOG,2)
	var b = warehouse(&"b",Vector2(30,0))
	var base = warehouse(&"base",Vector2(60,0),0)
	var first = Resident.new("first","First",30,P.PORTER)
	var second = Resident.new("second","Second",30,P.PORTER)
	first.work_location_id = base.id if foreign else a.id
	second.work_location_id = first.work_location_id
	var player = Player.new()
	player.setup([first,second],[a,b,base])
	var service = Service.new()
	service.assignment_control = player
	service.position_provider = func(_id): return Vector2.ZERO
	service.setup(a,b,first)
	service.register_building(base)
	service.register_resident(second)
	return {"s":service,"a":a,"b":b,"base":base,"first":first,"second":second,"player":player}
func offer(source: RefCounted, destination: RefCounted, resource: int = R.LOG, surplus: bool = true):
	var candidate = Candidate.new()
	candidate.source = source
	candidate.source_ref = Source.new(Source.Kind.CONTAINER,source.id)
	candidate.destination = destination
	candidate.resource_type = resource
	candidate.surplus_export = surplus
	return candidate
func complete(f: Dictionary, job: RefCounted) -> void:
	check(f.s.sources.pickup(job.source_ref,job.resource_type,job.id),"Owned unit leaves source once")
	job.state = Job.State.CARRYING
	check(f.s.deliver_inbound(job) and not f.s.deliver_inbound(job),"Owned inbound delivers once")
	job.state = Job.State.COMPLETED
	f.s.finish_job(job)
func consumer(f: Dictionary, type: int = T.SAWMILL):
	var building = Building.new(&"consumer",Definition.for_type(type),Vector2(1,0))
	building.resources.set_capacity(R.LOG,12)
	building.resources.set_capacity(R.PLANK,12)
	f.s.register_building(building)
	return building

func domain_checks() -> void:
	var f = fixture()
	check(f.s.surplus_available(f.a,R.LOG)==1,"Only actual over-quota stock is surplus")
	var job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.admission==Job.Admission.SURPLUS and job.destination_location_id==f.b.id,"Own porter claims warehouse surplus")
	if job!=null:
		check(f.s.surplus_job_valid(job) and f.a.resources.get_reserved_out(R.LOG)==1 and f.b.resources.get_reserved_in(R.LOG)==1,"Own reservation does not require another surplus unit")
		check(f.s.claim_best_job(f.second.id)==null,"Last surplus unit cannot be promised twice")
		complete(f,job)
		check(f.a.resources.get_amount(R.LOG)==2 and f.b.resources.get_amount(R.LOG)==1 and f.s.sources._claims.is_empty() and f.s._inbound.is_empty(),"Redistribution conserves all stock and clears ownership")
		check(not f.s.has_available_job(f.first.id) and f.s.surplus_available(f.b,R.LOG)==0,"Unchanged quotas do not cause a return trip")
	f = fixture(true)
	job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.source_location_id==f.a.id and job.destination_location_id==f.b.id and job.workplace_location_id==f.base.id,"Foreign porter can redistribute with neither endpoint equal to its base")
	if job!=null: f.s.cancel_job(job)
	check(not f.s.allows_external_delivery(f.a,f.b,R.LOG) and f.s._claim_delivery(f.first,offer(f.a,f.b,R.LOG,false))==null,"Ordinary inter-warehouse admission remains forbidden")
	f.a.resources.set_quota(R.LOG,3)
	check(not f.s.has_available_job(f.first.id) and f.s._claim_delivery(f.first,offer(f.a,f.b))==null,"Foreign normal stock cannot use surplus admission")
	f = fixture()
	var saw = consumer(f)
	saw.logistics_weight = 10
	var pool: Array = f.s._cheap_candidates(f.first.id)
	var keys: Dictionary = {}
	for candidate in pool: keys[candidate.stable_key()] = true
	check(pool.size()==keys.size(),"Ordinary and surplus versions of one trip are not duplicated")
	job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.destination_location_id==f.b.id,"Accepting warehouse precedes a higher-scoring production destination")
	if job!=null: f.s.cancel_job(job)
	var route_calls: Array = []
	f.s.sources.route_available = func(start,target_position):
		route_calls.append([start,target_position])
		return target_position!=f.b.position
	var selected = f.s._first_reachable(f.first.id,f.s._cheap_candidates(f.first.id))
	check(selected!=null and selected.destination==saw and route_calls.size()==4,"Unreachable warehouse falls back to production without repeating route probes")
	# Remove the route callback before releasing this fixture's captured references.
	f.s.sources.route_available = Callable()
	f.b.resources.set_quota(R.LOG,0)
	f.a.resources.set_quota(R.LOG,0)
	var expected_priority: float = Priority.import_priority(saw.resources,R.LOG,saw.logistics_weight)
	job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.destination_location_id==saw.id and is_finite(job.priority) and job.priority<=expected_priority,"Zero source quota allows ordinary finite-scored export to production")
	if job!=null: f.s.cancel_job(job)
	f.a.resources.try_take(R.LOG,3)
	f.a.resources.set_quota(R.PLANK,3)
	f.a.resources.add(R.PLANK,3)
	f.a.resources.set_quota(R.PLANK,0)
	check(not f.s.has_available_job(f.first.id) and f.s._claim_delivery(f.first,offer(f.a,saw,R.PLANK))==null,"Sawmill output buffer is not an external PLANK receiver")
	f = fixture()
	f.b.resources.set_quotas({R.LOG:10,R.PLANK:90})
	f.b.resources.set_quotas({R.LOG:0,R.PLANK:100})
	f.b.resources.add(R.PLANK,100)
	f.b.resources.set_quotas({R.LOG:10,R.PLANK:90})
	check(not f.s.has_available_job(f.first.id) and f.a.resources.get_amount(R.LOG)==3 and f.s.jobs.is_empty(),"Receiver's physical surplus blocks new arrivals; no receiver leaves source unchanged")
	f = fixture()
	f.b.resources.set_quota(R.LOG,1)
	f.b.resources.reserve_in(R.LOG,1)
	check(not f.s.has_available_job(f.first.id) and f.s.surplus_available(f.b,R.LOG)==0,"Inbound occupies receiver room but is never an exportable physical source")
	f = fixture()
	var held = Source.new(Source.Kind.CONTAINER,f.a.id)
	f.s.sources.reserve(held,R.LOG,&"ordinary_owner")
	check(f.s.surplus_available(f.a,R.LOG)==0 and not f.s.has_available_job(f.first.id),"All existing outbound reservations count against surplus")
	f.s.sources.release(held,R.LOG,&"ordinary_owner")
	for callback_at_destination in [false,true]:
		f = fixture()
		var source = f.a
		var target = f.b
		if callback_at_destination:
			target.resources.reserve_in(R.LOG,1)
			target.resources.reservations_changed.connect(func(_resource): source.resources.set_quota(R.LOG,3),CONNECT_ONE_SHOT)
		else: source.resources.reservations_changed.connect(func(_resource): source.resources.set_quota(R.LOG,3),CONNECT_ONE_SHOT)
		check(f.s.claim_best_job(f.first.id)==null and source.resources.get_reserved_out(R.LOG)==0 and target.resources.get_reserved_in(R.LOG)==int(callback_at_destination),"Quota mutation inside reserve callback rolls back only this job's promises")
		if callback_at_destination: target.resources.release_in(R.LOG,1)
	f = fixture()
	var service = f.s
	var second = f.second
	var candidate = offer(f.a,f.b)
	var nested: Array = []
	f.a.resources.reservations_changed.connect(func(_resource): nested.append(service._claim_delivery(second,candidate)),CONNECT_ONE_SHOT)
	job = service._claim_delivery(f.first,candidate)
	check(job!=null and nested==[null] and service.jobs.size()==1 and service.surplus_job_valid(job),"Reentrant claim cannot duplicate the final surplus unit")
	if job!=null:
		f.a.resources.set_quota(R.LOG,3)
		check(job.state==Job.State.CANCELLED and f.a.resources.get_reserved_out(R.LOG)==0 and f.b.resources.get_reserved_in(R.LOG)==0,"Source quota increase cancels only unpicked surplus and releases both sides")
	f = fixture()
	f.a.resources.set_quota(R.LOG,10)
	f.a.resources.add(R.LOG,2)
	f.a.resources.set_quota(R.LOG,2)
	var first_job = f.s.claim_best_job(f.first.id)
	var second_job = f.s.claim_best_job(f.second.id)
	f.a.resources.set_quota(R.LOG,4)
	check(first_job!=null and second_job!=null and f.s.jobs.size()==1 and f.a.resources.get_reserved_out(R.LOG)==1,"Increasing quota cancels only the excess commitments that no longer fit")
	for active in f.s.jobs.duplicate(): f.s.cancel_job(active)
	for remove in ["assignment","source","destination","base"]:
		f = fixture(true)
		job = f.s.claim_best_job(f.first.id)
		if remove=="assignment": f.player.assign_workplace(f.first.id,f.a.id,P.PORTER)
		elif remove=="source": f.s.remove_building(f.a.id)
		elif remove=="destination": f.s.remove_building(f.b.id)
		else: f.s.remove_building(f.base.id)
		check(job!=null and job.state==Job.State.CANCELLED and f.a.resources.get_reserved_out(R.LOG)==0 and f.b.resources.get_reserved_in(R.LOG)==0,"Immediate owned cleanup on "+remove)
	# Ordinary work competes by its existing score; surplus is not an emergency.
	f = fixture()
	f.b.resources.add(R.LOG,9)
	f.a.resources.set_quota(R.FOOD,10)
	var producer = Building.new(&"food",Definition.for_type(T.GATHERER_HUT),Vector2(1,0))
	producer.resources.set_capacity(R.FOOD,5)
	producer.resources.add(R.FOOD,1)
	f.s.register_building(producer)
	job = f.s.claim_best_job(f.first.id)
	check(job!=null and job.source_location_id==producer.id and job.admission==Job.Admission.EXTERNAL,"Higher-scoring ordinary supply retains priority over surplus work")
	if job!=null: f.s.cancel_job(job)
	# Cheap empty warehouse checks do not multiply pathfinding calls.
	f = fixture()
	for index in range(40): f.s.register_building(warehouse(StringName("empty_%d"%index),Vector2(100+index,0),0))
	var calls: Array = []
	f.s.sources.route_available = func(start,target_position): calls.append([start,target_position]); return true
	check(f.s.has_available_job(f.first.id) and calls.size()==2,"Forty irrelevant warehouses add no eager route probes")
	f.s.sources.route_available = Callable()
	print("Surplus selection: 40 irrelevant warehouses, 2 route checks for existence")

func walk(actor: Node) -> void:
	for step in range(6000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func finish(world: Node, actor: Node, job: RefCounted) -> void:
	for boundary in range(6):
		if not job.is_active(): break
		walk(actor)
		await process_frame
		world.game_time.debug_skip_minutes(10)
func capture(world: Node, label: String, building: RefCounted) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	world.resident_selection.select_building(building)
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.info_panel.select_tab(&"storage")
	var camera = world.get_viewport().get_camera_3d()
	var focus = preload("res://scripts/world_3d/world_coordinates.gd").to_world(building.position)
	var forward: Vector3 = -camera.global_basis.z
	var center: Vector3 = camera.global_position+forward*(-camera.global_position.y/forward.y)
	camera.global_position += Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.set_zoom_distance(24/(2*tan(deg_to_rad(camera.fov/2))))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/warehouse-e2-3a/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func physical_checks() -> void:
	var world = F.create(self)
	await process_frame
	var a = F.building(world,T.STORAGE,Vector3(30,0,24))
	var b = F.building(world,T.STORAGE,Vector3(-15,0,24))
	var town = world.warehouse_data
	town.resources.set_quota(R.LOG,0)
	a.resources.add(R.LOG,1)
	a.resources.set_quota(R.LOG,0)
	var actor = world.resident_runtimes[0]
	check(world.player_control.assign_workplace(actor.data.id,town.id,P.PORTER),"Actual foreign warehouse porter assignment")
	check(world._request_work(actor),"Next ordinary work request discovers surplus without a wake notification")
	var job = world.logistics.get_job(actor.data.id)
	check(job!=null and job.admission==Job.Admission.SURPLUS and job.source_location_id==a.id and job.destination_location_id==b.id,"Canonical third-party surplus uses existing HaulExecutor")
	if job==null: world.free(); return
	walk(actor)
	check(actor.view._marker!=null and actor.data.inventory.amount==0,"Quota cancellation is tested during actual source loading before pickup")
	await capture(world,"surplus-loading",a)
	a.resources.set_quota(R.LOG,1)
	check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and b.resources.get_reserved_in(R.LOG)==0,"Pre-pickup quota edit immediately cancels physical trip")
	a.resources.set_quota(R.LOG,0)
	check(world._request_work(actor),"Retry starts a fresh surplus job")
	job = world.logistics.get_job(actor.data.id)
	if job==null: world.free(); return
	walk(actor)
	check(actor.view._marker!=null and actor.view._marker.purpose==1,"Physical source arrival acquires a COURIER slot")
	world.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1 and a.resources.get_amount(R.LOG)==0,"Standard loading picks one reserved unit")
	a.resources.set_quota(R.LOG,1)
	b.resources.set_quota(R.LOG,0)
	check(job.is_active() and world.logistics.inbound_valid(job) and actor.data.inventory.amount==1,"Source and recipient quota edits preserve loaded cargo and confirmed inbound")
	await capture(world,"surplus-carrying",b)
	await finish(world,actor,job)
	check(job.state==Job.State.COMPLETED and b.resources.get_amount(R.LOG)==1 and actor.data.inventory.amount==0,"Standard movement/unloading completes accepted over-quota arrival")
	check(world.logistics.sources._claims.is_empty() and world.logistics._inbound.is_empty() and actor.view._marker==null,"Delivery releases both ownership ledgers and courier slot")
	await capture(world,"surplus-delivered",b)
	# Cancel a loaded trip through a real management assignment change.
	b.resources.set_quota(R.LOG,2)
	a.resources.add(R.LOG,1)
	a.resources.set_quota(R.LOG,0)
	check(world._request_work(actor),"Another surplus job is discoverable normally")
	job = world.logistics.get_job(actor.data.id)
	if job==null: world.free(); return
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	var before: int = world.ground_resources.drops.reduce(func(total,drop): return total+drop.amount,0)
	check(actor.data.inventory.amount==1,"Cancellation scenario actually owns cargo")
	world.player_control.clear_work_assignment(actor.data.id)
	check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and b.resources.get_reserved_in(R.LOG)==0,"Assignment change immediately uses normal loaded cleanup")
	var after: int = world.ground_resources.drops.reduce(func(total,drop): return total+drop.amount,0)
	check(after==before+1 and not world.logistics.cancel_job(job),"Emergency cleanup drops cargo once; no new ground destination is introduced")
	check(world.player_control.assign_workplace(actor.data.id,town.id,P.PORTER),"Porter can take another job after cleanup")
	a.resources.set_quota(R.LOG,1)
	a.resources.add(R.LOG,1)
	a.resources.set_quota(R.LOG,0)
	# Isolate the container surplus from the preceding cleanup's ordinary ground pickup.
	for drop in world.ground_resources.drops: drop.reserve(&"fixture_ground")
	check(world._request_work(actor),"Container surplus is assigned after prior cancellation")
	job = world.logistics.get_job(actor.data.id)
	if job!=null:
		world.logistics.sources.release(job.source_ref,R.LOG,job.id)
		check(job.state==Job.State.CANCELLED and b.resources.get_reserved_in(R.LOG)==0 and actor.data.inventory.amount==0,"Lost outbound reservation cancels physical work immediately")
	world.free()

func run() -> void:
	domain_checks()
	await physical_checks()
	print("Warehouse surplus: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
