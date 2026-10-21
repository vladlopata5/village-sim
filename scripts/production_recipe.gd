extends RefCounted
## Input/output quantities and actual work-minutes; no building-type execution branches.
var id: StringName
var inputs: Dictionary
var outputs: Dictionary
var optional_outputs: Dictionary = {} # Best-effort products, admitted only at completion.
var work_required: int
func _init(required_inputs: Dictionary, produced_outputs: Dictionary, minutes: int, recipe_id: StringName = &"recipe") -> void:
	id = recipe_id
	inputs = required_inputs.duplicate()
	outputs = produced_outputs.duplicate()
	work_required = minutes

const Goods = preload("res://scripts/resource_type.gd")
static func valid_quantities(values: Dictionary) -> bool:
	for resource in values:
		if not resource is int or resource not in Goods.Type.values(): return false
		if not values[resource] is int or values[resource]<=0: return false
	return true
func is_valid() -> bool:
	return not id.is_empty() and work_required>0 and not outputs.is_empty() and valid_quantities(inputs) and valid_quantities(outputs) and valid_quantities(optional_outputs) and optional_outputs.keys().all(func(resource):return not outputs.has(resource))
# Quantity modes count units of one concrete product, not batches.
func counted_product() -> int:
	return int(outputs.keys()[0]) if outputs.size()==1 and is_valid() else -1
func output_quantity() -> int:
	return int(outputs.values()[0]) if counted_product()>=0 else 0
