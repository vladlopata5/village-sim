extends RefCounted
## Physical presentation dimensions in WORLD units, independent of 2D visual sizes.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Types = preload("res://scripts/building_type.gd").Type
const RESIDENT_RADIUS: float = 0.4
const RESIDENT_HEIGHT: float = 1.44
const BUILDING_SIZES = {
	Types.HOME: Vector2(2.56, 1.92),
	Types.FOOD: Vector2(5.76, 3.84),
	Types.STORAGE: Vector2(5.76, 3.84),
	Types.GATHERER_HUT: Vector2(5.76, 3.84),
}
static func building_size(building: RefCounted) -> Vector2: return BUILDING_SIZES[building.type]
static func footprint(building: RefCounted) -> Rect2:
	var size := building_size(building)
	return Rect2(Coordinates.world_plane(Coordinates.to_world(building.position)) - size / 2.0, size)
static func building_height(building: RefCounted) -> float:
	return 1.6 if building.type == Types.HOME else 2.6
