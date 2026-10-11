extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
var checks := 0
var failures := 0
class CountedGrid extends Grid:
	var ordinary_calls := 0
	var raw_calls := 0
	var smooth_calls := 0
	func find_path(a: Vector3,b: Vector3) -> PackedVector3Array:
		ordinary_calls += 1
		return super.find_path(a,b)
	func find_raw_path(a: Vector3,b: Vector3) -> PackedVector3Array:
		raw_calls += 1
		return super.find_raw_path(a,b)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls += 1
		return super.smooth_path(raw)
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func valid_path(grid: RefCounted,path: PackedVector3Array,center: Vector3,radius: float,inner: float) -> bool:
	if path.is_empty(): return false
	var distance := Vector2(path[-1].x,path[-1].z).distance_to(Vector2(center.x,center.z))
	if distance > radius+0.00001 or distance < inner-0.00001: return false
	for i in range(1,path.size()):
		if not grid.has_line_of_sight(path[i-1],path[i]): return false
	return true
func _initialize() -> void:
	var grid = CountedGrid.new(Rect2(-8,-8,16,16),0.0)
	var center := Vector3(2.25,0,2.25)
	grid.add_blocker(&"trunk",Rect2(2,2,0.5,0.5))
	check(not grid.is_world_walkable(center),"Center may be blocked")
	for start in [Vector3(-4.25,0,2.25),Vector3(6.25,0,2.25),Vector3(2.25,0,-4.25),Vector3(2.25,0,6.25)]:
		var previous: int = grid.smooth_calls
		var path: PackedVector3Array = grid.find_path_to_radius(start,center,1.75,0.75)
		check(valid_path(grid,path,center,1.75,0.75),"Approach from every side stays outside trunk/inside radius")
		check(grid.smooth_calls==previous+1,"Only found region path is smoothed once")
	check(grid.raw_calls==0 and grid.ordinary_calls==0,"Region search never starts 24 point-to-point searches")
	grid.add_blocker(&"obstacle",Rect2(-1,-1,1,5))
	var around: PackedVector3Array = grid.find_path_to_radius(Vector3(-4.25,0,2.25),center,1.75,0.75)
	check(valid_path(grid,around,center,1.75,0.75) and around.size()>2,"Smoothing keeps necessary obstacle detour")
	var inside := Vector3(3.25,0,2.25)
	check(grid.find_path_to_radius(inside,center,1.75,0.75)==PackedVector3Array([inside]),"Already inside valid annulus requires no travel")
	check(grid.find_path_to_radius(Vector3(2.75,0,2.25),center,1.75,0.75).size()>1,"Inside trunk clearance is not a valid arrival")
	var raised: PackedVector3Array = grid.find_path_to_radius(Vector3(6.25,3,2.25),Vector3(2.25,10,2.25),1.75,0.75)
	check(valid_path(grid,raised,center,1.75,0.75) and raised[-1].y==3,"Region connectivity/radius ignores visual Y")
	grid.add_blocker(&"wall",Rect2(-1,-8,1,16))
	check(grid.find_path_to_radius(Vector3(-4.25,0,2.25),center,1.75,0.75).is_empty(),"Disconnected region is unavailable")
	grid.remove_blocker(&"wall")
	grid.add_blocker(&"cover",Rect2(0,0,5,5))
	check(grid.find_path_to_radius(Vector3(-4.25,0,2.25),center,1.75,0.75).is_empty(),"Region with no walkable goals is unavailable")
	check(grid.find_path_to_radius(Vector3(99,0,0),center,1.75).is_empty(),"Invalid start safely fails")
	check(grid.find_path_to_radius(Vector3(-4.25,0,2.25),center,-1).is_empty(),"Invalid radius safely fails")
	var corners = Grid.new(Rect2(0,0,2,2),0.0)
	corners.add_blocker(&"right",Rect2(0.5,0,0.5,0.5))
	corners.add_blocker(&"down",Rect2(0,0.5,0.5,0.5))
	check(corners.find_path_to_radius(Vector3(0.25,0,0.25),Vector3(1.25,0,1.25),0.4).is_empty(),"No diagonal corner cutting out of enclosed start")
	var tiny = Grid.new(Rect2(0,0,4,4),0.0)
	check(tiny.find_path_to_radius(Vector3(0.25,0,0.25),Vector3(2,0,2),0.1).is_empty(),"No implicit discretization radius expansion")
	# Entry-cell weights must still favor faster detours around slow forest terrain.
	var fast = Grid.new(Rect2(0,0,12,8),0.0)
	fast.set_traversal_modifier(&"slow",Rect2(4,1,3,5),0.2)
	var route: PackedVector3Array = fast.find_path_to_radius(Vector3(1.25,0,3.25),Vector3(10.25,0,3.25),0.4)
	check(valid_path(fast,route,Vector3(10.25,0,3.25),0.4,0) and route.size()>2,"Weighted region A* and smoothing preserve faster forest detour")
	check(not fast.find_path(Vector3(1.25,0,3.25),Vector3(10.25,0,3.25)).is_empty(),"Ordinary point navigation still works")
	print("Navigation radius: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
