extends SceneTree
const Logistics = preload("res://scripts/logistics_controller.gd")
const Reference = preload("res://tests/porter_exhaustive_reference.gd")
const Building = preload("res://scripts/building_data.gd")
const Data = preload("res://scripts/resident_data.gd")
const Drop = preload("res://scripts/ground_resource.gd")
const Ground = preload("res://scripts/ground_resources.gd")
const BT = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
class Counted extends "res://scripts/logistics_controller.gd":
	var checked := 0
	func _routes_available(candidate: Candidate, position: Vector2) -> bool:
		checked += 1
		return super._routes_available(candidate,position)
class RejectAll extends Counted:
	var attempts: Array[String] = []
	func _claim_candidate(_worker: ResidentData, candidate: Candidate) -> HaulJob:
		attempts.append(candidate.stable_key())
		return null
class RejectSmoothing extends "res://scripts/navigation_grid.gd":
	func smooth_path(_raw: PackedVector3Array) -> PackedVector3Array: return PackedVector3Array()
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func fixture(service: Counted = null) -> Dictionary:
	if service==null: service=Counted.new()
	var reference := Reference.new()
	var base = Building.new(&"base","Base",BT.STORAGE)
	var worker = Data.new("p","Porter",20,P.PORTER)
	worker.work_location_id=base.id
	for res in R.values(): base.resources.set_capacity(res,100)
	service.setup(base,null,worker)
	reference.setup(base,null,worker)
	service.position_provider=func(_id): return Vector2(-50,0)
	reference.position_provider=service.position_provider
	var ground := Ground.new()
	service.sources.ground=ground
	reference.sources.ground=ground
	return {"service":service,"reference":reference,"base":base,"worker":worker,"ground":ground}
func add_building(f: Dictionary, id: StringName, type: int, position: Vector2):
	var b = Building.new(id,String(id),type)
	b.position=position
	for res in R.values(): b.resources.set_capacity(res,20)
	f.service.register_building(b)
	f.reference.register_building(b)
	return b
func drop(f: Dictionary, id: StringName, res: int, position: Vector2) -> void:
	var d := Drop.new(res,1,position,0)
	d.id=id
	f.ground.drops.append(d)
func compare(f: Dictionary, label: String) -> Variant:
	var old = f.reference._best(f.reference.collect_candidates(f.worker.id))
	var current = f.service._first_reachable(f.worker.id,f.service._cheap_candidates(f.worker.id))
	check((old==null)==(current==null),label+": presence")
	if old!=null and current!=null:
		check(old.source_ref.stable_key()==current.source_ref.stable_key() and old.destination.id==current.destination.id and old.resource_type==current.resource_type and old.porter_score==current.porter_score and old.stable_key()==current.stable_key(),label+": exact identity/score/key")
	check(f.service.collect_candidates(f.worker.id).map(func(c): return c.stable_key())==f.reference.collect_candidates(f.worker.id).map(func(c): return c.stable_key()),label+": full diagnostic list")
	return current
