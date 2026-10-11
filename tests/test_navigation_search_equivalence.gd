extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Search = preload("res://scripts/navigation_radius_search.gd")
const Reference = preload("res://tests/navigation_radius_reference.gd")
# Independent zero-heuristic cost oracle using the frozen old implementation.
class Dijkstra extends Reference:
	func _estimate(_grid: RefCounted, _cell: Vector2i, _center: Vector3, _radius: float) -> float: return 0.0
var checks := 0
var failures := 0
var search = Search.new() # Reuse intentionally to detect leaked heap/query state.
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func cost(grid: RefCounted, path: Array[Vector2i]) -> float:
	if path.is_empty(): return INF
	var result := 0.0
	for i in range(1,path.size()):
		var d := path[i]-path[i-1]
		result += (sqrt(2.0) if d.x != 0 and d.y != 0 else 1.0) * grid.get_cell_traversal_cost(path[i])
	return result
func valid(grid: RefCounted, path: Array[Vector2i], center: Vector3, radius: float, inner: float) -> bool:
	if path.is_empty(): return true
	var distance: float = grid.cell_to_world(path[-1]).distance_to(center)
	if distance > radius+0.000001 or distance < inner-0.000001: return false
	for i in range(path.size()):
		if not grid.is_cell_walkable(path[i]): return false
		if i == 0: continue
		var d := path[i]-path[i-1]
		if absi(d.x)>1 or absi(d.y)>1 or d==Vector2i.ZERO: return false
		if d.x and d.y:
			if not grid.is_cell_walkable(path[i-1]+Vector2i(d.x,0)) or not grid.is_cell_walkable(path[i-1]+Vector2i(0,d.y)): return false
	return true
func compare(label: String, grid: RefCounted, start: Vector2i, center: Vector3, radius: float = 0.4, inner: float = 0.0) -> void:
	var old: Array[Vector2i] = Reference.new().find_cells(grid,start,center,radius,inner)
	var current: Array[Vector2i] = search.find_cells(grid,start,center,radius,inner)
	var oracle: Array[Vector2i] = Dijkstra.new().find_cells(grid,start,center,radius,inner)
	check(current.is_empty()==old.is_empty() and current.is_empty()==oracle.is_empty(),label+": reachability matches")
	check(valid(grid,current,center,radius,inner),label+": walkable goals, adjacent steps and no corner cutting")
	if not current.is_empty():
		check(absf(cost(grid,current)-cost(grid,old))<0.000001,label+": old/new cost matches")
		check(absf(cost(grid,current)-cost(grid,oracle))<0.000001,label+": optimal discrete entry-cell cost")
		check(search.find_cells(grid,start,center,radius,inner)==current,label+": deterministic ties/repeated query")
	# For one-cell goals also check the unchanged native point backend against Dijkstra.
	if radius < Grid.CELL_SIZE*0.5:
		var points: PackedVector3Array = grid.find_raw_path(grid.cell_to_world(start),center)
		var cells: Array[Vector2i] = []
		for point in points: cells.append(grid.world_to_cell(point))
		check(cells.is_empty()==oracle.is_empty(),label+": native point reachability")
		if not cells.is_empty(): check(absf(cost(grid,cells)-cost(grid,oracle))<0.000001,label+": native point optimal cost")
func caches_match(grid: RefCounted) -> bool:
	for y in range(grid.grid_size().y):
		for x in range(grid.grid_size().x):
			var cell := Vector2i(x,y)
			var id: int = y*grid.grid_size().x+x
			if bool(grid._search_solids[id]) == grid.is_cell_walkable(cell): return false
			var expected: float = grid._fastest_speed/grid._resolve_cell_speed(cell)
			if grid._search_costs[id] != expected or grid._backend.get_point_weight_scale(cell)!=expected: return false
	return true
