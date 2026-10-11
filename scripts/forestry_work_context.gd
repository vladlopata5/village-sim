extends RefCounted
## Transient context, captured by committed actions.
const Area = preload("res://scripts/work_area.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
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
static func for_building(building: RefCounted):
	return load("res://scripts/forestry_work_context.gd").new(Area.new(building.id,building.position,Coordinates.length_to_sim(building.definition.work_radius)),building)
