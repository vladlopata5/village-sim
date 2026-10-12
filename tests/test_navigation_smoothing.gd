extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
class Counted extends "res://scripts/navigation_grid.gd":
	var raw_calls := 0
	var smooth_calls := 0
	var los_calls := 0
	func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
		raw_calls += 1
		return super.find_raw_path(start,target)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls += 1
		return super.smooth_path(raw)
	func has_line_of_sight(start: Vector3, target: Vector3) -> bool:
		los_calls += 1
		return super.has_line_of_sight(start,target)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

# Independent closed-rectangle intersection (slab test), not the grid's DDA LOS.
func intersects_cell(a: Vector2, b: Vector2, rectangle: Rect2) -> bool:
	var low := 0.0
	var high := 1.0
	var direction := b-a
	for axis in 2:
		if direction[axis] == 0.0:
			if a[axis] < rectangle.position[axis] or a[axis] > rectangle.end[axis]: return false
		else:
			var first: float = (rectangle.position[axis]-a[axis])/direction[axis]
			var last: float = (rectangle.end[axis]-a[axis])/direction[axis]
			low = maxf(low,minf(first,last))
			high = minf(high,maxf(first,last))
			if low > high: return false
	return true
func independent_clear(grid: RefCounted, path: PackedVector3Array) -> bool:
	var solids: Array = grid.blocked_cells()
	for index in range(1,path.size()):
		var a := Coordinates.world_plane(path[index-1])
		var b := Coordinates.world_plane(path[index])
		for cell in solids:
			var center := Coordinates.world_plane(grid.cell_to_world(cell))
			if intersects_cell(a,b,Rect2(center-Vector2.ONE*grid.CELL_SIZE/2.0,Vector2.ONE*grid.CELL_SIZE)): return false
	return true
func verify(grid: RefCounted, start: Vector3, target: Vector3, label: String) -> void:
	var raw: PackedVector3Array = grid.find_raw_path(start,target)
	var path: PackedVector3Array = grid.smooth_path(raw)
	check(not raw.is_empty() and not path.is_empty(),label+": reachable route retained")
	if path.is_empty(): return
	check(path[0] == start and path[-1] == target,label+": exact endpoints")
	check(independent_clear(grid,path),label+": independent solid-cell intersection")
	check(grid.last_smoothing_checks <= grid.SMOOTH_CHECK_BUDGET,label+": optional checks bounded")
	check(grid.path_travel_cost(path) <= grid.path_travel_cost(raw)+0.0001,label+": current terrain integral never worsens raw cost")
	for index in range(1,path.size()): check(path[index] != path[index-1],label+": no adjacent duplicates")
	var body := Node3D.new()
	root.add_child(body)
	var mover := Movement.new()
	body.add_child(mover)
	mover.body = body
	mover.navigation = grid
	mover.speed = 1000
	body.position = start
	mover.set_target(target)
	for tick in 20:
		mover.advance(0.1)
		if not mover.is_moving(): break
	check(not mover.is_moving() and body.position == target,label+": physical traversal arrives")
	body.free()
