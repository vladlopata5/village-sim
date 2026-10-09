extends RefCounted
## Small chopping perimeter resolver, not an interaction-point framework.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var navigation: RefCounted
func resolve(tree: RefCounted, from_sim: Vector2) -> Variant:
	var center := Coordinates.to_world(tree.position)
	var from_world := Coordinates.to_world(from_sim)
	var best: Variant = null
	var best_distance := INF
	# Fixed perimeter directions and outward rings account for conservative cell rasterization.
	for ring in range(3):
		var radius: float = tree.physical_radius + Geometry.RESIDENT_RADIUS + 0.5 + ring * navigation.CELL_SIZE
		for index in range(8):
			var offset := Vector2.from_angle(index * TAU / 8.0) * radius
			var point := center + Vector3(offset.x,0,offset.y)
			if not navigation.is_world_walkable(point) or navigation.find_path(from_world,point).is_empty(): continue
			var distance := from_world.distance_squared_to(point)
			if distance < best_distance:
				best_distance = distance
				best = Coordinates.to_sim(point)
	return best

func is_available(point: Vector2) -> bool:
	return navigation.is_world_walkable(Coordinates.to_world(point))
