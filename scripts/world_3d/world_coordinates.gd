extends RefCounted
## Main-world bridge. Simulation balance remains in its original units.
const SIM_UNITS_PER_WORLD_UNIT: float = 25.0
static func to_world(point: Vector2, height: float = 0.0) -> Vector3:
	var plane := point / SIM_UNITS_PER_WORLD_UNIT
	return from_plane(plane, height)
static func to_sim(point: Vector3) -> Vector2:
	return world_plane(point) * SIM_UNITS_PER_WORLD_UNIT
static func length_to_world(sim_length: float) -> float:
	return sim_length / SIM_UNITS_PER_WORLD_UNIT
static func world_plane(point: Vector3) -> Vector2: return Vector2(point.x, point.z)
static func from_plane(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x, height, point.y)
