extends "res://scripts/building_instance.gd"
## Compatibility constructor for existing prototype buildings and tests.
## These are BuildingInstances, not a second registry or a replacement entity.
const BuildingType = preload("res://scripts/building_type.gd")
func _init(building_id: StringName, building_name: String, building_type: BuildingType.Type) -> void:
	super(building_id, Definition.for_type(building_type, building_name))
