extends RefCounted
## Resolved natural work assignment; only active actions retain this snapshot.
const BuildingArea = preload("res://scripts/building_work_area.gd")
var area: RefCounted
var workplace: RefCounted
func _init(region: RefCounted, building: RefCounted = null) -> void:
	area = region
	workplace = building
func identity() -> Array:
	return [area.id,area.revision,area.center,area.radius,workplace.id if workplace!=null else &""]
static func for_building(building: RefCounted, registry: RefCounted = null):
	return load("res://scripts/natural_work_context.gd").new(BuildingArea.resolve(building,registry),building)
