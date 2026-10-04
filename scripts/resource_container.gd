extends RefCounted
## Local resources belonging to one owner/place; never a settlement total.
const ResourceType = preload("res://scripts/resource_type.gd")
signal changed(resource: ResourceType.Type, amount: int)
var owner_id: StringName
var _amounts: Dictionary = {}

func _init(owner: StringName) -> void:
	owner_id = owner

func get_amount(resource: ResourceType.Type) -> int:
	return _amounts.get(resource, 0)

func add(resource: ResourceType.Type, amount: int) -> void:
	if amount <= 0:
		return
	_amounts[resource] = get_amount(resource) + amount
	changed.emit(resource, get_amount(resource))

func has_resource(resource: ResourceType.Type, amount: int) -> bool:
	return amount > 0 and get_amount(resource) >= amount

func try_take(resource: ResourceType.Type, amount: int) -> bool:
	if not has_resource(resource, amount):
		return false
	_amounts[resource] = get_amount(resource) - amount
	changed.emit(resource, get_amount(resource))
	return true
