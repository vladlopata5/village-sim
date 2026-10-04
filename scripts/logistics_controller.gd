extends RefCounted
## One fixed FOOD route, one job. Assignment does not command a resident.
const HaulJob = preload("res://scripts/haul_job.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const FOOD = ResourceType.Type.FOOD
const TARGET_STOCK := 3
signal changed
var current_job: HaulJob
var _source: BuildingData
var _destination: BuildingData
var _resident: ResidentData
var _next_id := 1

func setup(source: BuildingData, destination: BuildingData, resident: ResidentData) -> void:
	_source = source
	_destination = destination
	_resident = resident

func recalculate() -> void:
	if current_job != null and current_job.is_active():
		_assign_if_possible()
		changed.emit()
		return
	if _source == null or _destination == null:
		return
	if _source.id != &"warehouse_01" or _destination.id != &"communal_kitchen_01":
		return
	if _source.type != BuildingType.Type.STORAGE or _destination.type != BuildingType.Type.FOOD:
		return
	var source = _source.resources
	var destination = _destination.resources
	if destination.get_amount(FOOD) + destination.get_reserved_in(FOOD) >= TARGET_STOCK:
		return
	if source.get_available_amount(FOOD) < 1 or destination.get_available_free_capacity(FOOD) < 1:
		return
	if not source.reserve_out(FOOD, 1):
		return
	if not destination.reserve_in(FOOD, 1):
		# Roll back only the reservation made by this attempt.
		source.release_out(FOOD, 1)
		return
	current_job = HaulJob.new(StringName("haul_%04d" % _next_id), _source.id, _destination.id, FOOD, 1)
	_next_id += 1
	_assign_if_possible()
	changed.emit()

func _assign_if_possible() -> void:
	if current_job.state != HaulJob.State.RESERVED or _resident == null:
		return
	if _resident.profession == Profession.Type.PORTER and _resident.work_location_id == _source.id:
		current_job.assigned_resident_id = _resident.id
		current_job.state = HaulJob.State.ASSIGNED

func cancel_job(job: HaulJob) -> bool:
	if job == null or job != current_job or not job.is_active():
		return false
	_source.resources.release_out(job.resource_type, job.amount)
	_destination.resources.release_in(job.resource_type, job.amount)
	job.state = HaulJob.State.CANCELLED
	changed.emit()
	return true
