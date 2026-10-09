extends SceneTree
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Logistics = preload("res://scripts/logistics_controller.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func building(id: StringName, type: int, stock: int = 0):
	var data = Instance.new(id,Definition.for_type(type))
	data.resources.set_capacity(Resources.FOOD,20)
	if stock>0: data.resources.add(Resources.FOOD,stock)
	return data
func pair(pool: Array, source: RefCounted, destination: RefCounted) -> bool:
	return pool.any(func(candidate): return candidate.source==source and candidate.destination==destination)
func stop(actor: Node) -> void:
	actor.decision._deciding=true
	if actor.commands.active_command != null: actor.commands.cancel_current()
	actor.intents.cancel_current(actor.intents.current_intent)
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(1600):
		actor.view._physics_process(0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id!=reason: break
		if not actor.view.movement.is_moving(): break
func run() -> void:
	for row in [[Types.STORAGE,Resources.FOOD,true,true],[Types.STORAGE,Resources.WOOD,true,true],[Types.STORAGE,Resources.LOG,true,true],[Types.GATHERER_HUT,Resources.FOOD,false,true],[Types.FOOD,Resources.FOOD,true,false],[Types.LUMBERJACK_HUT,Resources.LOG,false,true],[Types.LUMBERJACK_HUT,Resources.FOOD,false,false]]:
		var def = Definition.for_type(row[0])
		check(def.allows_external_import(row[1])==row[2] and def.allows_external_export(row[1])==row[3],"Per-building/resource import/export policy")
	var service = Logistics.new()
	service.position_provider=func(_id): return Vector2.ZERO
	var a=building(&"a",Types.STORAGE,5)
	var b=building(&"b",Types.STORAGE,5)
	var gatherer=building(&"gatherer",Types.GATHERER_HUT,2)
	var kitchen=building(&"kitchen",Types.FOOD)
	var porter=Resident.new("pa","Porter A",30,Profession.PORTER)
	service.setup(a,kitchen,porter)
	service.register_building(gatherer)
	check(not service.has_available_job(porter.id),"No workplace means no logistics WORK")
	porter.work_location_id=a.id
	check(service.has_available_job(porter.id),"Built own Storage exposes WORK")
	service.register_building(b)
	var pool=service.collect_candidates(porter.id)
	check(porter.work_location_id==a.id,"Second Storage never replaces assigned base")
	check(pair(pool,gatherer,a) and not pair(pool,gatherer,b),"Inbound targets only own Storage")
	check(pair(pool,a,kitchen) and not pair(pool,b,kitchen),"Outbound uses only own Storage")
	check(not pair(pool,gatherer,kitchen),"External producer to consumer bypass is excluded")
	check(not service.allows_external_delivery(a,b,Resources.FOOD) and not service.allows_external_delivery(b,a,Resources.FOOD),"No ordinary Storage balancing in either direction")
	var bypass=Candidate.new()
	bypass.source=b
	bypass.destination=kitchen
	check(service._claim_candidate(porter,bypass)==null,"Claim cannot bypass own-base filter")
	a.resources.add(Resources.FOOD,15)
	check(not pair(service.collect_candidates(porter.id),gatherer,a) and not pair(service.collect_candidates(porter.id),gatherer,b),"Full own Storage cannot spill inbound into another")
	a.resources.try_take(Resources.FOOD,1)
	check(pair(service.collect_candidates(porter.id),gatherer,a),"Freed own capacity restores inbound")
	var site=Instance.new(&"site",Definition.for_type(Types.STORAGE),Vector2.ZERO,Instance.State.UNDER_CONSTRUCTION)
	service.register_building(site)
	porter.work_location_id=site.id
	check(not service.has_available_job(porter.id),"Construction Storage is not workplace")
	porter.work_location_id=&"missing"
	check(not service.has_available_job(porter.id),"Missing workplace does not fall back to another Storage")
	# Policy changes during the synchronous reserve callbacks must roll back both sides.
	porter.work_location_id=a.id
	var stale=Candidate.new()
	stale.source=gatherer
	stale.destination=a
	gatherer.resources.reservations_changed.connect(func(_resource): a.definition.logistics_flow[Resources.FOOD]["import"]=false,CONNECT_ONE_SHOT)
	check(service._claim_candidate(porter,stale)==null and gatherer.resources.get_reserved_out(Resources.FOOD)==0 and a.resources.get_reserved_in(Resources.FOOD)==0,"Atomic post-reservation recheck rejects changed import policy")
	a.definition.logistics_flow[Resources.FOOD]["import"]=true
	# Two porter bases compete for one actual external unit.
	porter.work_location_id=a.id
	var second=Resident.new("pb","Porter B",30,Profession.PORTER)
	second.work_location_id=b.id
	service.register_resident(second)
	a.resources.try_take(Resources.FOOD,a.resources.get_amount(Resources.FOOD))
	b.resources.try_take(Resources.FOOD,b.resources.get_amount(Resources.FOOD))
	gatherer.resources.try_take(Resources.FOOD,1)
	var first_job=service.claim_best_job(porter.id)
	check(first_job.source_location_id==gatherer.id and first_job.destination_location_id==a.id,"Porter A claims producer to A")
	check(service.claim_best_job(second.id)==null and gatherer.resources.get_reserved_out(Resources.FOOD)==1,"Porter B cannot duplicate reserved producer unit")
	service.cancel_job(first_job)
	var second_job=service.claim_best_job(second.id)
	check(second_job.destination_location_id==b.id,"Porter B claims its own B after release")
	service.cancel_job(second_job)
	# Actual main_3d executors, resource reservations and command cleanup.
	var scene=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for actor in scene.resident_runtimes:
		stop(actor)
		actor.view.set_physics_process(false)
		for need in range(4): actor.data.get_need(need).value=0
	await physics_frame
	var actor=scene.resident_runtimes[0]
	var own=scene.warehouse_data
	var storage=Instance.new(&"second_storage",Definition.for_type(Types.STORAGE),Coordinates.to_sim(Vector3(25,0,20)))
	scene.buildings.append(storage)
	scene._show_building(storage)
	check(actor.data.work_location_id==own.id,"Built world Storage keeps existing porter assignment")
	var other=scene.resident_runtimes[2]
	check(scene.player_control.assign_workplace(other.data.id,storage.id),"Shared workplace API assigns specific second Storage")
	scene.game_time.debug_skip_minutes(60)
	check(scene.logistics.collect_candidates(other.data.id).is_empty(),"Second porter cannot use first warehouse stock")
	storage.resources.add(Resources.FOOD,2)
	var job=scene.logistics.claim_best_job(other.data.id)
	check(job.source_location_id==storage.id and job.workplace_location_id==storage.id and scene.logistics.start_claimed_job(job,other.data.id),"Real owned job captures porter base")
	walk(other,&"haul_source")
	check(other.data.inventory.amount==1 and storage.resources.get_reserved_out(Resources.FOOD)==0,"Real pickup uses existing inventory/reservation flow")
	walk(other)
	check(scene.kitchen_data.resources.get_amount(Resources.FOOD)==1 and other.data.inventory.amount==0,"Kitchen receives FOOD from assigned second base")
	for picked_up in [false,true]:
		if own.resources.get_available_free_capacity(Resources.FOOD)>0: own.resources.add(Resources.FOOD,1)
		job=scene.logistics.claim_best_job(actor.data.id)
		check(job != null and scene.logistics.start_claimed_job(job,actor.data.id),"Active base-invalidation fixture")
		if picked_up: walk(actor,&"haul_source")
		var original_stock: int=own.resources.get_amount(Resources.FOOD)
		if picked_up:
			scene.world_locations.unregister(own.id)
			scene.logistics.recalculate()
		else: scene.logistics.remove_building(own.id)
		check(scene.logistics.get_job(actor.data.id)==null and own.resources.get_reserved_out(Resources.FOOD)==0 and scene.kitchen_data.resources.get_reserved_in(Resources.FOOD)==0,"Unavailable own base cancels job and releases reservations")
		check(actor.data.work_location_id==own.id and not scene.logistics.has_available_job(actor.data.id),"No reassignment to surviving Storage")
		check(own.resources.get_amount(Resources.FOOD)==original_stock and actor.data.inventory.amount==0 and scene.ground_resources.drops.size()==(1 if picked_up else 0),"After-pickup cargo drops, source is not restored")
		if not picked_up: scene.logistics.register_building(own)
	# Two huts, empty nearer hut must be excluded by generic policy and forestry selection.
	var hut=preload("res://tests/forestry_fixture.gd").hut(scene,&"hut_a",Vector3(-20,0,-8))
	var hut_b=preload("res://tests/forestry_fixture.gd").hut(scene,&"hut_b",Vector3(-20,0,-2))
	var lumber=scene.resident_runtimes[3]
	scene.player_control.assign_workplace(lumber.data.id,hut.id)
	hut.resources.add(Resources.LOG,12)
	hut.definition.target_tree_count=0
	var worker=lumber.get_node("Lumberjack")
	check(hut_b.resources.get_available_free_capacity(Resources.LOG)==12 and not scene.logistics.allows_external_delivery(hut,hut_b,Resources.LOG),"Empty hut stores LOG but cannot externally import it")
	check(not scene.logistics.external_destinations(hut,Resources.LOG).has(hut_b),"Generic external destination provider rejects second hut")
	check(worker.best_task().kind==&"EXPORT" and worker.best_task().destination==storage,"Forestry fallback respects shared policy, chooses Storage")
	check(scene.logistics.collect_candidates(other.data.id).any(func(c): return c.source==hut and c.destination==storage and c.resource_type==Resources.LOG),"Porter B can import hut LOG only into B")
	check(scene.logistics.claim_own_export(lumber.data.id,hut_b)==null and hut.resources.get_reserved_out(Resources.LOG)==0 and hut_b.resources.get_reserved_in(Resources.LOG)==0,"Direct external claim cannot bypass hut import policy")
	scene.free()
	print("Logistics flow policy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
