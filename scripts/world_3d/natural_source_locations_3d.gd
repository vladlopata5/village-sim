extends RefCounted
## Approach annulus for a finite natural source; positions remain simulation-space.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var navigation: RefCounted
func interaction_radius(source: RefCounted) -> float:
	# Preserve the maximum reach of the previous three perimeter rings.
	return source.physical_radius + Geometry.RESIDENT_RADIUS + 0.5 + 2.0*navigation.CELL_SIZE
func in_range(source: RefCounted, point: Vector2) -> bool:
	var distance := Coordinates.length_to_world(source.position.distance_to(point))
	return distance >= source.physical_radius+Geometry.RESIDENT_RADIUS-0.00001 and distance <= interaction_radius(source)+0.00001
func resolve(source: RefCounted, from_sim: Vector2) -> Variant:
	var path: PackedVector3Array = navigation.find_path_to_radius(Coordinates.to_world(from_sim),Coordinates.to_world(source.position),interaction_radius(source),source.physical_radius+Geometry.RESIDENT_RADIUS)
	if path.is_empty(): return null
	return Coordinates.to_sim(path[-1])
func is_available(point: Vector2) -> bool:
	return navigation.is_world_walkable(Coordinates.to_world(point))
