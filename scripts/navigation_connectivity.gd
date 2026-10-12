extends RefCounted
## Derived connectivity index owned by one NavigationGrid; never owns obstacles.
## Cardinal flood is exact only while allowed diagonals also have cardinal routes
## (both adjacent cells walkable). Directed/height transitions need a new model.
var generation := -1
var _labels := PackedInt32Array()
var _queue := PackedInt32Array()

func ensure(grid: RefCounted) -> void:
	if generation != grid.topology_generation: _rebuild(grid)

func _rebuild(grid: RefCounted) -> void:
	var size: Vector2i = grid.grid_size()
	var width := size.x
	var count := width * size.y
	var solids: PackedByteArray = grid._search_solids
	_labels.resize(count)
	_labels.fill(-1)
	_queue.resize(count)
	var directions: Array[int] = [-1, 1, -width, width]
	var component := 0
	for first in range(count):
		if solids[first] or _labels[first] != -1: continue
		var head := 0
		var tail := 1
		_queue[0] = first
		_labels[first] = component
		while head < tail:
			var cell := _queue[head]
			head += 1
			var x := cell % width
			for direction_index in range(4):
				if (direction_index == 0 and x == 0) or (direction_index == 1 and x == width-1): continue
				var direction := directions[direction_index]
				var next := cell + direction
				if next < 0 or next >= count or solids[next] or _labels[next] != -1: continue
				_labels[next] = component
				_queue[tail] = next
				tail += 1
		component += 1
	generation = grid.topology_generation # Publish only a complete index.

func can_reach_radius(grid: RefCounted, start: Vector2i, center: Vector3, radius: float, inner_radius: float) -> bool:
	ensure(grid)
	var size: Vector2i = grid.grid_size()
	var owner := _labels[start.y * size.x + start.x]
	if owner < 0: return false
	var low: Vector2i = grid.world_to_cell(center - Vector3(radius,0,radius))
	var high: Vector2i = grid.world_to_cell(center + Vector3(radius,0,radius))
	for y in range(maxi(0,low.y),mini(size.y,high.y+1)):
		for x in range(maxi(0,low.x),mini(size.x,high.x+1)):
			if _labels[y * size.x + x] != owner: continue
			# Match NavigationRadiusSearch cell-center annulus exactly, not its square.
			var distance: float = grid.cell_to_world(Vector2i(x,y)).distance_to(center)
			if distance <= radius and distance >= inner_radius: return true
	return false

func can_reach_point(grid: RefCounted, start: Vector2i, target: Vector2i) -> bool:
	ensure(grid)
	var width: int = grid.grid_size().x
	var owner := _labels[start.y*width+start.x]
	return owner>=0 and owner==_labels[target.y*width+target.x]
