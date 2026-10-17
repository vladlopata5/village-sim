extends RefCounted
## Transient context, captured by committed actions.
const Area = preload("res://scripts/work_area.gd")
const BuildingArea = preload("res://scripts/building_work_area.gd")
enum Mode { BUILDING, FREE }
var mode: Mode
var area: Area
var hut: RefCounted
func _init(region: Area, workplace: RefCounted = null) -> void:
	area = region
	hut = workplace
	mode = Mode.FREE if hut == null else Mode.BUILDING
func identity() -> Array:
	return [mode,area.id,area.revision,area.center,area.radius,hut.id if hut != null else &""]
static func for_building(building: RefCounted, registry: RefCounted = null):
	return load("res://scripts/forestry_work_context.gd").new(BuildingArea.resolve(building,registry),building)
