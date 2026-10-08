extends RefCounted
## Authoritative X/Z connectivity. Backend and cell IDs stay behind this service.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const CELL_SIZE: float = 0.5
const WORLD_BOUNDS := Rect2(-64, -40, 128, 80)
signal changed(revision: int)
var bounds: Rect2
var clearance: float
var revision := 0
var _backend := AStarGrid2D.new()
var _blockers: Dictionary = {} # Stable blocker ID -> occupied navigation cells.
var _counts: Dictionary = {} # Cell -> number of independent obstacle owners.
func _init(world_bounds: Rect2 = WORLD_BOUNDS, resident_radius: float = Geometry.RESIDENT_RADIUS) -> void:
	bounds = world_bounds
	clearance = resident_radius
	_backend.region = Rect2i(Vector2i.ZERO, Vector2i(ceili(bounds.size.x / CELL_SIZE), ceili(bounds.size.y / CELL_SIZE)))
	_backend.cell_size = Vector2.ONE * CELL_SIZE
	_backend.offset = bounds.position + Vector2.ONE * CELL_SIZE / 2.0
	_backend.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_backend.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_backend.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_backend.jumping_enabled = false
	_backend.update() # Only initialization; blocker edits do not call update().
	for cell in _all_cells():
		_backend.set_point_solid(cell, _outside_clearance(cell))
func grid_size() -> Vector2i: return _backend.region.size
func world_to_cell(point: Vector3) -> Vector2i:
	var local := (Coordinates.world_plane(point) - bounds.position) / CELL_SIZE
	return Vector2i(floori(local.x), floori(local.y))
func cell_to_world(cell: Vector2i, height: float = 0.0) -> Vector3:
	return Coordinates.from_plane(bounds.position + (Vector2(cell) + Vector2.ONE * 0.5) * CELL_SIZE, height)
func _outside_clearance(cell: Vector2i) -> bool:
	var low := Coordinates.world_plane(cell_to_world(cell)) - Vector2.ONE * CELL_SIZE / 2.0
	var high := low + Vector2.ONE * CELL_SIZE
	return low.x < bounds.position.x + clearance or low.y < bounds.position.y + clearance or high.x > bounds.end.x - clearance or high.y > bounds.end.y - clearance
func is_cell_walkable(cell: Vector2i) -> bool:
	return _backend.is_in_boundsv(cell) and not _backend.is_point_solid(cell)
func is_world_walkable(point: Vector3) -> bool:
	if not point.is_finite() or not bounds.has_point(Coordinates.world_plane(point)): return false
	var cell := world_to_cell(point)
	if not is_cell_walkable(cell): return false
	# A point exactly on a cell edge/corner must also clear the cells it touches.
	var local := (Coordinates.world_plane(point) - bounds.position) / CELL_SIZE
	var on_x := absf(local.x - roundf(local.x)) < 0.00001
	var on_y := absf(local.y - roundf(local.y)) < 0.00001
	if on_x and not is_cell_walkable(cell + Vector2i.LEFT): return false
	if on_y and not is_cell_walkable(cell + Vector2i.UP): return false
	return not (on_x and on_y) or is_cell_walkable(cell + Vector2i(-1,-1))
func add_blocker(id: StringName, occupied_area: Rect2) -> void:
	_remove_cells(id)
	var cells: Array[Vector2i] = []
	if occupied_area.has_area():
		var area := occupied_area.grow(clearance) # Never alters the physical footprint.
		var first := world_to_cell(Coordinates.from_plane(area.position))
		var end := (area.end - bounds.position) / CELL_SIZE
		var last := Vector2i(ceili(end.x), ceili(end.y))
		for y in range(maxi(0,first.y), mini(grid_size().y,last.y)):
			for x in range(maxi(0,first.x), mini(grid_size().x,last.x)):
				var cell := Vector2i(x,y)
				cells.append(cell)
				_counts[cell] = _counts.get(cell, 0) + 1
				_backend.set_point_solid(cell, true)
	_blockers[id] = cells
	_publish_change()
func remove_blocker(id: StringName) -> void:
	if not _blockers.has(id): return
	_remove_cells(id)
	_publish_change()
func _remove_cells(id: StringName) -> void:
	for cell in _blockers.get(id, []):
		var count: int = _counts[cell] - 1
		if count == 0: _counts.erase(cell)
		else: _counts[cell] = count
		_backend.set_point_solid(cell, count > 0 or _outside_clearance(cell))
	_blockers.erase(id)
func _publish_change() -> void:
	revision += 1
	changed.emit(revision)
func _all_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(grid_size().y):
		for x in range(grid_size().x): cells.append(Vector2i(x,y))
	return cells
func blocked_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _all_cells():
		if not is_cell_walkable(cell): result.append(cell)
	return result
func has_line_of_sight(start: Vector3, target: Vector3) -> bool:
	if not is_world_walkable(start) or not is_world_walkable(target): return false
	var a := (Coordinates.world_plane(start) - bounds.position) / CELL_SIZE
	var b := (Coordinates.world_plane(target) - bounds.position) / CELL_SIZE
	var direction := b - a
	var cell := world_to_cell(start)
	var goal := world_to_cell(target)
	var step := Vector2i(int(signf(direction.x)), int(signf(direction.y)))
	var delta_x := absf(1.0 / direction.x) if direction.x != 0 else INF
	var delta_y := absf(1.0 / direction.y) if direction.y != 0 else INF
	var edge_x := float(cell.x + 1) if step.x > 0 else float(cell.x)
	var edge_y := float(cell.y + 1) if step.y > 0 else float(cell.y)
	var next_x := (edge_x - a.x) / direction.x if direction.x != 0 else INF
	var next_y := (edge_y - a.y) / direction.y if direction.y != 0 else INF
	var vertical_edge := direction.x == 0 and absf(a.x - roundf(a.x)) < 0.00001
	var horizontal_edge := direction.y == 0 and absf(a.y - roundf(a.y)) < 0.00001
	while cell != goal:
		if absf(next_x-next_y) < 0.00001:
			if not is_cell_walkable(cell+Vector2i(step.x,0)) or not is_cell_walkable(cell+Vector2i(0,step.y)): return false
			cell += step
			next_x += delta_x
			next_y += delta_y
		elif next_x < next_y:
			cell.x += step.x
			next_x += delta_x
		else:
			cell.y += step.y
			next_y += delta_y
		if not is_cell_walkable(cell): return false
		if vertical_edge and not is_cell_walkable(cell+Vector2i.LEFT): return false
		if horizontal_edge and not is_cell_walkable(cell+Vector2i.UP): return false
	return true
func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not is_world_walkable(start) or not is_world_walkable(target): return result
	var ids: Array[Vector2i] = _backend.get_id_path(world_to_cell(start), world_to_cell(target), false)
	if ids.is_empty(): return result
	_append_point(result, start)
	for cell in ids: _append_point(result, cell_to_world(cell))
	_append_point(result, target)
	return result
func _append_point(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or points[-1].distance_to(point) > 0.00001: points.append(point)
func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	if raw.is_empty(): return result
	result.append(raw[0])
	var anchor := 0
	while anchor < raw.size()-1:
		var next := raw.size()-1
		while next > anchor+1 and not has_line_of_sight(raw[anchor],raw[next]): next -= 1
		if not has_line_of_sight(raw[anchor],raw[next]): return PackedVector3Array()
		result.append(raw[next])
		anchor = next
	return result
func find_path(start: Vector3, target: Vector3) -> PackedVector3Array:
	return smooth_path(find_raw_path(start,target))
