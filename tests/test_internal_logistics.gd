extends SceneTree
const Logistics = preload("res://scripts/logistics_controller.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Data = preload("res://scripts/resident_data.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
const BT = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var service := Logistics.new()
	var hut := Building.new(&"hut",Definition.for_type(BT.LUMBERJACK_HUT),Vector2.ZERO)
	var other := Building.new(&"other",Definition.for_type(BT.LUMBERJACK_HUT),Vector2.ONE)
	var storage := Building.new(&"storage",Definition.for_type(BT.STORAGE),Vector2(2,0))
	for place in [hut,other,storage]:
		place.resources.set_capacity(R.LOG,2)
	var worker := Data.new("worker","Worker",30,P.LUMBERJACK)
	worker.work_location_id = hut.id
	service.setup(storage,hut,worker)
	service.register_building(other)
	service.position_provider = func(_id): return Vector2.ZERO
	storage.resources.add(R.LOG,2)
	var ref := Source.new(Source.Kind.CONTAINER,storage.id)
	var eligible := func(): return true
	check(service.claim_transport(worker.id,ref,hut,R.LOG,eligible)==null,"External policy stays closed")
	check(service.claim_internal(worker.id,ref,other,R.LOG,eligible)==null,"Cannot deposit into another hut")
	check(service.claim_internal(worker.id,ref,hut,R.FOOD,eligible)==null,"Internal rejects unsupported resource")
	worker.profession = P.PORTER
	check(service.claim_internal(worker.id,ref,hut,R.LOG,eligible)==null,"Porter cannot forge internal authorization")
	worker.profession = P.LUMBERJACK
	var site := Building.new(&"site",Definition.for_type(BT.LUMBERJACK_HUT),Vector2.ZERO,Building.State.UNDER_CONSTRUCTION)
	service.register_building(site)
	worker.work_location_id = site.id
	check(service.claim_internal(worker.id,ref,site,R.LOG,eligible)==null,"Unbuilt destination rejected")
	worker.work_location_id = hut.id
	var job = service.claim_internal(worker.id,ref,hut,R.LOG,eligible)
	check(job!=null and job.admission==Job.Admission.INTERNAL and service.inbound_valid(job),"Own internal claim reserves normal inbound")
	check(storage.resources.get_reserved_out(R.LOG)==1 and hut.resources.get_reserved_in(R.LOG)==1,"Normal ledgers reserve exactly once")
	worker.work_location_id = other.id
	check(service.delivery_allowed(job),"Captured admission survives reassignment")
	check(service.claim_internal(worker.id,ref,hut,R.LOG,eligible)==null,"No new old-workplace claim")
	var forged := Job.new(&"forged",storage.id,hut.id,R.LOG,1,worker.id)
	forged.admission = Job.Admission.INTERNAL
	check(not service.delivery_allowed(forged),"Flag alone cannot authorize a job")
	hut.definition.internal_resources.clear()
	check(not service.delivery_allowed(job),"Execution revalidates policy")
	hut.definition.internal_resources = [R.LOG]
	check(service.cancel_job(job) and storage.resources.get_reserved_out(R.LOG)==0 and hut.resources.get_reserved_in(R.LOG)==0,"Cancellation releases reservations")
	worker.work_location_id = hut.id
	hut.resources.add(R.LOG,2)
	check(service.claim_internal(worker.id,ref,hut,R.LOG,eligible)==null,"Full buffer blocks inbound")
	var export_job = service.claim_worker_export(worker.id,hut,storage,R.LOG)
	check(export_job==null,"Full storage rejects export")
	storage.resources.try_take(R.LOG,1)
	export_job = service.claim_worker_export(worker.id,hut,storage,R.LOG)
	check(export_job!=null and export_job.admission==Job.Admission.EXTERNAL,"Generic export uses normal external delivery")
	if export_job!=null: service.cancel_job(export_job)
	check(service.claim_worker_export(worker.id,other,storage,R.LOG)==null,"Generic export cannot use foreign buffer")
	print("Internal logistics: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
