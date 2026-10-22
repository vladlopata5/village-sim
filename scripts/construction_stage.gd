extends RefCounted
## Reusable data for one finite construction step; visuals never drive completion.
var id: StringName
var display_name: String
var materials: Dictionary
var work_minutes: int
var visual_id: StringName
func _init(key: StringName, label: String, requirements: Dictionary, minutes: int, visual: StringName) -> void:
	id=key;display_name=label;materials=requirements.duplicate();work_minutes=minutes;visual_id=visual
func is_valid() -> bool:
	if id.is_empty() or display_name.is_empty() or visual_id.is_empty() or work_minutes<=0:return false
	for resource in materials:
		if resource not in preload("res://scripts/resource_type.gd").Type.values() or not materials[resource] is int or materials[resource]<=0:return false
	return true
