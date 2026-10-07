extends RefCounted
## Successfully claimed delivery, owned by one resident from creation.
const ResourceType = preload("res://scripts/resource_type.gd")
enum State { ASSIGNED, GOING_TO_SOURCE, CARRYING, GOING_TO_DESTINATION, COMPLETED, CANCELLED }
var priority: float = 0.0 # Claim-time porter score snapshot; never refreshed or compared with needs.
var id: StringName
var source_location_id: StringName
var destination_location_id: StringName
var resource_type: ResourceType.Type
var amount: int
var assigned_resident_id: String
var state: State = State.ASSIGNED

func _init(job_id: StringName, source_id: StringName, destination_id: StringName, resource: ResourceType.Type, quantity: int, resident_id: String, job_priority: float = 0.0) -> void:
	assert(not resident_id.is_empty())
	assigned_resident_id = resident_id
	priority = job_priority
	id = job_id
	source_location_id = source_id
	destination_location_id = destination_id
	resource_type = resource
	amount = quantity

func is_active() -> bool:
	return state not in [State.CANCELLED, State.COMPLETED]
