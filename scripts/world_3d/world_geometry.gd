extends RefCounted
## Physical presentation dimensions in WORLD units, independent of 2D visual sizes.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Types = preload("res://scripts/building_type.gd").Type
const RESIDENT_RADIUS: float = 0.4
const RESIDENT_HEIGHT: float = 1.44
const Grid = preload("res://scripts/build_grid.gd")
static func building_size(building: RefCounted) -> Vector2:
	var cells: Vector2i = building.definition.footprint_cells
	if building.quarter_turns % 2 == 1: cells = Vector2i(cells.y, cells.x)
	return Vector2(cells) * Grid.CELL_SIZE
static func footprint(building: RefCounted) -> Rect2:
	var size := building_size(building)
	return Rect2(Coordinates.world_plane(Coordinates.to_world(building.position)) - size / 2.0, size)
static func building_height(building: RefCounted) -> float:
	if building.type == Types.TOWN_CENTER: return 4.0
	return 1.6 if building.type == Types.HOME else 2.6
