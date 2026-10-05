extends RefCounted
## What the building is, independently of its location or visual scene.
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
const Balance = preload("res://scripts/balance_config.gd")
var production_progress: int = 0 # Shared work minutes; survives worker interruptions/replacement.
var logistics_weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT
var resources: ResourceContainer
var id: StringName
var display_name: String
var type: BuildingType.Type

func _init(building_id: StringName, building_name: String, building_type: BuildingType.Type) -> void:
	id = building_id
	resources = ResourceContainer.new(id)
	display_name = building_name
	type = building_type
