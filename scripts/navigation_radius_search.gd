extends RefCounted
## One region-goal A* over NavigationGrid's live cells; no second grid/state.
const DIRECTIONS = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN,
	Vector2i(-1,-1), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1)]
var _open: Array[Dictionary] = []
func find_cells(grid: RefCounted, start: Vector2i, center: Vector3, radius: float, inner_radius: float) -> Array[Vector2i]:
	var goals: Dictionary = {}
	var low: Vector2i = grid.world_to_cell(center-Vector3(radius,0,radius))
	var high: Vector2i = grid.world_to_cell(center+Vector3(radius,0,radius))
	for y in range(maxi(0,low.y),mini(grid.grid_size().y,high.y+1)):
		for x in range(maxi(0,low.x),mini(grid.grid_size().x,high.x+1)):
			var cell := Vector2i(x,y)
			var distance: float = grid.cell_to_world(cell).distance_to(center)
			if distance <= radius and distance >= inner_radius and grid.is_cell_walkable(cell): goals[cell] = true
	if goals.is_empty(): return []
	var costs: Dictionary = {start:0.0}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	_open.clear()
	_push({"cell":start,"cost":0.0,"score":_estimate(grid,start,center,radius)})
	while not _open.is_empty():
		var current := _pop()
		var cell: Vector2i = current.cell
		if closed.has(cell): continue
		closed[cell] = true
		if goals.has(cell):
			var path: Array[Vector2i] = [cell]
			while parents.has(cell):
				cell = parents[cell]
				path.append(cell)
			path.reverse()
			return path
		for direction in DIRECTIONS:
			var next: Vector2i = cell+direction
			if closed.has(next) or not grid.is_cell_walkable(next): continue
			if direction.x != 0 and direction.y != 0:
				if not grid.is_cell_walkable(cell+Vector2i(direction.x,0)) or not grid.is_cell_walkable(cell+Vector2i(0,direction.y)): continue
			# Same entry-cell normalized costs as ordinary AStarGrid2D.
			var step := sqrt(2.0) if direction.x != 0 and direction.y != 0 else 1.0
			var cost: float = current.cost+step*grid.get_cell_traversal_cost(next)
			if cost >= costs.get(next,INF): continue
			costs[next] = cost
			parents[next] = cell
			_push({"cell":next,"cost":cost,"score":cost+_estimate(grid,next,center,radius)})
	return []
func _estimate(grid: RefCounted, cell: Vector2i, center: Vector3, radius: float) -> float:
	# Euclidean distance to the disk is a lower bound: normalized weights >= 1.
	return maxf(grid.cell_to_world(cell).distance_to(center)-radius,0.0)/grid.CELL_SIZE
func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.score != b.score: return a.score < b.score
	if a.cell.y != b.cell.y: return a.cell.y < b.cell.y
	return a.cell.x < b.cell.x
func _push(entry: Dictionary) -> void:
	_open.append(entry)
	var index := _open.size()-1
	while index > 0:
		var parent := int((index-1)/2.0)
		if not _before(_open[index],_open[parent]): break
		var swap := _open[parent]
		_open[parent] = _open[index]
		_open[index] = swap
		index = parent
func _pop() -> Dictionary:
	var result := _open[0]
	var last: Dictionary = _open.pop_back()
	if _open.is_empty(): return result
	_open[0] = last
	var index := 0
	while index*2+1 < _open.size():
		var child := index*2+1
		if child+1 < _open.size() and _before(_open[child+1],_open[child]): child += 1
		if not _before(_open[child],_open[index]): break
		var swap := _open[index]
		_open[index] = _open[child]
		_open[child] = swap
		index = child
	return result
