extends RefCounted
## Resolved natural work assignment; only active actions retain this snapshot.
const Area = preload("res://scripts/work_area.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var area: RefCounted
var workplace: RefCounted
func _init(region: RefCounted, building: RefCounted = null) -> void:
	area = region
	workplace = building
func identity() -> Array:
	return [area.id,area.revision,area.center,area.radius,workplace.id if workplace!=null else &""]
static func for_building(building: RefCounted):
	return load("res://scripts/natural_work_context.gd").new(Area.new(building.id,building.position,Coordinates.length_to_sim(building.definition.work_radius)),building)
