extends RefCounted
## Delivery selection/reservation service. Only already-owned committed jobs persist.
const EventLog = preload("res://scripts/game_logger.gd")
const HaulJob = preload("res://scripts/haul_job.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Executor = preload("res://scripts/haul_executor.gd")
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
var sources = preload("res://scripts/resource_sources.gd").new()
var _internal: Dictionary = {} # Job-bound captured authorization, never a second resource ledger.
var _inbound: Dictionary = {} # Owned inbound reservations for committed hauls.
const FOOD = ResourceType.Type.FOOD
signal changed
signal availability_changed
signal cargo_dropped(resource: ResourceType.Type, amount: int, resident_id: String)
signal job_cancelled(resident_id: String)
signal delivered
var logger: EventLog
var position_provider: Callable
var jobs: Array[HaulJob] = [] # Active committed deliveries, never offers.
var current_job: HaulJob # Last claim for prototype debug UI; execution uses resident ownership.
var _residents: Dictionary = {}
var _executors: Dictionary = {}
var _buildings: Dictionary = {}
var _source: BuildingInstance
var _destination: BuildingInstance
var _resident: ResidentData
var _clock: Node
var _locations: RefCounted
var _next_id := 1
var _claiming := false

func setup(source: BuildingInstance, destination: BuildingInstance, resident: ResidentData) -> void:
	sources.buildings = _buildings
	if not sources.changed.is_connected(recalculate): sources.changed.connect(recalculate)
	_source = source
	_destination = destination
	_resident = resident
	register_building(source)
	register_building(destination)
	if resident != null: register_resident(resident)
func register_building(building: BuildingInstance) -> void:
	if building == null or _buildings.has(building.id): return
	_buildings[building.id] = building
	building.resources.availability_changed.connect(_on_amount_changed)
	building.resources.reservations_changed.connect(_on_reservations_changed)
	building.construction_changed.connect(recalculate)
	recalculate()
func remove_building(id: StringName) -> void:
	var building: BuildingInstance = _buildings.get(id)
	if building == null: return
	for active in jobs.duplicate():
		if active.source_location_id == id or active.destination_location_id == id:
			var owner = _executors.get(active.assigned_resident_id)
			if owner != null: owner.cancel("здание удалено")
			else: cancel_job(active)
	building.resources.availability_changed.disconnect(_on_amount_changed)
	building.resources.reservations_changed.disconnect(_on_reservations_changed)
	building.construction_changed.disconnect(recalculate)
	_buildings.erase(id)
	for executor in _executors.values(): executor.validate_job()
	recalculate()
func add_production_source(hut: BuildingInstance) -> void: register_building(hut)
func add_kitchen(kitchen: BuildingInstance) -> void: register_building(kitchen)
func add_warehouse(warehouse: BuildingInstance) -> void: register_building(warehouse)
func register_resident(resident: ResidentData) -> void: _residents[resident.id] = resident
func _on_amount_changed(_resource: ResourceType.Type, _amount: int) -> void:
	recalculate()
func _on_reservations_changed(_resource: ResourceType.Type) -> void:
	recalculate()
func recalculate() -> void:
	# Explicit debug refresh / local events only. No clock polling or job creation.
	if _claiming: return
	for executor in _executors.values():
		if executor.job != null: executor.validate_job()
	changed.emit()
	availability_changed.emit()
func allows_external_delivery(source: BuildingInstance, destination: BuildingInstance, resource: int) -> bool:
	if source == null or destination == null or source == destination: return false
	if _buildings.get(source.id) != source or _buildings.get(destination.id) != destination: return false
	if not source.is_built() or not destination.is_built(): return false
	# Storage balancing needs explicit future demand, never ordinary hauling.
	if source.definition.is_storage and destination.definition.is_storage: return false
	return source.definition.allows_external_export(resource) and destination.definition.allows_external_import(resource) and source.resources.allows_resource(resource) and destination.resources.allows_resource(resource) and source.resources.get_capacity(resource)>0 and destination.resources.get_capacity(resource)>0
func external_destinations(source: BuildingInstance, resource: int) -> Array:
	return _buildings.values().filter(func(destination): return allows_external_delivery(source,destination,resource) and destination.resources.get_available_free_capacity(resource)>0)
func _porter_pair(resident: ResidentData, source: BuildingInstance, destination: BuildingInstance) -> bool:
	return source.id == resident.work_location_id or destination.id == resident.work_location_id
func _pairs() -> Array:
	var pairs: Array = []
	for source in _buildings.values():
		for destination in _buildings.values():
			for resource in ResourceType.Type.values():
				if allows_external_delivery(source,destination,resource):
					pairs.append({"source":source,"destination":destination,"resource":resource,"export":not source.definition.is_storage})
	return pairs
func _valid_pair(pair: Dictionary) -> bool:
	var source: BuildingInstance = pair.source
	var destination: BuildingInstance = pair.destination
	var resource: ResourceType.Type = pair.get("resource",FOOD)
	return allows_external_delivery(source,destination,resource) and source.resources.get_available_amount(resource)>0 and destination.resources.get_available_free_capacity(resource)>0 and _point(source) is Vector2 and _point(destination) is Vector2
func _point(building: BuildingInstance) -> Variant:
	return (_locations.get_resource_position(building.id) if _locations.has_method("get_resource_position") else _locations.get_position(building.id)) if _locations != null else building.position
func _eligible(resident: ResidentData) -> bool:
	if resident == null or resident.profession != Profession.Type.PORTER or resident.inventory.amount != 0: return false
	var workplace: BuildingInstance = _buildings.get(resident.work_location_id)
	return workplace != null and workplace.is_built() and workplace.definition.is_storage and _point(workplace) is Vector2
func _can_claim(resident: ResidentData) -> bool:
	var eligible := _eligible(resident)
	if not eligible or jobs.any(func(job): return job.assigned_resident_id == resident.id): return false
	var executor = _executors.get(resident.id)
	return executor == null or executor.can_start()
func has_available_job(resident_id: String) -> bool:
	# Availability needs existence, not the best score. Nothing survives this probe.
	return not _candidate_scan(resident_id,true).is_empty()
func collect_candidates(resident_id: String) -> Array:
	# Public diagnostic API still returns ALL fully reachable candidates in enumeration order.
	var candidates := _cheap_candidates(resident_id)
	var position: Variant = position_provider.call(resident_id) if position_provider.is_valid() else null
	if not position is Vector2: return []
	return candidates.filter(func(candidate): return _routes_available(candidate,position))
func _routes_available(candidate: Candidate, position: Vector2) -> bool:
	var source_position: Variant = sources.point(candidate.source_ref)
	if not source_position is Vector2 or not source_position.is_finite() or not sources.reachable(position,source_position): return false
	var destination_position: Variant = _point(candidate.destination)
	return destination_position is Vector2 and destination_position.is_finite() and sources.reachable(source_position,destination_position)
func _ranked_before(a: Candidate, b: Candidate) -> bool:
	return a.porter_score > b.porter_score or (a.porter_score == b.porter_score and a.stable_key() < b.stable_key())
func _first_reachable(resident_id: String, candidates: Array, attempted: Dictionary = {}) -> Candidate:
	var position: Variant = position_provider.call(resident_id) if position_provider.is_valid() else null
	if not position is Vector2 or not position.is_finite(): return null
	candidates.sort_custom(_ranked_before)
	for candidate in candidates:
		if not attempted.has(candidate.stable_key()) and _routes_available(candidate,position): return candidate
	return null
func _cheap_candidates(resident_id: String) -> Array:
	return _candidate_scan(resident_id,false)
func _candidate_scan(resident_id: String, first_reachable_only: bool) -> Array:
	# Shared eligibility/scoring; no claims or retained availability state.
	# The read-only probe checks routes one candidate at a time and stops at the first.
	# Claim still builds the full current pool and ranks it by exact score/stable key.
	var resident: ResidentData = _residents.get(resident_id)
	if not _can_claim(resident) or not position_provider.is_valid(): return []
	var position: Variant = position_provider.call(resident_id)
	if not position is Vector2 or not position.is_finite(): return []
	var candidates: Array = []
	for pair in _pairs():
		if not _porter_pair(resident,pair.source,pair.destination) or not _valid_pair(pair): continue
		var candidate := Candidate.new()
		candidate.source = pair.source
		candidate.source_ref = Source.new(Source.Kind.CONTAINER,pair.source.id)
		candidate.destination = pair.destination
		candidate.resource_type = pair.get("resource",FOOD)
		candidate.world_urgency = Priority.export_priority(pair.source.resources, candidate.resource_type, pair.source.logistics_weight) if pair.export else Priority.import_priority(pair.destination.resources, candidate.resource_type, pair.destination.logistics_weight)
		var source_position: Vector2 = _point(pair.source)
		var destination_position: Vector2 = _point(pair.destination)
		candidate.route_distance = position.distance_to(source_position) + source_position.distance_to(destination_position)
		candidate.distance_penalty = distance_penalty(candidate.route_distance)
		candidate.personal_modifier = _get_personal_delivery_modifier(resident, candidate)
		candidate.porter_score = candidate.world_urgency - candidate.distance_penalty + candidate.personal_modifier
		if not is_finite(candidate.porter_score): continue
		if first_reachable_only:
			if _routes_available(candidate,position): return [candidate]
		else: candidates.append(candidate)
	var base: BuildingInstance = _buildings.get(resident.work_location_id)
	var base_position: Variant = _point(base) if base != null else null
	if is_instance_valid(sources.ground) and base_position is Vector2:
		for drop in sources.ground.drops:
			var source_ref := Source.new(Source.Kind.GROUND,drop.id)
			if not sources.available(source_ref,drop.resource_type) or not base.definition.allows_external_import(drop.resource_type) or base.resources.get_available_free_capacity(drop.resource_type)<1: continue
			var candidate := Candidate.new()
			candidate.source_ref = source_ref
			candidate.destination = base
			candidate.resource_type = drop.resource_type
			candidate.world_urgency = Priority.import_priority(base.resources,drop.resource_type,base.logistics_weight)
			candidate.route_distance = position.distance_to(drop.world_position)+drop.world_position.distance_to(base_position)
			candidate.distance_penalty = distance_penalty(candidate.route_distance)
			candidate.personal_modifier = _get_personal_delivery_modifier(resident,candidate)
			candidate.porter_score = candidate.world_urgency-candidate.distance_penalty+candidate.personal_modifier+Balance.PORTER_GROUND_CLEANUP_BONUS
			if not is_finite(candidate.porter_score): continue
			if first_reachable_only:
				if _routes_available(candidate,position): return [candidate]
			else: candidates.append(candidate)
	return candidates
func distance_penalty(distance: float) -> float:
	return pow(distance / Balance.PORTER_DISTANCE_SCALE, 2.0) * Balance.PORTER_DISTANCE_WEIGHT
func _get_personal_delivery_modifier(_worker: ResidentData, _candidate: Candidate) -> float: return 0.0
func _best(candidates: Array) -> Candidate:
	var best: Candidate = null
	for candidate in candidates:
		if best == null or candidate.porter_score > best.porter_score or (candidate.porter_score == best.porter_score and candidate.stable_key() < best.stable_key()): best = candidate
	return best
func claim_best_job(resident_id: String) -> HaulJob:
	if _claiming: return null
	var resident: ResidentData = _residents.get(resident_id)
	var candidates := _cheap_candidates(resident_id)
	# Keep finite retries and one attempt per key, without an eager route-count pass.
	var limit := candidates.size()
	var attempted: Dictionary = {}
	for _attempt in range(limit):
		var best := _first_reachable(resident_id,candidates,attempted)
		if best == null: break
		if logger != null and logger.debug_enabled:
			var candidate := best
			logger.debug(EventLog.LOGISTICS, "%s: candidate %s → %s urgency=%.1f distance=%.1f penalty=%.1f personal=%.1f score=%.1f" % [resident.resident_name, sources.label(candidate.source_ref), candidate.destination.display_name, candidate.world_urgency, candidate.route_distance, candidate.distance_penalty, candidate.personal_modifier, candidate.porter_score])
		attempted[best.stable_key()] = true
		var job := _claim_candidate(resident, best)
		if job != null: return job
		candidates = _cheap_candidates(resident_id) # Bounded fresh evaluation, no stale execution.
	return null
func _claim_candidate(resident: ResidentData, candidate: Candidate) -> HaulJob:
	return _claim_delivery(resident,candidate)
func _porter_base_valid(id: StringName) -> bool:
	var base: BuildingInstance = _buildings.get(id)
	return base != null and base.is_built() and base.definition.is_storage and _point(base) is Vector2
func _claim_delivery(resident: ResidentData, candidate: Candidate) -> HaulJob:
	if candidate.source_ref == null and candidate.source != null: candidate.source_ref = Source.new(Source.Kind.CONTAINER,candidate.source.id)
	if resident == null or candidate.source_ref==null or (candidate.source_ref.kind==Source.Kind.CONTAINER and not _porter_pair(resident,candidate.source,candidate.destination)) or (candidate.source_ref.kind==Source.Kind.GROUND and candidate.destination.id!=resident.work_location_id): return null
	var job := claim_transport(resident.id,candidate.source_ref,candidate.destination,candidate.resource_type,_can_claim.bind(resident),false,_porter_base_valid.bind(resident.work_location_id),true,candidate.porter_score)
	if job != null: job.workplace_location_id = resident.work_location_id
	return job
func claim_transport(resident_id: String, source_ref: Source, destination: BuildingInstance, resource: int, eligibility: Callable, work_phase_only: bool = true, validation: Callable = Callable(), award_xp: bool = false, score: float = 0.0, internal_workplace: BuildingInstance = null) -> HaulJob:
	# Controllers supply gameplay eligibility. This transaction only owns reservations.
	var resident: ResidentData = _residents.get(resident_id)
	var executor = _executors.get(resident_id)
	if _claiming or resident==null or (executor!=null and not executor.can_start()) or get_job(resident_id)!=null or not eligibility.call(): return null
	if not _admission_at_claim(resident,destination,resource,internal_workplace) or destination.resources.get_available_free_capacity(resource)<1: return null
	var start: Variant = position_provider.call(resident_id) if position_provider.is_valid() else null
	var end: Variant = _point(destination)
	if not start is Vector2 or not end is Vector2 or not sources.available(source_ref,resource) or not sources.reachable(start,sources.point(source_ref)) or not sources.reachable(sources.point(source_ref),end): return null
	if source_ref.kind==Source.Kind.CONTAINER and source_ref.id==destination.id: return null
	_claiming = true
	var id := StringName("haul_%04d" % _next_id)
	_next_id += 1
	var out: bool = sources.reserve(source_ref,resource,id)
	var incoming := false
	if out:
		_inbound[id] = {"destination":destination,"resource":resource}
		incoming = destination.resources.reserve_in(resource,1)
		if not incoming: _inbound.erase(id)
	var valid: bool = incoming and eligibility.call() and (executor==null or executor.can_start()) and _buildings.get(destination.id)==destination and destination.is_built() and _admission_at_claim(resident,destination,resource,internal_workplace) and sources.reserved(source_ref,resource,id) and destination.resources.get_reserved_in(resource)>=1 and _point(destination) is Vector2 and sources.point(source_ref) is Vector2
	valid = valid and (not validation.is_valid() or validation.call())
	if valid: valid = sources.reachable(start,sources.point(source_ref)) and sources.reachable(sources.point(source_ref),_point(destination))
	if not valid:
		if out: sources.release(source_ref,resource,id)
		if incoming:
			_inbound.erase(id)
			destination.resources.release_in(resource,1)
		_claiming = false
		recalculate()
		return null
	var job := HaulJob.new(id,source_ref.id,destination.id,resource,1,resident_id,score)
	if internal_workplace != null:
		job.admission = HaulJob.Admission.INTERNAL
		job.workplace_location_id = internal_workplace.id
		_internal[id] = {"job":job,"worker":resident,"workplace":internal_workplace,"resource":resource}
	job.source_ref = source_ref
	job.work_phase_only = work_phase_only
	job.validation = validation
	job.award_logistics_xp = award_xp
	jobs.append(job)
	current_job = job
	if executor!=null: executor.job = job
	_claiming = false
	if logger!=null: logger.info(EventLog.LOGISTICS,"%s: выбрал доставку 1 %s — %s → %s" % [resident.resident_name,ResourceType.Type.keys()[resource],sources.label(source_ref),destination.display_name])
	recalculate()
	return job
func inbound_valid(job: HaulJob) -> bool:
	var row: Dictionary = _inbound.get(job.id,{})
	if row.is_empty() or _buildings.get(job.destination_location_id)!=row.destination or row.resource!=job.resource_type: return false
	var managed := 0
	for claim in _inbound.values():
		if claim.destination==row.destination and claim.resource==row.resource: managed += 1
	return row.destination.resources.get_reserved_in(job.resource_type)>=managed
func release_inbound(job: HaulJob) -> void:
	var row: Dictionary = _inbound.get(job.id,{})
	if row.is_empty(): return
	_inbound.erase(job.id)
	row.destination.resources.release_in(job.resource_type,1)
func deliver_inbound(job: HaulJob) -> bool:
	if not inbound_valid(job): return false
	var row: Dictionary = _inbound[job.id]
	_inbound.erase(job.id)
	if row.destination.resources.add_reserved(job.resource_type,1): return true
	_inbound[job.id] = row
	return false
func get_job(resident_id: String) -> HaulJob:
	for job in jobs:
		if job.assigned_resident_id == resident_id: return job
	return null
func finish_job(job: HaulJob) -> void:
	_internal.erase(job.id)
	jobs.erase(job)
	recalculate()
func cancel_job(job: HaulJob) -> bool:
	if job == null or job not in jobs or not job.is_active() or job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]: return false
	var executor = _executors.get(job.assigned_resident_id)
	if executor != null and executor.job == job: return executor.cancel("отмена задачи")
	# Isolated data-level claim without execution binding.
	sources.release(job.source_ref,job.resource_type,job.id)
	release_inbound(job)
	job.state = HaulJob.State.CANCELLED
	finish_job(job)
	job_cancelled.emit(job.assigned_resident_id)
	return true
