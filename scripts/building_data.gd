extends RefCounted
## What the building is, independently of its location or visual scene.
const BuildingType = preload("res://scripts/building_type.gd")
var id: StringName
var display_name: String
var type: BuildingType.Type

func _init(building_id: StringName, building_name: String, building_type: BuildingType.Type) -> void:
	id = building_id
	display_name = building_name
	type = building_type
