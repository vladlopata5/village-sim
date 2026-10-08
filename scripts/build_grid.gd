extends RefCounted
## Placement occupancy only. Navigation owns clearance/connectivity independently.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const CELL_SIZE: float = 0.5
const WORLD_BOUNDS := Rect2(-64, -40, 128, 80)
var bounds: Rect2
var _owners: Dictionary = {}
var _buildings: Dictionary = {}
func _init(world_bounds: Rect2 = WORLD_BOUNDS) -> void: bounds = world_bounds
func grid_size() -> Vector2i: return Vector2i(bounds.size / CELL_SIZE)
func world_to_cell(point: Vector3) -> Vector2i:
	var local := (Coordinates.world_plane(point) - bounds.position) / CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))
func cell_to_world(cell: Vector2i) -> Vector3:
	return Coordinates.from_plane(bounds.position + (Vector2(cell) + Vector2.ONE * 0.5) * CELL_SIZE)
func rotated_size(size: Vector2i, quarter_turns: int) -> Vector2i:
	return Vector2i(size.y, size.x) if posmod(quarter_turns, 2) == 1 else size
func snap(point: Vector3, size: Vector2i, quarter_turns: int = 0) -> Vector3:
	var extent := Vector2(rotated_size(size, quarter_turns))
	var low := (Coordinates.world_plane(point) - bounds.position) / CELL_SIZE - extent / 2.0
	return Coordinates.from_plane(bounds.position + (low.round() + extent / 2.0) * CELL_SIZE)
func footprint_cells(point: Vector3, size: Vector2i, quarter_turns: int = 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not point.is_finite() or size.x <= 0 or size.y <= 0: return cells
	var extent := Vector2(rotated_size(size, quarter_turns))
	var low := (Coordinates.world_plane(point) - bounds.position) / CELL_SIZE - extent / 2.0
	var high := low + extent
	# Starter centers stay unchanged; non-aligned footprints conservatively own touched cells.
	for y in range(floori(low.y + 0.00001), ceili(high.y - 0.00001)):
		for x in range(floori(low.x + 0.00001), ceili(high.x - 0.00001)):
			cells.append(Vector2i(x,y))
	return cells
func occupant(cell: Vector2i) -> StringName: return _owners.get(cell, &"")
func occupied_cells(id: StringName) -> Array: return _buildings.get(id, []).duplicate()
func validation_reason(cells: Array) -> String:
	if cells.is_empty(): return "Некорректная позиция или footprint"
	var region := Rect2i(Vector2i.ZERO, grid_size())
	for cell in cells:
		if not region.has_point(cell): return "За пределами карты"
		if not occupant(cell).is_empty(): return "Место занято зданием"
	return ""
func occupy(id: StringName, cells: Array) -> bool:
	if id.is_empty() or _buildings.has(id) or not validation_reason(cells).is_empty(): return false
	_buildings[id] = cells.duplicate()
	for cell in cells: _owners[cell] = id
	return true
func release(id: StringName) -> void:
	for cell in _buildings.get(id, []): _owners.erase(cell)
	_buildings.erase(id)
