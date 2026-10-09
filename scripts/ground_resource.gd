extends RefCounted
## Physical world data, separate from inventory, containers and presentation.
const ResourceType = preload("res://scripts/resource_type.gd")
const LIFETIME_MINUTES := 3 * 24 * 60
var id: StringName
var reservation_owner_id := &""
var resource_type: ResourceType.Type
var amount: int
var world_position: Vector2
var created_at: int
var lifetime: int = LIFETIME_MINUTES

func _init(resource: ResourceType.Type, quantity: int, position: Vector2, minute: int) -> void:
	resource_type = resource
	amount = quantity
	world_position = position
	created_at = minute

func age_minutes(now: int) -> int:
	return maxi(0, now - created_at)

func reserve(worker_id: StringName) -> bool:
	if worker_id.is_empty() or amount < 1 or not reservation_owner_id.is_empty(): return false
	reservation_owner_id = worker_id
	return true
func release(worker_id: StringName) -> void:
	if reservation_owner_id == worker_id: reservation_owner_id = &""
