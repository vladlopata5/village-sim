extends RefCounted
## World-owned geometry. ResidentData owns assignment references.
const Area = preload("res://scripts/work_area.gd")
signal changed
var _areas: Dictionary = {}
var _next_id := 1
func create(center: Vector2, radius: float) -> Area:
	if not center.is_finite() or not is_finite(radius) or radius <= 0: return null
	var area := Area.new(StringName("work_area_%04d" % _next_id),center,radius)
	_next_id += 1
	_areas[area.id] = area
	area.changed.connect(_on_changed)
	changed.emit()
	return area
func get_area(id: StringName) -> Area: return _areas.get(id)
func all() -> Array: return _areas.values()
func remove(id: StringName) -> bool:
	var area := get_area(id)
	if area == null: return false
	area.changed.disconnect(_on_changed)
	_areas.erase(id)
	changed.emit()
	return true
func _on_changed() -> void: changed.emit()
