extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Connectivity = preload("res://scripts/navigation_connectivity.gd")
const Search = preload("res://scripts/navigation_radius_search.gd")
var checks := 0
var failures := 0
class CountedConnectivity extends Connectivity:
	var builds := 0
	func _rebuild(grid: RefCounted) -> void:
		builds += 1
		super._rebuild(grid)
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func grid(bounds: Rect2 = Rect2(0,0,8,8)) -> RefCounted:
	var result = Grid.new(bounds,0.0)
	result._connectivity = CountedConnectivity.new()
	return result
func reachable(map: RefCounted, start: Vector3, target: Vector3, radius: float = 0.1, inner: float = 0.0) -> bool:
	return not map.find_path_to_radius(start,target,radius,inner).is_empty()
func original(map: RefCounted,start: Vector3,center: Vector3,radius: float,inner: float) -> PackedVector3Array:
	var cells: Array[Vector2i] = Search.new().find_cells(map,map.world_to_cell(start),center,radius,inner)
	if cells.is_empty(): return PackedVector3Array()
	var raw := PackedVector3Array([start])
	for cell in cells: map._append_point(raw,map.cell_to_world(cell,start.y))
	return map.smooth_path(raw)
func _initialize() -> void:
	var map = grid()
	var start := Vector3(1.25,0,1.25)
	var target := Vector3(6.25,0,1.25)
	check(reachable(map,start,target),"Open grid lazily prepares index")
	check(map._connectivity.builds==1,"Exactly one initial build")
	var initial: int = map.topology_generation
	map.add_blocker(&"wall",Rect2(4,0,0.5,8))
	check(map.topology_generation==initial+1,"One generation per complete edit")
	check(not reachable(map,start,target),"Full wall separates islands immediately")
	check(map._connectivity.builds==2,"One rebuild after topology change")
	map.add_blocker(&"overlap",Rect2(4,0,0.5,8))
	var previous: int = map.topology_generation
	map.remove_blocker(&"wall")
	check(map.topology_generation==previous,"Ownership-only removal leaves topology unchanged")
	check(not reachable(map,start,target) and map._connectivity.builds==2,"Remaining owner still blocks without rebuild")
	map.add_blocker(&"overlap",Rect2(4,0,0.5,8))
	check(map.topology_generation==previous,"Identical replacement doesn't invalidate after temporary internal opening")
	map.set_traversal_modifier(&"road",Rect2(0,1,8,0.5),1.25)
	map.set_traversal_modifier(&"tree",Rect2(0,0,2,2),0.2)
	check(map.topology_generation==previous and map.revision>previous,"Costs preserve topology and publish ordinary revision")
	check(not reachable(map,start,target) and map._connectivity.builds==2,"No cost-only rebuild")
	map.remove_traversal_modifier(&"tree")
	map.remove_traversal_modifier(&"road")
	check(map.topology_generation==previous,"Cost source removals preserve topology")
	map.remove_blocker(&"overlap")
	check(reachable(map,start,target),"Removing final owner opens path same frame")
	map.add_blocker(&"one",Rect2(2,0,0.5,8))
	map.add_blocker(&"two",Rect2(5,0,0.5,8))
	var built_before: int = map._connectivity.builds
	check(not reachable(map,start,target) and map._connectivity.builds==built_before+1,"Several pending edits coalesce to one rebuild")
	map.add_blocker(&"one",Rect2(2,0,0.5,3))
	map.remove_blocker(&"two")
	check(reachable(map,start,target),"Replacement with a gap allows detour")
	check(map.find_path(start,target).size()>2,"Native point A* still respects wall gap")
	map.add_blocker(&"horizontal",Rect2(0,4,8,0.5))
	check(not reachable(map,start,Vector3(1.25,0,6.25)),"Multiple islands separated")
	var corner = grid(Rect2(0,0,2,2))
	corner.add_blocker(&"east",Rect2(0.5,0,0.5,0.5))
	corner.add_blocker(&"south",Rect2(0,0.5,0.5,0.5))
	check(not reachable(corner,Vector3(0.25,0,0.25),Vector3(1.25,0,1.25)),"Diagonal contact never cuts blocked corners")
	var ring = grid()
	ring.add_blocker(&"wall",Rect2(4,0,0.5,8))
	var center := Vector3(4.25,0,1.25)
	check(not ring.is_world_walkable(center),"Object center blocked")
	check(reachable(ring,start,center,1.75,0.75),"Annulus spanning components reaches available side")
	check(not reachable(ring,start,target,0.75,0.25),"Walkable goals in wrong component unavailable")
	check(not reachable(ring,start,Vector3(2,0,2),0.1),"Tiny ring without centered goals unavailable")
	check(reachable(ring,start,start+Vector3(0.01,0,0),0.1),"Continuous fast path preserved without centered goal")
	check(reachable(ring,start,Vector3(1.75,0,1.25),0.5,0.5),"Exact inner/outer boundary remains valid")
	check(reachable(ring,start,Vector3(-0.25,0,1.25),0.5),"Goal near map edge clipped correctly")
	check(not reachable(ring,Vector3(-1,0,1),center,1.75),"Invalid starting point safe")
	var column = grid(Rect2(0,0,0.5,4))
	check(reachable(column,Vector3(0.25,0,0.25),Vector3(0.25,0,3.75)),"One-cell-wide grid keeps vertical edges")
	var resized = grid(Rect2(-2,-2,3,5))
	check(reachable(resized,Vector3(-1.75,0,-1.75),Vector3(0.75,0,2.75)),"New grid dimensions/origin produce fresh index")
	check(resized._connectivity._labels.size()==60,"Index size matches new grid")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	for trial in range(8):
		var random_grid = grid()
		for y in range(16):
			for x in range(16):
				if rng.randf()<0.28: random_grid.add_blocker(StringName("%d_%d"%[x,y]),Rect2(x*0.5,y*0.5,0.5,0.5))
		random_grid.set_traversal_modifier(&"road",Rect2(0,1,8,0.5),1.25)
		random_grid.set_traversal_modifier(&"slow",Rect2(3,3,2,2),0.2)
		for sample in range(30):
			var a := Vector2i(rng.randi_range(0,15),rng.randi_range(0,15))
			var b := Vector2i(rng.randi_range(0,15),rng.randi_range(0,15))
			if not random_grid.is_cell_walkable(a): continue
			var origin: Vector3 = random_grid.cell_to_world(a)
			var destination: Vector3 = random_grid.cell_to_world(b)
			var radius: float = [0.1,0.75,1.25][sample%3]
			var inner := 0.25 if radius>0.25 and sample%2==0 else 0.0
			if origin.distance_to(destination)<=radius and origin.distance_to(destination)>=inner: continue
			var expected := original(random_grid,origin,destination,radius,inner)
			var actual: PackedVector3Array = random_grid.find_path_to_radius(origin,destination,radius,inner)
			check(actual==expected,"Random weighted path/endpoint/cost identical to original region search")
			for index in range(1,actual.size()): check(random_grid.has_line_of_sight(actual[index-1],actual[index]),"Smoothed segments remain clear")
	print("Navigation connectivity: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
