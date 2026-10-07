extends RefCounted
## One resource unit, without coordinates or scene references.
const ResourceType = preload("res://scripts/resource_type.gd")
signal changed
var resource_type: ResourceType.Type = ResourceType.Type.FOOD
var _amount: int = 0
var amount: int:
	get: return _amount

func put(resource: ResourceType.Type, quantity: int) -> bool:
	if amount != 0 or resource not in ResourceType.Type.values() or quantity != 1:
		return false
	resource_type = resource
	_amount = quantity
	changed.emit()
	return true

func clear() -> void:
	_amount = 0
	changed.emit()
