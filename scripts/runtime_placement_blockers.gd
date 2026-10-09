extends RefCounted
## Live world-position providers and circular X/Z bounds; no grid/navigation ownership.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var _circles: Dictionary = {}
func register_circle(id: StringName, position_provider: Callable, radius: float) -> bool:
	# Registration opts into blocking placement. One stable ID per world entity.
	if id.is_empty() or _circles.has(id) or not position_provider.is_valid() or not is_finite(radius) or radius <= 0.0: return false
	_circles[id] = {"position":position_provider, "radius":radius}
	return true
func unregister(id: StringName) -> void: _circles.erase(id)
func has_blocker(id: StringName) -> bool: return _circles.has(id)
func first_overlap(footprint: Rect2) -> StringName:
	if not footprint.has_area(): return &""
	var ids: Array = _circles.keys()
	ids.sort_custom(func(a, b): return String(a) < String(b)) # Explicit lexical order for StringName IDs.
	for id in ids:
		var circle: Dictionary = _circles[id]
		var provider: Callable = circle.position
		if not provider.is_valid():
			unregister(id) # Safe stale-provider cleanup, even without a lifecycle notification.
			continue
		var point: Variant = provider.call()
		if not point is Vector3 or not point.is_finite(): continue
		var center := Coordinates.world_plane(point)
		var closest := center.clamp(footprint.position, footprint.end)
		if center.distance_squared_to(closest) <= circle.radius * circle.radius: return id
	return &""
