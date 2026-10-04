extends RefCounted
## What the building is, independently of its location or visual scene.
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
var resources: ResourceContainer
var id: StringName
var display_name: String
var type: BuildingType.Type

func _init(building_id: StringName, building_name: String, building_type: BuildingType.Type) -> void:
	id = building_id
	resources = ResourceContainer.new(id)
	display_name = building_name
	type = building_type