func dispose(f: Dictionary) -> void: f.ground.free()
func run() -> void:
	var f := fixture()
	compare(f,"empty")
	drop(f,&"ground_2",R.LOG,Vector2(10,0))
	drop(f,&"ground_10",R.LOG,Vector2(10,0))
	var best = compare(f,"lexical tie")
	check(best.source_ref.id==&"ground_10","Lexical rather than numeric tie")
	f.service.checked=0
	check(f.service.has_available_job(f.worker.id) and f.service.checked==1,"Availability stops after first feasible")
	check(f.service.jobs.is_empty() and f.base.resources.get_reserved_in(R.LOG)==0 and f.ground.drops.all(func(d): return d.reservation_owner_id.is_empty()),"Availability has no reservation effects")
	f.base.logistics_weight=0
	check(compare(f,"negative").porter_score<200,"No score positivity gate")
	dispose(f)
	f=fixture()
	for i in 11: drop(f,StringName("ground_%02d" % i),R.LOG,Vector2(i+1,0))
	f.service.sources.route_available=func(_a,b): return b.x>10 or b==Vector2.ZERO
	f.reference.sources.route_available=f.service.sources.route_available
	f.service.checked=0
	best=f.service._first_reachable(f.worker.id,f.service._cheap_candidates(f.worker.id))
	check(best.source_ref.id==&"ground_10" and f.service.checked==11,"No K cap: ten unreachable then eleventh")
	compare(f,"ten unreachable")
	f.service.sources.route_available=func(_a,_b): return false
	f.reference.sources.route_available=f.service.sources.route_available
	check(compare(f,"all unreachable")==null,"Exhaustion")
	dispose(f)
	for res in R.values():
		f=fixture()
		drop(f,&"resource",res,Vector2(30,0))
		check(compare(f,"resource %d" % res).resource_type==res,"Every Ground resource")
		dispose(f)
	f=fixture()
	drop(f,&"remote",R.LOG,Vector2(5000,0))
	check(compare(f,"strictly negative").porter_score<0,"Negative score remains eligible")
	f.service.sources.route_available=func(a,b): return not (a.x==5000 and b==Vector2.ZERO)
	f.reference.sources.route_available=f.service.sources.route_available
	check(compare(f,"destination leg unavailable")==null,"Both legs checked")
	f.service.position_provider=func(_id): return Vector2(NAN,0)
	check(not f.service.has_available_job(f.worker.id),"Invalid origin cannot enter ranking")
	dispose(f)
	f=fixture()
	f.base.resources.add(R.FOOD,10)
	var near = add_building(f,&"near_consumer",BT.FOOD,Vector2(20,0))
	near.resources.add(R.FOOD,19)
	var far = add_building(f,&"far_consumer",BT.FOOD,Vector2(900,0))
	check(compare(f,"far more urgent").destination==far,"Distance does not override score")
	var producer = add_building(f,&"producer",BT.GATHERER_HUT,Vector2(100,0))
	producer.resources.add(R.FOOD,producer.resources.get_capacity(R.FOOD))
	check(compare(f,"export beats import").source==producer,"Unified category score")
	drop(f,&"ground",R.LOG,Vector2(10,0))
	check(compare(f,"ground competes with container").source_ref.kind==1,"Ground included in same ranking")
	f.base.resources.reserve_in(R.LOG,100)
	check(compare(f,"full Ground destination").source==producer,"Full base excludes only relevant resource")
	f.base.resources.release_in(R.LOG,1)
	compare(f,"last free space")
	f.ground.drops.clear()
	f.base.resources.try_take(R.FOOD,10)
	check(f.service.has_available_job(f.worker.id),"Container availability before deletion")
	f.service.remove_building(producer.id)
	check(f.service.claim_best_job(f.worker.id)==null,"Container deletion after availability")
	dispose(f)
	var rng := RandomNumberGenerator.new()
	rng.seed=741923
	for iteration in 250:
		f=fixture()
		f.base.position=Vector2(rng.randf_range(-900,900),rng.randf_range(-900,900))
		var origin := Vector2(rng.randf_range(-900,900),rng.randf_range(-900,900))
		f.service.position_provider=func(_id): return origin
		f.reference.position_provider=f.service.position_provider
		f.base.logistics_weight=rng.randi_range(0,250)
		for res in R.values():
			var cap := rng.randi_range(1,100)
			f.base.resources.set_capacity(res,cap)
			f.base.resources.add(res,rng.randi_range(0,cap))
			f.base.resources.reserve_out(res,rng.randi_range(0,f.base.resources.get_amount(res)))
			f.base.resources.reserve_in(res,rng.randi_range(0,f.base.resources.get_available_free_capacity(res)))
		for i in 8:
			var b = add_building(f,StringName("building_%d" % i),[BT.FOOD,BT.GATHERER_HUT,BT.SAWMILL,BT.LUMBERJACK_HUT,BT.QUARRY][i%5],Vector2(rng.randf_range(-1500,1500),rng.randf_range(-1500,1500)))
			b.logistics_weight=rng.randi_range(0,250)
			for res in R.values():
				b.resources.add(res,rng.randi_range(0,b.resources.get_capacity(res)))
		for i in 12:
			drop(f,StringName("ground_%d" % i),R.values()[rng.randi_range(0,R.size()-1)],Vector2(rng.randf_range(-1500,1500),rng.randf_range(-1500,1500)))
		var cutoff := rng.randf_range(-1200,1200)
		f.service.sources.route_available=func(a,b): return a.x>cutoff and b.x>cutoff
		f.reference.sources.route_available=f.service.sources.route_available
		compare(f,"random %d" % iteration)
		dispose(f)
	# Actual grid path predicate including costs, disconnects and endpoint rejection.
	f=fixture()
	var grid = preload("res://scripts/navigation_grid.gd").new(Rect2(-10,-10,20,20),0.0)
	f.base.position=C.to_sim(Vector3(-4.25,0,0.25))
	f.service.position_provider=func(_id): return C.to_sim(Vector3(-5.25,0,0.25))
	f.reference.position_provider=f.service.position_provider
	drop(f,&"near",R.LOG,C.to_sim(Vector3(-2.25,0,0.25)))
	drop(f,&"far",R.STONE,C.to_sim(Vector3(3.25,0,0.25)))
	f.service.sources.route_available=func(a,b): return grid.can_reach_point(C.to_world(a),C.to_world(b)) and not grid.find_path(C.to_world(a),C.to_world(b)).is_empty()
	f.reference.sources.route_available=f.service.sources.route_available
	compare(f,"actual routes")
	grid.set_traversal_modifier(&"road",Rect2(-6,-1,12,2),1.5)
	compare(f,"road costs")
	grid.add_blocker(&"wall",Rect2(0,-10,0.5,20))
	compare(f,"disconnected actual grid")
	grid.add_blocker(&"near",Rect2(-2.5,0,0.5,0.5))
	check(compare(f,"blocked endpoints")==null,"Full path endpoint predicate retained")
	dispose(f)
	f=fixture()
	grid=RejectSmoothing.new(Rect2(-10,-10,20,20),0.0)
	drop(f,&"smooth",R.LOG,Vector2(25,0))
	f.service.sources.route_available=func(a,b): return grid.can_reach_point(C.to_world(a),C.to_world(b)) and not grid.find_path(C.to_world(a),C.to_world(b)).is_empty()
	f.reference.sources.route_available=f.service.sources.route_available
	check(grid.can_reach_point(Vector3(-2,0,0),Vector3(1,0,0)),"Connectivity alone would accept")
	check(compare(f,"smoothing rejection")==null,"Full predicate preserves post-connectivity rejection")
	dispose(f)
	var rejected := RejectAll.new()
	f=fixture(rejected)
	for i in 3: drop(f,StringName("retry_%d" % i),R.LOG,Vector2(i+1,0))
	check(rejected.claim_best_job(f.worker.id)==null and rejected.attempts.size()==3,"Finite retry after failed claims")
	check(rejected.attempts[0]!=rejected.attempts[1] and rejected.attempts[1]!=rejected.attempts[2],"Each key attempted once")
	check(f.base.resources.get_reserved_in(R.LOG)==0,"Failed attempts leave no reservations")
	dispose(f)
	# Fresh claim, four competitors and source/destination removal after availability.
	f=fixture()
	for i in 4: drop(f,StringName("ground_%d" % i),R.LOG,Vector2(20,0))
	for i in 4:
		var worker = Data.new("porter_%d" % i,"Porter",20,P.PORTER)
		worker.work_location_id=f.base.id
		f.service.register_resident(worker)
		check(f.service.claim_best_job(worker.id)!=null,"Four competing claims")
	check(f.service.jobs.size()==4 and f.base.resources.get_reserved_in(R.LOG)==4 and f.ground.drops.all(func(d): return not d.reservation_owner_id.is_empty()),"Distinct owned cargo promises")
	for job in f.service.jobs.duplicate(): f.service.cancel_job(job)
	check(f.service.has_available_job(f.worker.id),"Availability before deletion")
	f.ground.drops.clear()
	check(f.service.claim_best_job(f.worker.id)==null,"Ground deletion after availability")
	drop(f,&"new",R.LOG,Vector2(20,0))
	check(f.service.has_available_job(f.worker.id),"Availability before base deletion")
	f.service.remove_building(f.base.id)
	check(f.service.claim_best_job(f.worker.id)==null,"Destination deletion after availability")
	dispose(f)
	print("Porter exact lazy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
