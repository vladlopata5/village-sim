extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
class Counted extends "res://scripts/navigation_grid.gd":
	var raw_calls := 0
	var smooth_calls := 0
	func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
		raw_calls += 1
		return super.find_raw_path(start,target)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls += 1
		return super.smooth_path(raw)
# Nonempty A* output is insufficient when its physical polyline is unsafe.
class UnsafeRaw extends "res://scripts/navigation_grid.gd":
	var supplied := PackedVector3Array()
	func find_raw_path(_start: Vector3, _target: Vector3) -> PackedVector3Array:
		return supplied
var checks := 0
var failures := 0
var arrivals := 0
var rejected := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func compare(grid: RefCounted, start: Vector3, target: Vector3, label: String, expected: Variant = null) -> void:
	var reference: bool = not grid.find_path(start,target).is_empty()
	var actual: bool = grid.has_walkable_path(start,target)
	check(actual == reference,label+": bool probe preserves full-path reachability")
	if expected is bool: check(actual == expected,label+": expected geometry outcome")
func run() -> void:
	var start := Vector3(1.25,0,5.25)
	var target := Vector3(18.25,0,5.25)
	var grid = Counted.new(Rect2(0,0,20,20),0.4)
	compare(grid,start,target,"Open",true)
	grid.add_blocker(&"building",Rect2(7,3,3,4))
	compare(grid,start,target,"Detour",true)
	compare(grid,start,start,"Same point",true)
	compare(grid,start,Vector3(1.250001,0,5.25),"Very close",true)
	compare(grid,start,Vector3(8,0,4),"Blocked endpoint",false)
	compare(grid,Vector3(-1,0,5),target,"Outside start",false)
	compare(grid,start,Vector3(INF,0,5),"Nonfinite endpoint",false)
	compare(grid,Vector3(0.25,0,1.25),target,"Boundary clearance",false)
	grid.add_blocker(&"wall",Rect2(10,0,0.5,20))
	compare(grid,start,target,"Disconnected",false)
	grid.remove_blocker(&"wall")
	grid.remove_blocker(&"building")
	grid.set_traversal_modifier(&"forest",Rect2(3,4,12,2),0.2)
	grid.set_traversal_modifier(&"road",Rect2(1,2,18,0.5),1.25)
	compare(grid,start,target,"Weighted forest and road",true)
	for radius in [0.0,0.2,0.4,0.8]:
		var corridor = Grid.new(Rect2(0,0,12,10),radius)
		corridor.add_blocker(&"top",Rect2(4,0,4,4))
		corridor.add_blocker(&"bottom",Rect2(4,6,4,4))
		compare(corridor,Vector3(1.25,0,5.25),Vector3(10.25,0,5.25),"Radius %s grid-clearance gap"%radius,radius < 0.8)
		corridor.add_blocker(&"rock",Rect2(5,4.75,0.5,0.5))
		compare(corridor,Vector3(1.25,0,5.25),Vector3(10.25,0,5.25),"Radius %s obstructed gap"%radius)
	var bad = UnsafeRaw.new(Rect2(0,0,8,8),0)
	bad.add_blocker(&"blocked_edge",Rect2(3,2,1,3))
	bad.supplied = PackedVector3Array([Vector3(1.25,0,3.25),Vector3(6.25,0,3.25)])
	check(not bad.supplied.is_empty(),"Unsafe fixture supplies nonempty raw polyline")
	compare(bad,bad.supplied[0],bad.supplied[-1],"Mandatory segment validation",false)
	bad.supplied = PackedVector3Array([Vector3(3.25,0,3.25)])
	compare(bad,bad.supplied[0],bad.supplied[0],"Mandatory first point validation",false)
	var corner = Grid.new(Rect2(0,0,3,3),0)
	corner.add_blocker(&"neighbor",Rect2(0.5,0,0.5,0.5))
	compare(corner,Vector3(0.25,0,0.25),Vector3(0.75,0,0.75),"Diagonal cannot graze corner",true)
	corner.add_blocker(&"other",Rect2(0,0.5,0.5,0.5))
	compare(corner,Vector3(0.25,0,0.25),Vector3(0.75,0,0.75),"Enclosed corner",false)
	# Seeded endpoints include cell edges, noncentral points and differing clearances.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	for radius in [0.0,0.2,0.4,0.8]:
		for layout in 5:
			var sample_grid = Grid.new(Rect2(-6,-6,12,12),radius)
			for obstacle in 8:
				sample_grid.add_blocker(StringName("b%d"%obstacle),Rect2(rng.randf_range(-4,3),rng.randf_range(-4,3),rng.randf_range(0.1,1.2),rng.randf_range(0.1,1.2)))
			if layout%2==0: sample_grid.set_traversal_modifier(&"weighted",Rect2(-4,-2,8,1),0.3)
			for pair in 80:
				var a := Vector3(rng.randf_range(-6.2,6.2),0,rng.randf_range(-6.2,6.2))
				var b := Vector3(rng.randf_range(-6.2,6.2),0,rng.randf_range(-6.2,6.2))
				if pair%4==0: a.x=snappedf(a.x,0.5)
				compare(sample_grid,a,b,"Seeded endpoints")
	# Probe never smooths; executor still does, and reacts to changes after a probe.
	grid = Counted.new(Rect2(0,0,20,20),0.4)
	check(grid.has_walkable_path(start,target) and grid.raw_calls==1 and grid.smooth_calls==0,"Probe uses one raw search and zero smoothing")
	var body := Node3D.new()
	root.add_child(body)
	body.position=start
	var mover := Movement.new()
	body.add_child(mover)
	mover.body=body; mover.navigation=grid; mover.speed=10
	mover.arrived.connect(func():arrivals+=1)
	mover.failed.connect(func():rejected+=1)
	mover.set_target(target)
	mover.advance(0)
	check(grid.smooth_calls==1 and mover.current_path().size()==2,"Real movement still smooths its prepared path")
	grid.add_blocker(&"new_obstacle",Rect2(7,3,3,4))
	mover.advance(0)
	check(grid.smooth_calls==2 and mover.current_path().size()>2,"Revision triggers safe detour after successful probe")
	check(grid.is_raw_path_walkable(mover.current_path()),"Executed detour passes physical geometry validation")
	for tick in 100:
		mover.advance(0.05)
		if not mover.is_moving():break
	check(arrivals==1 and body.position==target,"Movement arrives exactly once after probe and revision")
	body.position=start
	check(grid.has_walkable_path(start,target),"Open route can be probed again")
	grid.add_blocker(&"closed_target",Rect2(17,4,2,2))
	mover.set_target(target);mover.advance(0)
	check(rejected==1 and not mover.is_moving() and body.position==start,"Live executor rejects target blocked after probe")
	grid.remove_blocker(&"closed_target")
	mover.set_target(target);mover.stop()
	var previous: int = grid.smooth_calls
	mover.advance(10)
	check(grid.smooth_calls==previous and body.position==start,"Cancelled movement does not plan or arrive")
	body.free()
	# Actual canonical adapters and a real building's portal access position.
	var world = load("res://scenes/main_3d.tscn").instantiate()
	world.navigation=Counted.new()
	root.add_child(world)
	world.game_time.set_process(false);world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.view.set_physics_process(false)
	var origin := Coordinates.to_sim(Vector3(-15,0,20))
	var portal: Vector2 = world.world_locations.get_position(world.warehouse_data.id)
	var reference: bool = not world.navigation.find_path(Coordinates.to_world(origin),Coordinates.to_world(portal)).is_empty()
	world.navigation.raw_calls=0;world.navigation.smooth_calls=0
	check(reference and world._resource_route_available(origin,portal),"Real canonical resource probe reaches actual building access point")
	check(world.navigation.raw_calls==1 and world.navigation.smooth_calls==0,"Resource adapter retains A* and removes only smoothing")
	var nearby := origin+Vector2(25,0)
	check(world._reachable_wander_target(origin,nearby),"Canonical wander probe remains reachable")
	var lumber = preload("res://scripts/resident_lumberjack_controller.gd").new()
	lumber.locations=world.tree_locations
	check(lumber._path(origin,portal)==reference,"Lumberjack export probe preserves access reachability")
	check(world.navigation.smooth_calls==0,"All point bool-only adapters avoid smoothing")
	lumber.free();world.free()
	await process_frame
	print("Reachability probes: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
