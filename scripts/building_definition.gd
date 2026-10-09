extends RefCounted
## Shared type description, not a building on the map.
const Balance = preload("res://scripts/balance_config.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
# Prototype construction balance belongs to type definitions, not execution.
const BuildingType = preload("res://scripts/building_type.gd")
const CONSTRUCTION_BALANCE = {
	BuildingType.Type.LUMBERJACK_HUT: {"wood":10,"minutes":180,"builders":2},
	BuildingType.Type.FOOD: {"wood": 15, "minutes": 240, "builders": 2},
	BuildingType.Type.STORAGE: {"wood": 15, "minutes": 240, "builders": 2},
	BuildingType.Type.GATHERER_HUT: {"wood": 10, "minutes": 180, "builders": 2},
	BuildingType.Type.HOME: {"wood": 10, "minutes": 180, "builders": 2},
}
# Explicit 3D physical area in build cells; legacy size remains the 2D visual footprint.
const FOOTPRINT_CELLS = {
	BuildingType.Type.LUMBERJACK_HUT: Vector2i(8,6),
	BuildingType.Type.HOME: Vector2i(6, 4),
	BuildingType.Type.STORAGE: Vector2i(12, 8),
	BuildingType.Type.FOOD: Vector2i(12, 8),
	BuildingType.Type.GATHERER_HUT: Vector2i(12, 8),
}
# External haul policy is independent from ResourceContainer storage/direct deposits.
const LOGISTICS_FLOW = {
	BuildingType.Type.STORAGE: {
		ResourceType.Type.FOOD: {"import":true,"export":true},
		ResourceType.Type.WOOD: {"import":true,"export":true},
		ResourceType.Type.LOG: {"import":true,"export":true},
	},
	BuildingType.Type.FOOD: {ResourceType.Type.FOOD:{"import":true,"export":false}},
	BuildingType.Type.GATHERER_HUT: {ResourceType.Type.FOOD:{"import":false,"export":true}},
	BuildingType.Type.LUMBERJACK_HUT: {ResourceType.Type.LOG:{"import":false,"export":true}},
}
var logistics_flow: Dictionary
var worker_capacity := 0 # Zero keeps existing unlimited workplace semantics.
var work_radius := 0.0 # WORLD units, unrelated to visual footprint.
var target_tree_count := 0
var local_resource_capacity := 0
var footprint_cells: Vector2i
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
	logistics_flow = LOGISTICS_FLOW.get(category,{}).duplicate(true)
	footprint_cells = FOOTPRINT_CELLS[category]
	display_name = label
	size = footprint_size
	construction_requirements = requirements.duplicate()
	construction_work_required = maxi(work_minutes, 0)
	max_builders = maxi(builder_limit, 0)
	housing_capacity = maxi(resident_capacity, 0)
static func for_type(category: BuildingType.Type, label: String = ""):
	var ids := [&"kitchen", &"warehouse", &"gatherer_hut", &"home", &"lumberjack_hut"]
	var labels := ["Общая кухня", "Склад", "Хижина собирателя", "Дом", "Хижина лесоруба"]
	var footprint_size := Vector2(64, 48) if category == BuildingType.Type.HOME else Vector2(144, 96)
	var construction: Dictionary = CONSTRUCTION_BALANCE[category]
	var result = load("res://scripts/building_definition.gd").new(ids[category], category, labels[category] if label.is_empty() else label, footprint_size, {ResourceType.Type.WOOD: construction.wood}, construction.minutes, construction.builders, Balance.HOUSE_RESIDENT_CAPACITY if category == BuildingType.Type.HOME else 0)

	if category == BuildingType.Type.LUMBERJACK_HUT:
		result.worker_capacity = Balance.LUMBERJACK_WORKER_CAPACITY
		result.work_radius = Balance.LUMBERJACK_WORK_RADIUS
		result.target_tree_count = Balance.LUMBERJACK_TARGET_TREE_COUNT
		result.local_resource_capacity = Balance.LUMBERJACK_LOG_CAPACITY
	return result

func allows_external_import(resource: int) -> bool:
	return logistics_flow.get(resource,{}).get("import",false)
func allows_external_export(resource: int) -> bool:
	return logistics_flow.get(resource,{}).get("export",false)
