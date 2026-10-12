extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var grid := Grid.new(Rect2(-5,-5,10,10),0.0)
	check(grid.can_reach_point(Vector3(-2,0,0),Vector3(2,0,0)),"Open points connected")
	grid.add_blocker(&"wall",Rect2(0,-5,0.5,10))
	check(not grid.can_reach_point(Vector3(-2,0,0),Vector3(2,0,0)),"Disconnected targets pre-rejected")
	check(not grid.can_reach_point(Vector3(0.25,0,0),Vector3(2,0,0)),"Blocked start rejected")
	check(not grid.can_reach_point(Vector3(-2,0,0),Vector3(0.25,0,0)),"Blocked target rejected")
	check(not grid.can_reach_point(Vector3(-20,0,0),Vector3(2,0,0)),"Bounds rejected")
	grid.remove_blocker(&"wall")
	check(grid.can_reach_point(Vector3(-2,0,0),Vector3(2,0,0)),"Dynamic removal refreshes connectivity")
	for x in [-4.25,-2.25,1.25,3.25]:
		for z in [-4.25,-1.25,1.25,3.25]:
			var a := Vector3(x,0,z)
			var b := Vector3(-x,0,-z)
			check(grid.can_reach_point(a,b)==not grid.find_path(a,b).is_empty(),"Point precheck agrees with backend on flat map")
	print("Point connectivity: 22 checks, %d failures" % failures)
	quit(1 if failures else 0)
