extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func path_clear(grid: RefCounted, path: PackedVector3Array) -> bool:
	for i in range(path.size()-1):
		if not grid.has_line_of_sight(path[i],path[i+1]): return false
	return not path.is_empty()
func _run() -> void:
	check(Grid.CELL_SIZE == 0.5, "Navigation cells use 0.5 world units")
	var world = Grid.new()
	check(world.grid_size() == Vector2i(256,160) and world.bounds == Rect2(-64,-40,128,80), "Main grid covers all starter playable bounds")
	check(Coordinates.to_world(Vector2(250,500)) == Vector3(10,0,20), "Central bridge applies agreed 25:1 scale")
	check(Coordinates.to_sim(Vector3(10,0,20)) == Vector2(250,500), "World position providers return simulation units")
	check(Coordinates.length_to_world(120) == 4.8, "Simulation movement speed converts once to world units")
	check(Geometry.RESIDENT_RADIUS == 0.4, "Physical resident clearance is in world units")
	var grid = Grid.new(Rect2(0,0,8,8),0.0)
	for cell in [Vector2i.ZERO,Vector2i(7,8),Vector2i(15,15)]:
		check(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "Cell/world center round-trip")
	check(grid.cell_to_world(Vector2i(2,3),2.0).y == 2.0, "Cell conversion admits explicit future terrain height")
	var start: Vector3 = grid.cell_to_world(Vector2i(1,3))
	var target: Vector3 = grid.cell_to_world(Vector2i(14,3))
	var raw: PackedVector3Array = grid.find_raw_path(start,target)
	var smooth: PackedVector3Array = grid.find_path(start,target)
	check(raw.size() == 14 and smooth.size() == 2, "Empty-world smoothing removes redundant cell waypoints")
	check(smooth[0] == start and smooth[-1] == target, "World-space path preserves exact endpoints")
	grid.add_blocker(&"building",Rect2(3,1,2,2))
	check(not grid.has_line_of_sight(start,target), "Physical building blocks direct traversal")
	raw = grid.find_raw_path(start,target)
	smooth = grid.find_path(start,target)
	check(raw.size() > smooth.size() and smooth.size()>2, "Obstacle path is smoothed but retains a detour")
	check(path_clear(grid,smooth), "Every smoothed segment passes authoritative supercover traversal")
	print("Obstacle raw/smoothed waypoints: %d / %d; smooth=%s" % [raw.size(),smooth.size(),smooth])
	grid.add_blocker(&"tree_future_test",Rect2(3,1,2,2))
	grid.remove_blocker(&"building")
	check(not grid.is_world_walkable(Vector3(3.25,0,1.25)), "Removing one overlapping blocker keeps the other")
	grid.remove_blocker(&"tree_future_test")
	check(grid.find_path(start,target).size()==2, "Removing final owner opens path immediately")
	grid.add_blocker(&"same_id",Rect2(3,1,2,2))
	grid.add_blocker(&"same_id",Rect2(6,6,1,1))
	check(grid.is_world_walkable(Vector3(3.25,0,1.25)), "Replacing blocker ID releases old cells without leaked counts")
	grid.remove_blocker(&"same_id")
	grid.remove_blocker(&"unknown")
	check(grid.is_world_walkable(Vector3(6.25,0,6.25)), "Removing replacement clears its cells")
	grid.add_blocker(&"wall",Rect2(3.5,0,0.5,8))
	check(grid.find_path(start,target).is_empty(), "Disconnected targets return no partial path")
	check(grid.find_path(start,Vector3(9,0,2)).is_empty(), "Out-of-bounds target is unavailable")
	check(grid.find_path(start,Vector3(3.75,0,2)).is_empty(), "Blocked target is unavailable; no silent nearest-point projection")
	check(grid.find_path(Vector3(-1,0,2),target).is_empty(), "Out-of-bounds start is unavailable")
	grid.remove_blocker(&"wall")
	check(grid.find_path(start,target).size()==2, "Runtime removal restores connectivity without rebuild")
	var padded = Grid.new(Rect2(0,0,8,8),0.4)
	var footprint := Rect2(3,3,1,1)
	padded.add_blocker(&"obstacle",footprint)
	check(footprint == Rect2(3,3,1,1), "Clearance does not mutate physical footprint")
	check(not padded.is_world_walkable(Vector3(2.75,0,3.25)), "Resident clearance blocks cells outside physical footprint")
	check(padded.is_world_walkable(Vector3(2.25,0,3.25)), "Point beyond padded obstacle remains available")
	var padded_path: PackedVector3Array = padded.find_path(Vector3(1.25,0,3.25),Vector3(6.25,0,3.25))
	check(path_clear(padded,padded_path), "Smoothed detour respects clearance, not just mesh collider")
	for i in range(padded_path.size()-1):
		for step in range(21):
			var point := Coordinates.world_plane(padded_path[i].lerp(padded_path[i+1],step/20.0))
			check(point.distance_to(point.clamp(footprint.position,footprint.end)) >= 0.4, "Sampled smoothed path preserves resident radius")
	check(not padded.is_world_walkable(Vector3(0.25,0,1.25)), "Boundary clearance prevents body outside playable map")
	padded.add_blocker(&"edge",Rect2(0,0,0.5,0.5))
	padded.remove_blocker(&"edge")
	check(not padded.is_cell_walkable(Vector2i.ZERO), "Removing blocker does not erase permanent boundary clearance")
	# Diagonal neighbors both need to be open. Jump-point optimization is not used.
	var corners = Grid.new(Rect2(0,0,2,2),0.0)
	corners.add_blocker(&"right",Rect2(0.5,0,0.5,0.5))
	corners.add_blocker(&"below",Rect2(0,0.5,0.5,0.5))
	check(corners.find_path(Vector3(0.25,0,0.25),Vector3(0.75,0,0.75)).is_empty(), "A* cannot cut diagonally through two blocked corners")
	check(not corners.has_line_of_sight(Vector3(0.25,0,0.25),Vector3(0.75,0,0.75)), "Smoothing also rejects diagonal corner cutting")
	corners.remove_blocker(&"below")
	var corner_path: PackedVector3Array = corners.find_path(Vector3(0.25,0,0.25),Vector3(0.75,0,0.75))
	check(corner_path.size()==3 and path_clear(corners,corner_path), "Even one blocked neighbor forbids diagonal shortcut")
	check(not corners.has_line_of_sight(Vector3(0.5,0,0.75),Vector3(0.5,0,0.1)), "Boundary-aligned LOS cannot graze a blocked cell edge")
	# Continuous endpoints need conservative traversal too, not just center-to-center LOS.
	var rng := RandomNumberGenerator.new()
	rng.seed=9182
	var symmetric := true
	var safe := true
	for sample in range(100):
		var a := Vector3(rng.randf_range(0.6,7.4),0,rng.randf_range(0.6,7.4))
		var b := Vector3(rng.randf_range(0.6,7.4),0,rng.randf_range(0.6,7.4))
		symmetric = symmetric and padded.has_line_of_sight(a,b)==padded.has_line_of_sight(b,a)
		if padded.has_line_of_sight(a,b):
			for step in range(61):
				var point := Coordinates.world_plane(a.lerp(b,step/60.0))
				safe = safe and point.distance_to(point.clamp(footprint.position,footprint.end))>=0.4
	check(symmetric, "Continuous LOS is symmetric for deterministic arbitrary endpoints")
	check(safe, "Continuous LOS segments never enter physical resident clearance")
	# Movement budget includes all waypoints; revision changes replan committed targets.
	var body := Node3D.new()
	root.add_child(body)
	var mover := Movement.new()
	body.add_child(mover)
	mover.body=body
	mover.navigation=grid
	mover.speed=4.8
	body.position=start
	mover.set_target(target)
	mover.advance(0.1)
	var first: Vector3 = body.position
	check(is_equal_approx(first.distance_to(start),0.48), "Scaled executor moves expected distance for elapsed time")
	grid.add_blocker(&"runtime",Rect2(3,1,2,2))
	mover.advance(0.0)
	check(mover.current_path().size()>2 and path_clear(grid,mover.current_path()), "Active target replans when blocker revision changes")
	grid.remove_blocker(&"runtime")
	mover.advance(0.0)
	check(mover.current_path().size()==2, "Active target immediately uses opened route after removal")
	for step in range(50): mover.advance(0.1)
	check(not mover.is_moving() and body.position==target, "Movement reaches exact requested target and stops")
	var stopped: Vector3 = body.position
	mover.advance(10)
	check(body.position==stopped, "Stopped movement does not jitter")
	mover.set_target(Vector3(99,0,99))
	mover.advance(0.0)
	check(not mover.is_moving(), "Invalid path fails without stuck movement")
	mover.set_target(start)
	mover.stop()
	check(not mover.is_moving() and mover.current_path().is_empty(), "Interrupt clears movement path")
	# Same game-time distance at x1 and x20, including an obstacle waypoint turn.
	grid.add_blocker(&"time_scale",Rect2(3,1,2,2))
	body.position=start
	mover.speed=4.8
	mover.set_target(target)
	for frame in range(20): mover.advance(0.05)
	var x1: Vector3 = body.position
	body.position=start
	mover.speed=4.8*20
	mover.set_target(target)
	mover.advance(0.05)
	check(body.position.is_equal_approx(x1), "x1/x20 equivalent game time has identical progress across smoothed waypoints")
	grid.remove_blocker(&"time_scale")
	body.free()
	print("NavigationGrid: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
