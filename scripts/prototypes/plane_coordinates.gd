extends RefCounted
## Local slice convention only: simulation XY maps to world XZ, one unit to one unit.
static func to_world(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x, height, point.y)
static func to_sim(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
static func on_ground(point: Vector3) -> Vector3:
	return to_world(to_sim(point))
