extends RefCounted
## Shared type description, not a building on the map.
const Balance = preload("res://scripts/balance_config.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
# Prototype construction balance belongs to type definitions, not execution.
const BuildingType = preload("res://scripts/building_type.gd")
const CONSTRUCTION_BALANCE = {
	BuildingType.Type.FOOD: {"wood": 15, "minutes": 240, "builders": 2},
	BuildingType.Type.STORAGE: {"wood": 15, "minutes": 240, "builders": 2},
	BuildingType.Type.GATHERER_HUT: {"wood": 10, "minutes": 180, "builders": 2},
	BuildingType.Type.HOME: {"wood": 10, "minutes": 180, "builders": 2},
}
var id: StringName
var type: BuildingType.Type
var display_name: String
var size: Vector2
var construction_requirements: Dictionary
var construction_work_required: int
var max_builders: int
var housing_capacity: int
func _init(type_id: StringName, category: BuildingType.Type, label: String, footprint_size: Vector2, requirements: Dictionary = {}, work_minutes: int = 0, builder_limit: int = 0, resident_capacity: int = 0) -> void:
	id = type_id
	type = category
	display_name = label
	size = footprint_size
	construction_requirements = requirements.duplicate()
	construction_work_required = maxi(work_minutes, 0)
	max_builders = maxi(builder_limit, 0)
	housing_capacity = maxi(resident_capacity, 0)
static func for_type(category: BuildingType.Type, label: String = ""):
	var ids := [&"kitchen", &"warehouse", &"gatherer_hut", &"home"]
	var labels := ["Общая кухня", "Склад", "Хижина собирателя", "Дом"]
	var footprint_size := Vector2(64, 48) if category == BuildingType.Type.HOME else Vector2(144, 96)
	var construction: Dictionary = CONSTRUCTION_BALANCE[category]
	return load("res://scripts/building_definition.gd").new(ids[category], category, labels[category] if label.is_empty() else label, footprint_size, {ResourceType.Type.WOOD: construction.wood}, construction.minutes, construction.builders, Balance.HOUSE_RESIDENT_CAPACITY if category == BuildingType.Type.HOME else 0)
