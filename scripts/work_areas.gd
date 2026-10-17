extends RefCounted
## World-owned geometry. ResidentData owns assignment references.
const Area = preload("res://scripts/work_area.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Balance = preload("res://scripts/balance_config.gd")
signal changed
signal presentation_changed
var _areas: Dictionary = {}
var _next_id := 1
func create(center: Vector2, radius: float) -> Area:
	if not valid_geometry(center,radius): return null
	var area := Area.new(StringName("work_area_%04d" % _next_id),center,radius)
	area.rename("Область %d" % _next_id)
	_next_id += 1
	_areas[area.id] = area
	area.changed.connect(_on_changed)
	area.presentation_changed.connect(_on_presentation_changed)
	changed.emit()
	return area
func get_area(id: StringName) -> Area: return _areas.get(id)
func all() -> Array: return _areas.values()
func valid_geometry(center: Vector2, radius: float) -> bool:
	return center.is_finite() and is_finite(radius) and radius > 0 and radius <= Coordinates.length_to_sim(Balance.MAX_WORK_AREA_RADIUS)
func update_area(id: StringName, center: Vector2, radius: float) -> bool:
	var area := get_area(id)
	return area != null and valid_geometry(center,radius) and area.update(center,radius)
func remove(id: StringName) -> bool:
	var area := get_area(id)
	if area == null: return false
	area.changed.disconnect(_on_changed)
	area.presentation_changed.disconnect(_on_presentation_changed)
	_areas.erase(id)
	changed.emit()
	return true
func _on_changed() -> void: changed.emit()
func _on_presentation_changed() -> void: presentation_changed.emit()