func _initialize() -> void:
	var grid = Grid.new(Rect2(0,0,12,8),0.0)
	var a := Vector2i(1,7)
	var b := grid.cell_to_world(Vector2i(21,7))
	compare("straight",grid,a,b,0.2)
	compare("long diagonal",grid,Vector2i(0,0),grid.cell_to_world(Vector2i(23,15)),0.2)
	compare("equal-cost alternatives",grid,a,grid.cell_to_world(Vector2i(20,10)))
	compare("already in region",grid,a,grid.cell_to_world(a),1.0)
	grid.add_blocker(&"box",Rect2(4,2,2,4))
	compare("single obstacle",grid,a,b,0.2)
	compare("blocked center reachable annulus",grid,a,Vector3(5,0,4),2.0,1.0)
	grid.add_blocker(&"top",Rect2(4,0,2,1.5))
	grid.add_blocker(&"bottom",Rect2(4,2,2,6))
	compare("narrow passage",grid,a,b,0.2)
	grid.remove_blocker(&"box")
	grid.remove_blocker(&"top")
	grid.remove_blocker(&"bottom")
	grid.set_traversal_modifier(&"forest",Rect2(4,1,3,6),0.2)
	compare("weighted alternatives",grid,a,b,0.2)
	grid.set_traversal_modifier(&"road",Rect2(0,0.5,12,0.5),1.25)
	compare("road speedup",grid,a,b,0.2)
	check(caches_match(grid),"Dense costs and solids agree with live sources/backend including global normalization")
	grid.set_traversal_modifier(&"forest",Rect2(4,1,3,6),0.8)
	compare("dynamic cost",grid,a,b,0.2)
	grid.remove_traversal_modifier(&"road")
	check(caches_match(grid),"Removing fastest source updates every normalized weight")
	compare("road removed",grid,a,b,0.2)
	grid.add_blocker(&"wall",Rect2(6,0,0.5,8))
	compare("unreachable point",grid,a,b,0.2)
	compare("unreachable region",grid,a,b,1.0)
	grid.add_blocker(&"overlap",Rect2(6,0,0.5,8))
	grid.remove_blocker(&"wall")
	compare("remaining overlap",grid,a,b,0.2)
	grid.remove_blocker(&"overlap")
	compare("obstacle removed",grid,a,b,0.2)
	check(caches_match(grid),"Blocker add/remove retains authoritative derived data")
	var corner = Grid.new(Rect2(0,0,2,2),0.0)
	corner.add_blocker(&"right",Rect2(0.5,0,0.5,0.5))
	corner.add_blocker(&"down",Rect2(0,0.5,0.5,0.5))
	compare("corner cutting",corner,Vector2i.ZERO,Vector3(1.25,0,1.25),0.2)
	var cover = Grid.new(Rect2(0,0,2,2),0.0)
	cover.add_blocker(&"cover",Rect2(0.5,0,1.5,2))
	cover.add_blocker(&"cover_left",Rect2(0,0.5,0.5,1.5))
	compare("no walkable goals",cover,Vector2i.ZERO,Vector3(1.25,0,1.25),0.2)
	cover.add_blocker(&"all",cover.bounds)
	check(cover.find_path(Vector3(0.25,0,0.25),Vector3(1.25,0,1.25)).is_empty() and cover.find_path_to_radius(Vector3(0.25,0,0.25),Vector3(1.25,0,1.25),1).is_empty(),"Fully blocked world fails safely")
	check(grid.find_path(Vector3(-1,0,0),b).is_empty(),"Out of bounds still unavailable")
	var full = Grid.new()
	full.set_traversal_modifier(&"wide_forest",Rect2(-10,-20,15,40),0.3)
	compare("full 256x160 world long weighted region",full,full.world_to_cell(Vector3(-50.25,0,-25.25)),Vector3(50.25,0,25.25),2.25,0.75)
	# Small seeded maps exercise decrease-key and alternative weighted routes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4072
	for sample in range(8):
		var mixed = Grid.new(Rect2(0,0,6,5),0.0)
		for i in range(18):
			var cell := Vector2i(rng.randi_range(1,10),rng.randi_range(0,8))
			var area := Rect2(Vector2(cell)*Grid.CELL_SIZE,Vector2.ONE*Grid.CELL_SIZE)
			if i % 3 == 0: mixed.add_blocker(StringName("block%d"%i),area)
			else: mixed.set_traversal_modifier(StringName("cost%d"%i),area,1.25 if i % 2 == 0 else 0.25)
		compare("seeded weighted map %d"%sample,mixed,Vector2i.ZERO,mixed.cell_to_world(Vector2i(11,9)),0.2)
		check(caches_match(mixed),"Seeded live data agrees with backend")
	print("Navigation search equivalence: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
