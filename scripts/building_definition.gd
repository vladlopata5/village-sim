extends RefCounted
## Shared type description, not a building on the map.
const BuildingType = preload("res://scripts/building_type.gd")
var id: StringName
var type: BuildingType.Type
var display_name: String
var size: Vector2
func _init(type_id: StringName, category: BuildingType.Type, label: String, footprint_size: Vector2) -> void:
	id = type_id
	type = category
	display_name = label
	size = footprint_size
static func for_type(category: BuildingType.Type, label: String = ""):
	var ids := [&"kitchen", &"warehouse", &"gatherer_hut", &"home"]
	var labels := ["Общая кухня", "Склад", "Хижина собирателя", "Дом"]
	var footprint_size := Vector2(64, 48) if category == BuildingType.Type.HOME else Vector2(144, 96)
	return load("res://scripts/building_definition.gd").new(ids[category], category, labels[category] if label.is_empty() else label, footprint_size)
