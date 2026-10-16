extends RefCounted
## One resource unit, without coordinates or scene references.
const ResourceType = preload("res://scripts/resource_type.gd")
const DropResult = preload("res://scripts/cargo_drop_result.gd")
signal changed
var _transferring := false
var resource_type: ResourceType.Type = ResourceType.Type.FOOD
var _amount: int = 0
var amount: int:
	get: return _amount

func put(resource: ResourceType.Type, quantity: int) -> bool:
	if _transferring or amount != 0 or resource not in ResourceType.Type.values() or quantity != 1:
		return false
	resource_type = resource
	_amount = quantity
	changed.emit()
	return true

func clear() -> void:
	if _transferring: return
	_amount = 0
	changed.emit()

# Callbacks commit a one-unit source/destination operation; false must leave it untouched.
# The guard also covers changed callbacks, so they cannot replace an in-flight cargo.
func receive(resource: ResourceType.Type, quantity: int, take: Callable) -> bool:
	if _transferring or amount!=0 or quantity!=1 or resource not in ResourceType.Type.values() or not take.is_valid(): return false
	_transferring=true
	var result: Variant=take.call()
	var accepted: bool=typeof(result)==TYPE_BOOL and result
	if accepted:
		resource_type=resource
		_amount=1
		changed.emit()
	_transferring=false
	return accepted
func deliver(resource: ResourceType.Type, quantity: int, commit: Callable) -> bool:
	if _transferring or quantity!=1 or amount!=quantity or resource_type!=resource or not commit.is_valid(): return false
	_transferring=true
	var result: Variant=commit.call()
	var accepted: bool=typeof(result)==TYPE_BOOL and result
	if accepted:
		_amount=0
		changed.emit()
	_transferring=false
	return accepted
func drop_cargo(commit: Callable) -> int:
	if _transferring or amount!=1 or resource_type not in ResourceType.Type.values() or not commit.is_valid(): return DropResult.Status.FAILED
	_transferring=true
	var result: Variant=commit.call(resource_type,amount)
	var status: int=DropResult.Status.FAILED
	if DropResult.completed(result):
		status=result
		_amount=0
		changed.emit()
	_transferring=false
	return status
