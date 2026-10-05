extends RefCounted
## Delivery promise only: no coordinates, inventory or movement.
const ResourceType = preload("res://scripts/resource_type.gd")
enum State { RESERVED, ASSIGNED, GOING_TO_SOURCE, CARRYING, GOING_TO_DESTINATION, COMPLETED, CANCELLED }
var priority: int = 0 # Internal job urgency; never compared with Need priority.
var id: StringName
var source_location_id: StringName
var destination_location_id: StringName
var resource_type: ResourceType.Type
var amount: int
var assigned_resident_id: String = ""
var state: State = State.RESERVED

func _init(job_id: StringName, source_id: StringName, destination_id: StringName, resource: ResourceType.Type, quantity: int, job_priority: int = 0) -> void:
	priority = job_priority
	id = job_id
	source_location_id = source_id
	destination_location_id = destination_id
	resource_type = resource
	amount = quantity

func is_active() -> bool:
	return state not in [State.CANCELLED, State.COMPLETED]