func bind_world(clock: Node, locations: RefCounted) -> void:
	_clock = clock
	_locations = locations
	sources.locations = locations
func bind_execution(clock: Node, locations: RefCounted, intents: Node, schedule: Node) -> void:
	use_executor(intents.resident_data, clock, locations, intents, schedule)
func use_executor(resident: ResidentData, clock: Node, locations: RefCounted, intents: Node, _schedule: Node) -> bool:
	bind_world(clock, locations)
	_resident = resident
	if not _executors.has(resident.id):
		var executor := Executor.new()
		executor.setup(self, resident, clock, locations, intents)
		_executors[resident.id] = executor
	return executor_available(resident.id)
func executor_available(resident_id: String = "") -> bool:
	var executor = _executors.get(resident_id if not resident_id.is_empty() else (_resident.id if _resident != null else ""))
	return executor == null or executor.job == null
func start_claimed_job(job: HaulJob, resident_id: String) -> bool:
	var executor = _executors.get(resident_id)
	return executor != null and job != null and job.assigned_resident_id == resident_id and executor.start(job)
func unbind_execution() -> void:
	for executor in _executors.values(): executor.unbind()
	_executors.clear()
func has_work() -> bool: return _resident != null and has_available_job(_resident.id)

func drop_cargo(resource: ResourceType.Type, amount: int, resident_id: String) -> void:
	cargo_dropped.emit(resource, amount, resident_id)
