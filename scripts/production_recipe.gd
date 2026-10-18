extends RefCounted
## Input/output quantities and actual work-minutes; no building-type execution branches.
var id: StringName
var inputs: Dictionary
var outputs: Dictionary
var work_required: int
func _init(required_inputs: Dictionary, produced_outputs: Dictionary, minutes: int, recipe_id: StringName = &"recipe") -> void:
	id = recipe_id
	inputs = required_inputs.duplicate()
	outputs = produced_outputs.duplicate()
	work_required = minutes