func run() -> void:
	var grid = Grid.new(Rect2(0,0,20,20),0.4)
	var start := Vector3(1.25,0,5.25)
	var target := Vector3(18.25,0,5.25)
	verify(grid,start,target,"Open ground")
	check(grid.find_path(start,target).size() == 2,"Open straight route remains direct")
	grid.add_blocker(&"building",Rect2(7,3,3,4))
	verify(grid,start,target,"One building with clearance")
	grid.add_blocker(&"second",Rect2(12,5,2,6))
	verify(grid,start,target,"Two buildings/right angle")
	grid.remove_blocker(&"building")
	verify(grid,start,target,"Dynamic removal")
	grid.remove_blocker(&"second")
	# Narrow but physically sufficient corridor, plus a rock-sized hard obstacle.
	grid.add_blocker(&"upper",Rect2(6,0,8,4))
	grid.add_blocker(&"lower",Rect2(6,6,8,14))
	verify(grid,start,target,"Narrow corridor")
	grid.add_blocker(&"rock",Rect2(8.5,4.8,0.5,0.5))
	check(grid.find_path(start,target).is_empty(),"Clearance closes an insufficient rock gap")
	grid.remove_blocker(&"rock")
	grid.remove_blocker(&"upper")
	grid.remove_blocker(&"lower")
	for index in 8: grid.set_traversal_modifier(StringName("tree%d"%index),Rect2(3+index*1.5,4,1,2),0.2)
	verify(grid,start,target,"Existing soft forest terrain")
	check(grid.path_travel_cost(grid.find_path(start,target)) < grid.segment_travel_cost(start,target),"No shortcut through expensive forest")
	for index in 8: grid.remove_traversal_modifier(StringName("tree%d"%index))
	grid.set_traversal_modifier(&"road",Rect2(1,2.5,18,0.5),1.25)
	verify(grid,start,target,"Road detour")
	check(grid.path_travel_cost(grid.find_path(start,target)) < start.distance_to(target),"Road time benefit retained")
	grid.remove_traversal_modifier(&"road")
	var building = preload("res://scripts/building_instance.gd").new(&"rotated",preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.FOOD),Coordinates.to_sim(Vector3(10,0,5)))
	for rotation in 4:
		building.quarter_turns = rotation
		grid.add_blocker(building.id,preload("res://scripts/world_3d/world_geometry.gd").footprint(building))
		verify(grid,start,target,"Building orientation %d" % rotation)
	grid.remove_blocker(building.id)
	var short_path := PackedVector3Array([start,start,Vector3(1.5,0,5.25),target,target])
	var compact: PackedVector3Array = grid.smooth_path(short_path)
	check(compact == PackedVector3Array([start,target]),"Exact collinear points/duplicates compact without new geometry")
	check(grid.smooth_path(PackedVector3Array([start])) == PackedVector3Array([start]),"One-point arrival")
	check(grid.smooth_path(PackedVector3Array()).is_empty(),"Empty route")
	verify(grid,start,Vector3(1.250001,0,5.25),"Very close endpoint")
	grid.add_blocker(&"invalid_raw",Rect2(3,4,2,2))
	check(grid.smooth_path(PackedVector3Array([start,target])).is_empty(),"Invalid raw edge fails safely, even without shortening")
	grid.remove_blocker(&"invalid_raw")
	verify(grid,Vector3(0.75,0,0.75),Vector3(19.25,0,19.25),"Grid boundary")
	var corner = Grid.new(Rect2(0,0,3,3),0)
	corner.add_blocker(&"edge",Rect2(0.5,0,0.5,0.5))
	verify(corner,Vector3(0.25,0,0.25),Vector3(1.25,0,1.25),"Single blocked diagonal neighbor")
	check(corner.smooth_path(PackedVector3Array([Vector3(0.25,0,0.25),Vector3(0.75,0,0.75)])).is_empty(),"No unsafe diagonal raw fallback")
	# Hard tree/rock obstacles are respected independently of their gameplay policy.
	var forest = Grid.new(Rect2(0,0,20,20),0.4)
	for x in [5.0,8.0,11.0,14.0]:
		for z in [3.0,6.0,9.0,12.0]: forest.add_blocker(StringName("hard_%s_%s"%[x,z]),Rect2(x,z,0.6,0.6))
	verify(forest,Vector3(1.25,0,7.25),Vector3(18.25,0,7.25),"Hard forest/rocks")
	# Alternating tall walls produce enough real turns to exhaust optional work.
	var maze = Grid.new(Rect2(0,0,80,40),0)
	for index in 26:
		maze.add_blocker(StringName("wall%d"%index),Rect2(2+index*2.5,0 if index%2==0 else 2,0.5,38))
	var maze_start := Vector3(0.75,0,0.75)
	var maze_target := Vector3(78.25,0,38.25)
	var maze_raw: PackedVector3Array = maze.find_raw_path(maze_start,maze_target)
	var maze_path: PackedVector3Array = maze.smooth_path(maze_raw)
	check(maze.last_smoothing_used_raw_tail and maze.last_smoothing_checks == Grid.SMOOTH_CHECK_BUDGET,"Long maze really exhausts deterministic budget")
	check(not maze_path.is_empty() and maze_path[-1] == maze_target,"Budget exhaustion preserves reachable exact destination")
	check(independent_clear(maze,maze_path),"Budget fallback tail independently clears every blocked cell")
	verify(maze,maze_start,maze_target,"Very long obstacle route/fallback")
	# No new planning while a resident follows an unchanged path, including pauses.
	var counted = Counted.new(Rect2(0,0,20,20),0.4)
	var body := Node3D.new()
	root.add_child(body)
	var mover := Movement.new()
	body.add_child(mover)
	mover.body = body
	mover.navigation = counted
	body.position = start
	mover.set_target(target)
	for tick in 100: mover.advance(0.001)
	check(counted.raw_calls == 1 and counted.smooth_calls == 1,"Existing movement has no repeated search/smoothing")
	for tick in 100: mover.advance(0)
	check(counted.smooth_calls == 1,"Zero elapsed movement does not repeat planning")
	counted.add_blocker(&"live",Rect2(7,3,3,4))
	mover.advance(0)
	check(counted.smooth_calls == 2 and independent_clear(counted,mover.current_path()),"Revision change replans once safely")
	counted.remove_blocker(&"live")
	mover.advance(0)
	check(counted.smooth_calls == 3,"Removal replans once")
	mover.stop()
	mover.advance(1000)
	check(counted.smooth_calls == 3 and not mover.is_moving(),"Cancellation stays stopped")
	body.free()
	print("Navigation smoothing: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
