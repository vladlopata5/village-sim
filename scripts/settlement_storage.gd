extends RefCounted
## One shared stock, without a physical storage building or inventory UI.
const ResourceType = preload("res://scripts/resource_type.gd")
signal changed(resource: ResourceType.Type, amount: int)
var _amounts: Dictionary = {}

func get_amount(resource: ResourceType.Type) -> int:
	return _amounts.get(resource, 0)

func add(resource: ResourceType.Type, amount: int) -> void:
	if amount <= 0:
		return
	_amounts[resource] = get_amount(resource) + amount
	changed.emit(resource, get_amount(resource))

func try_consume(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or get_amount(resource) < amount:
		return false
	_amounts[resource] = get_amount(resource) - amount
	changed.emit(resource, get_amount(resource))
	return true