func notify_delivery() -> void:
	delivered.emit()

func _worker_at(resident: ResidentData, workplace: BuildingInstance) -> bool:
	return resident != null and workplace != null and _buildings.get(workplace.id)==workplace and workplace.is_built() and resident.work_location_id==workplace.id and resident.work_area_id.is_empty() and workplace.definition.worker_profession!=Profession.Type.NONE and resident.profession==workplace.definition.worker_profession
func _admission_at_claim(resident: ResidentData, destination: BuildingInstance, resource: int, internal_workplace: BuildingInstance) -> bool:
	if destination==null or _buildings.get(destination.id)!=destination or not destination.is_built() or not destination.resources.allows_resource(resource): return false
	if internal_workplace==null: return destination.definition.allows_external_import(resource)
	return destination==internal_workplace and _worker_at(resident,destination) and destination.definition.allows_internal_import(resource)
func delivery_allowed(job: HaulJob) -> bool:
	var destination: BuildingInstance = _buildings.get(job.destination_location_id)
	if destination==null or not destination.is_built() or not destination.resources.allows_resource(job.resource_type): return false
	if job.admission==HaulJob.Admission.EXTERNAL: return destination.definition.allows_external_import(job.resource_type)
	var captured: Dictionary = _internal.get(job.id,{})
	return not captured.is_empty() and captured.job==job and captured.worker.id==job.assigned_resident_id and captured.workplace==destination and captured.resource==job.resource_type and job.workplace_location_id==destination.id and destination.definition.allows_internal_import(job.resource_type)
func claim_internal(resident_id: String, source_ref: Source, workplace: BuildingInstance, resource: int, eligibility: Callable) -> HaulJob:
	return claim_transport(resident_id,source_ref,workplace,resource,eligibility,true,Callable(),false,0.0,workplace)
func claim_worker_export(resident_id: String, workplace: BuildingInstance, destination: BuildingInstance, resource: int, eligibility: Callable = Callable(), award_xp: bool = false) -> HaulJob:
	var resident: ResidentData = _residents.get(resident_id)
	if not _worker_at(resident,workplace) or destination==null or not allows_external_delivery(workplace,destination,resource): return null
	var allowed := func(): return _worker_at(resident,workplace) and resident.inventory.amount==0 and (not eligibility.is_valid() or eligibility.call())
	return claim_transport(resident_id,Source.new(Source.Kind.CONTAINER,workplace.id),destination,resource,allowed,true,Callable(),award_xp)
func claim_own_export(resident_id: String, destination: BuildingInstance) -> HaulJob:
	var resident: ResidentData = _residents.get(resident_id)
	if resident==null: return null
	return claim_worker_export(resident_id,_buildings.get(resident.work_location_id),destination,ResourceType.Type.LOG,Callable(),true)
