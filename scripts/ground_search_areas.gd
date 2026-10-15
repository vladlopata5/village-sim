extends RefCounted
## Admission for NEW ground searches only. All positions/radii use simulation units.
const Balance = preload("res://scripts/balance_config.gd")
static func contains(point: Vector2, resident_position: Variant, workplace: RefCounted = null, area: RefCounted = null) -> bool:
	if not point.is_finite() or not resident_position is Vector2 or not resident_position.is_finite(): return false
	if point.distance_squared_to(resident_position) <= Balance.RESIDENT_GROUND_SEARCH_RADIUS ** 2: return true
	if workplace != null and workplace.position.is_finite() and point.distance_squared_to(workplace.position) <= workplace.definition.get_ground_search_radius() ** 2: return true
	return area != null and area.contains(point)
static func identity(resident_position: Variant, workplace: RefCounted = null, area: RefCounted = null) -> Array:
	return [resident_position, workplace.get_instance_id() if workplace != null else 0, workplace.position if workplace != null else null, workplace.definition.get_ground_search_radius() if workplace != null else 0, area.id if area != null else &"", area.revision if area != null else 0, area.center if area != null else null, area.radius if area != null else 0]
