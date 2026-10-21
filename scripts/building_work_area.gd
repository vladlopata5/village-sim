extends RefCounted
## Shared geometry only. Buffers, assignments and service slots belong to the building.
const Area = preload("res://scripts/work_area.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Types = preload("res://scripts/building_type.gd").Type

static func supports(building: RefCounted) -> bool:
	return building != null and building.is_built() and building.type in [Types.LUMBERJACK_HUT,Types.QUARRY,Types.GATHERER_HUT,Types.SHEPHERD_HUT,Types.FARM]

static func resolve(building: RefCounted, registry: RefCounted = null) -> RefCounted:
	if not supports(building): return null
	if registry != null and not building.work_area_override_id.is_empty():
		var custom: RefCounted = registry.get_area(building.work_area_override_id)
		if custom != null: return custom
	return Area.new(building.id,building.position,Coordinates.length_to_sim(building.definition.work_radius))
