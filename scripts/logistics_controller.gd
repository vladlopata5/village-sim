extends RefCounted
## Delivery selection/reservation service. Only already-owned committed jobs persist.
const EventLog = preload("res://scripts/game_logger.gd")
const HaulJob = preload("res://scripts/haul_job.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Executor = preload("res://scripts/porter_haul_executor.gd")
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
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
var _available := false
var _availability_dirty := true

func setup(source: BuildingInstance, destination: BuildingInstance, resident: ResidentData) -> void:
	_source = source
	_destination = destination
	_resident = resident
	register_building(source)
	register_building(destination)
	if resident != null: register_resident(resident)
func register_building(building: BuildingInstance) -> void:
	if _buildings.has(building.id): return
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
func _on_amount_changed(resource: ResourceType.Type, _amount: int) -> void:
	if resource == FOOD: recalculate()
func _on_reservations_changed(resource: ResourceType.Type) -> void:
	if resource == FOOD: recalculate()
func recalculate() -> void:
	# Explicit debug refresh / local events only. No clock polling or job creation.
	_availability_dirty = true
	if _claiming: return
	changed.emit()
	availability_changed.emit()
func _pairs() -> Array:
	var pairs: Array = []
	for source in _buildings.values():
		for destination in _buildings.values():
			if source == destination: continue
			if source.type == BuildingType.Type.STORAGE and destination.type == BuildingType.Type.FOOD:
				pairs.append({"source": source, "destination": destination, "export": false})
			elif source.type == BuildingType.Type.GATHERER_HUT and destination.type == BuildingType.Type.STORAGE:
				pairs.append({"source": source, "destination": destination, "export": true})
	return pairs
func _valid_pair(pair: Dictionary) -> bool:
	var source: BuildingInstance = pair.source
	var destination: BuildingInstance = pair.destination
	return _buildings.get(source.id) == source and _buildings.get(destination.id) == destination and source != destination and source.is_built() and destination.is_built() and source.resources.get_available_amount(FOOD) > 0 and destination.resources.allows_resource(FOOD) and destination.resources.get_available_free_capacity(FOOD) > 0 and _point(source) is Vector2 and _point(destination) is Vector2
func _point(building: BuildingInstance) -> Variant:
	return _locations.get_position(building.id) if _locations != null else building.position
func _eligible(resident: ResidentData) -> bool:
	if resident == null or resident.profession != Profession.Type.PORTER or resident.inventory.amount != 0: return false
	var workplace: BuildingInstance = _buildings.get(resident.work_location_id)
	return workplace != null and workplace.is_built() and workplace.type == BuildingType.Type.STORAGE
func _can_claim(resident: ResidentData) -> bool:
	if not _eligible(resident) or jobs.any(func(job): return job.assigned_resident_id == resident.id): return false
	var executor = _executors.get(resident.id)
	return executor == null or executor.can_start()
func has_available_job(resident_id: String) -> bool:
	var resident: ResidentData = _residents.get(resident_id)
	if not _can_claim(resident): return false
	if _availability_dirty:
		_available = _pairs().any(_valid_pair)
		_availability_dirty = false
	return _available and position_provider.is_valid() and position_provider.call(resident_id) is Vector2
func collect_candidates(resident_id: String) -> Array:
	# Call at WORK selection (or explicit read-only debug/tests), not world updates.
	var resident: ResidentData = _residents.get(resident_id)
	if not _can_claim(resident) or not position_provider.is_valid(): return []
	var position: Variant = position_provider.call(resident_id)
	if not position is Vector2: return []
	var candidates: Array = []
	for pair in _pairs():
		if not _valid_pair(pair): continue
		var candidate := Candidate.new()
		candidate.source = pair.source
		candidate.destination = pair.destination
		candidate.resource_type = FOOD
		candidate.world_urgency = Priority.export_priority(pair.source.resources, FOOD, pair.source.logistics_weight) if pair.export else Priority.import_priority(pair.destination.resources, FOOD, pair.destination.logistics_weight)
		candidate.route_distance = position.distance_to(_point(pair.source)) + _point(pair.source).distance_to(_point(pair.destination))
		candidate.distance_penalty = distance_penalty(candidate.route_distance)
		candidate.personal_modifier = _get_personal_delivery_modifier(resident, candidate)
		candidate.porter_score = candidate.world_urgency - candidate.distance_penalty + candidate.personal_modifier
		candidates.append(candidate)
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
	var candidates := collect_candidates(resident_id)
	var limit := candidates.size()
	var attempted: Dictionary = {}
	for _attempt in range(limit):
		candidates = candidates.filter(func(candidate): return not attempted.has(candidate.stable_key()))
		var best := _best(candidates)
		if best == null: break
		if logger != null and logger.debug_enabled:
			for candidate in candidates:
				logger.debug(EventLog.LOGISTICS, "%s: candidate %s → %s urgency=%.1f distance=%.1f penalty=%.1f personal=%.1f score=%.1f" % [resident.resident_name, candidate.source.display_name, candidate.destination.display_name, candidate.world_urgency, candidate.route_distance, candidate.distance_penalty, candidate.personal_modifier, candidate.porter_score])
		attempted[best.stable_key()] = true
		var job := _claim_candidate(resident, best)
		if job != null: return job
		candidates = collect_candidates(resident_id) # Bounded fresh evaluation, no stale execution.
	return null
func _claim_candidate(resident: ResidentData, candidate: Candidate) -> HaulJob:
	if not _can_claim(resident) or not _valid_pair({"source": candidate.source, "destination": candidate.destination}): return null
	_claiming = true # Reserve callbacks cannot recursively claim a half-owned delivery.
	var out: bool = candidate.source.resources.reserve_out(candidate.resource_type, 1)
	var incoming: bool = out and candidate.destination.resources.reserve_in(candidate.resource_type, 1)
	# Forced/player/world changes inside synchronous resource signals are rechecked too.
	var valid: bool = incoming and _can_claim(resident) and _buildings.get(candidate.source.id) == candidate.source and _buildings.get(candidate.destination.id) == candidate.destination and candidate.source.is_built() and candidate.destination.is_built()
	valid = valid and _point(candidate.source) is Vector2 and _point(candidate.destination) is Vector2
	valid = valid and candidate.source.resources.get_reserved_out(candidate.resource_type) >= 1 and candidate.destination.resources.get_reserved_in(candidate.resource_type) >= 1
	if not valid:
		if out: candidate.source.resources.release_out(candidate.resource_type, 1)
		if incoming: candidate.destination.resources.release_in(candidate.resource_type, 1)
		_claiming = false
		recalculate()
		return null
	var job := HaulJob.new(StringName("haul_%04d" % _next_id), candidate.source.id, candidate.destination.id, candidate.resource_type, 1, resident.id, candidate.porter_score)
	_next_id += 1
	jobs.append(job)
	current_job = job
	var executor = _executors.get(resident.id)
	if executor != null: executor.job = job
	_claiming = false
	if logger != null: logger.info(EventLog.LOGISTICS, "%s: выбрал доставку 1 FOOD — %s → %s" % [resident.resident_name, candidate.source.display_name, candidate.destination.display_name])
	recalculate()
	return job
func get_job(resident_id: String) -> HaulJob:
	for job in jobs:
		if job.assigned_resident_id == resident_id: return job
	return null
func finish_job(job: HaulJob) -> void:
	jobs.erase(job)
	recalculate()
func cancel_job(job: HaulJob) -> bool:
	if job == null or job not in jobs or not job.is_active() or job.state in [HaulJob.State.CARRYING, HaulJob.State.GOING_TO_DESTINATION]: return false
	var executor = _executors.get(job.assigned_resident_id)
	if executor != null and executor.job == job: return executor.cancel("отмена задачи")
	# Isolated data-level claim without execution binding.
	_buildings[job.source_location_id].resources.release_out(job.resource_type, job.amount)
	_buildings[job.destination_location_id].resources.release_in(job.resource_type, job.amount)
	job.state = HaulJob.State.CANCELLED
	finish_job(job)
	job_cancelled.emit(job.assigned_resident_id)
	return true
func bind_world(clock: Node, locations: RefCounted) -> void:
	_clock = clock
	_locations = locations
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
