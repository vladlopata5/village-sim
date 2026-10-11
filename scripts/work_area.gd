extends RefCounted
## Domain circle in simulation units. No workers or reservations.
signal changed
var id: StringName
var center: Vector2
var radius: float
var revision := 0
func _init(identity: StringName, point: Vector2, extent: float) -> void:
	id = identity
	center = point
	radius = extent
func contains(point: Vector2) -> bool:
	return point.is_finite() and point.distance_squared_to(center) <= radius * radius
func update(point: Vector2, extent: float) -> bool:
	if not point.is_finite() or not is_finite(extent) or extent <= 0: return false
	if center == point and radius == extent: return true
	center = point
	radius = extent
	revision += 1
	changed.emit()
	return true
