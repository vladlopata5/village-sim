extends RefCounted
## Authoritative world road cells, independent of player tools and navigation weights.
const Grid = preload("res://scripts/build_grid.gd")
const CELL_SIZE := Grid.CELL_SIZE
const WORLD_BOUNDS := Grid.WORLD_BOUNDS
signal changed
var geometry: RefCounted
var _roads: Dictionary = {}
func _init(bounds: Rect2 = WORLD_BOUNDS) -> void: geometry = Grid.new(bounds)
func contains(cell: Vector2i) -> bool: return _roads.has(cell)
func in_bounds(cell: Vector2i) -> bool: return Rect2i(Vector2i.ZERO,geometry.grid_size()).has_point(cell)
func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_roads.keys())
	result.sort_custom(func(a,b): return a.y<b.y or (a.y==b.y and a.x<b.x))
	return result
func add_road(cell: Vector2i) -> bool: return edit([cell],false)
func remove_road(cell: Vector2i) -> bool: return edit([cell],true)
func edit(points: Array, erase: bool) -> bool:
	var modified := false
	for cell in points:
		if not in_bounds(cell): continue
		if erase:
			if _roads.erase(cell): modified=true
		elif not contains(cell):
			_roads[cell]=true
			modified=true
	if modified: changed.emit()
	return modified
