extends RefCounted
## Region-goal A* over the same live NavigationGrid data as point navigation.
## Dense query-local arrays and an indexed binary heap: one entry per open cell.
const DIRECTIONS = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN,
	Vector2i(-1,-1), Vector2i(1,-1), Vector2i(1,1), Vector2i(-1,1)]
const DIAGONAL_COST := 1.4142135623730951
var _open: Array[int] = []
var _positions := PackedInt32Array()
var _scores := PackedFloat64Array()

func find_cells(grid: RefCounted, start: Vector2i, center: Vector3, radius: float, inner_radius: float) -> Array[Vector2i]:
	var size: Vector2i = grid.grid_size()
	var width := size.x
	var count := width * size.y
	# Packed arrays share storage without copying while this synchronous search reads.
	var solids: PackedByteArray = grid._search_solids
	var weights: PackedFloat64Array = grid._search_costs
	var goals := PackedByteArray()
	goals.resize(count)
	var low: Vector2i = grid.world_to_cell(center-Vector3(radius,0,radius))
	var high: Vector2i = grid.world_to_cell(center+Vector3(radius,0,radius))
	var has_goal := false
	for y in range(maxi(0,low.y),mini(size.y,high.y+1)):
		for x in range(maxi(0,low.x),mini(width,high.x+1)):
			var id := y * width + x
			var distance: float = grid.cell_to_world(Vector2i(x,y)).distance_to(center)
			if distance <= radius and distance >= inner_radius and not solids[id]:
				goals[id] = 1
				has_goal = true
	if not has_goal: return []
	var costs := PackedFloat64Array()
	costs.resize(count)
	costs.fill(INF)
	var parents := PackedInt32Array()
	parents.resize(count)
	parents.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	_positions.resize(count)
	_positions.fill(-1)
	_scores.resize(count)
	_open.clear()
	var first := start.y * width + start.x
	costs[first] = 0.0
	# Same Euclidean lower bound, expressed in cell units once instead of repeated
	# world conversions. Entry weights are normalized >= 1 by NavigationGrid.
	var center_cell: Vector2 = (Vector2(center.x,center.z)-grid.bounds.position)/grid.CELL_SIZE-Vector2.ONE*0.5
	var cell_radius: float = radius/grid.CELL_SIZE
	_scores[first] = maxf(Vector2(start).distance_to(center_cell)-cell_radius,0.0)
	_push(first)
	while not _open.is_empty():
		var current := _pop()
		closed[current] = 1
		if goals[current]:
			var path: Array[Vector2i] = []
			while current != -1:
				path.append(Vector2i(current % width, int(float(current) / width)))
				current = parents[current]
			path.reverse()
			return path
		var x := current % width
		var y := int(float(current) / width)
		for direction: Vector2i in DIRECTIONS:
			var nx: int = x + direction.x
			var ny: int = y + direction.y
			if nx < 0 or ny < 0 or nx >= width or ny >= size.y: continue
			var next := ny * width + nx
			if closed[next] or solids[next]: continue
			var diagonal: bool = direction.x != 0 and direction.y != 0
			if diagonal and (solids[y*width+nx] or solids[ny*width+x]): continue
			var cost: float = costs[current] + (DIAGONAL_COST if diagonal else 1.0) * weights[next]
			if cost >= costs[next]: continue
			costs[next] = cost
			parents[next] = current
			_scores[next] = cost + maxf(Vector2(nx,ny).distance_to(center_cell)-cell_radius,0.0)
			_push(next) # Existing cell: decrease-key, never a lazy duplicate.
	return []

func _push(cell: int) -> void:
	var index := _positions[cell]
	if index == -1:
		index = _open.size()
		_open.append(cell)
	var score := _scores[cell]
	while index > 0:
		var parent := (index-1) >> 1
		var other := _open[parent]
		if score > _scores[other] or (score == _scores[other] and cell >= other): break
		_open[index] = other
		_positions[other] = index
		index = parent
	_open[index] = cell
	_positions[cell] = index

func _pop() -> int:
	var result := _open[0]
	var last: int = _open.pop_back()
	_positions[result] = -1
	if _open.is_empty(): return result
	var index := 0
	var score := _scores[last]
	var length := _open.size()
	while index*2+1 < length:
		var child := index*2+1
		var other := _open[child]
		if child+1 < length:
			var right := _open[child+1]
			if _scores[right] < _scores[other] or (_scores[right] == _scores[other] and right < other):
				child += 1
				other = right
		if score < _scores[other] or (score == _scores[other] and last <= other): break
		_open[index] = other
		_positions[other] = index
		index = child
	_open[index] = last
	_positions[last] = index
	return result
