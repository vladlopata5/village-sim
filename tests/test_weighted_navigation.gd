extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const G = preload("res://scripts/world_3d/world_geometry.gd")
const Def = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var grid = Grid.new(Rect2(0,0,12,8),0.0)
	var a := Vector3(1.25,0,3.25)
	var b := Vector3(10.25,0,3.25)
	check(Balance.TREE_TRAVERSAL_SPEED_MULTIPLIER==0.2,"Central tree speed balance")
	check(grid.get_world_speed_multiplier(a)==1.0,"Ground default speed")
	grid.set_traversal_modifier(&"forest",Rect2(4,2,3,2.5),0.2)
	var raw: PackedVector3Array = grid.find_raw_path(a,b)
	var path: PackedVector3Array = grid.smooth_path(raw)
	check(not raw.is_empty() and path.size()>2 and path.size()<raw.size(),"Weighted A* detours, smoothing still removes waypoints")
	check(grid.path_travel_cost(path)<grid.segment_travel_cost(a,b),"Faster detour survives smoothing; direct LOS is insufficient")
	check(grid.path_travel_cost(path)<=grid.path_travel_cost(raw)+0.0001,"Smoothing never increases travel time")
	print("Weighted raw/smooth: %d/%d, time %.3f/%.3f, direct %.3f" % [raw.size(),path.size(),grid.path_travel_cost(raw),grid.path_travel_cost(path),grid.segment_travel_cost(a,b)])
	grid.set_traversal_modifier(&"second",Rect2(5,3,1,1),0.2)
	check(is_equal_approx(grid.get_world_speed_multiplier(Vector3(5.25,0,3.25)),0.2),"Overlapping sources do not multiply to .04")
	grid.remove_traversal_modifier(&"forest")
	check(is_equal_approx(grid.get_world_speed_multiplier(Vector3(5.25,0,3.25)),0.2),"Removing one owner preserves second source")
	grid.set_traversal_modifier(&"second",Rect2(8,6,1,1),0.2)
	check(grid.get_world_speed_multiplier(Vector3(5.25,0,3.25))==1.0,"Replacing source releases its old cells")
	grid.remove_traversal_modifier(&"second")
	grid.remove_traversal_modifier(&"unknown")
	check(grid.find_path(a,b).size()==2,"Last removal restores direct route immediately")
	# Future speedups use normalized weights >= 1, including ground. No road system.
	grid.set_traversal_modifier(&"fast_test",Rect2(1,1,9.5,0.5),3.0)
	path = grid.find_path(a,b)
	check(path.size()>2 and grid.path_travel_cost(path)<a.distance_to(b),"Generic speedup attracts a longer but faster route")
	check(grid.get_cell_traversal_cost(grid.world_to_cell(Vector3(3.25,0,1.25)))==1.0 and grid.get_cell_traversal_cost(grid.world_to_cell(a))==3.0,"Normalization keeps fastest/ground weights 1/3, heuristic admissible")
	grid.set_traversal_modifier(&"slow_test",Rect2(3,1,1,0.5),0.2)
	check(is_equal_approx(grid.get_world_speed_multiplier(Vector3(3.25,0,1.25)),0.2),"Slowest source wins over a speedup, independent of insertion order")
	grid.remove_traversal_modifier(&"slow_test")
	grid.remove_traversal_modifier(&"fast_test")
	check(grid.get_cell_traversal_cost(grid.world_to_cell(a))==1.0,"Removing maximum speed renormalizes remaining grid")
	# A full-width slow band cannot isolate an otherwise connected world.
	grid.set_traversal_modifier(&"only_exit",Rect2(4,0,1,8),0.2)
	path = grid.find_path(a,b)
	check(not path.is_empty() and grid.is_world_walkable(Vector3(4.25,0,3.25)),"Only exit through forest stays reachable")
	check(is_equal_approx(grid.segment_travel_cost(a,b),13.0),"Travel cost integrates ground 8 plus slow distance 1/.2")
	var body := Node3D.new()
	root.add_child(body)
	var mover := Movement.new()
	body.add_child(mover)
	mover.body=body
	mover.navigation=grid
	mover.speed=1.0
	body.position=a
	mover.set_target(b)
	for frame in range(300): mover.advance(1.0/30.0)
	var fps30: Vector3 = body.position
	body.position=a
	mover.set_target(b)
	for frame in range(1440): mover.advance(1.0/144.0)
	print("FPS drift: ",body.position.distance_to(fps30))
	check(body.position.distance_to(fps30)<0.00001,"30/144 FPS identical across entry/exit boundaries")
	body.position=a
	mover.set_target(b)
	mover.speed=20.0
	mover.advance(0.5)
	check(body.position.distance_to(fps30)<0.00001,"x1/x20 same game time across zone boundaries")
	var paused_position: Vector3 = body.position
	mover.advance(0)
	check(body.position==paused_position,"Pause consumes no movement time")
	mover.advance(1)
	check(not mover.is_moving() and body.position==b,"Weighted movement reaches exact target")
	grid.remove_traversal_modifier(&"only_exit")
	var first := Vector3(2.25,0,3.25)
	var last := Vector3(3.25,0,3.25)
	body.position=first
	mover.speed=1.0
	mover.set_target(last)
	mover.advance(1.0)
	check(not mover.is_moving(),"One unit on ground takes one second at base speed1")
	grid.set_traversal_modifier(&"uniform",grid.bounds,0.2)
	body.position=first
	mover.set_target(last)
	mover.advance(1.0)
	check(is_equal_approx(body.position.distance_to(first),0.2) and mover.is_moving(),"Same distance in forest progresses at one fifth speed")
	mover.advance(4.0)
	check(not mover.is_moving() and body.position==last,"Same distance takes exactly five times as long")
	grid.remove_traversal_modifier(&"uniform")
	var boundary_target := Vector3(5.000001,0,3.25)
	body.position=a
	mover.set_target(boundary_target)
	mover.advance(20)
	check(body.position==boundary_target and not mover.is_moving(),"Very short final cell segment still arrives at exact target")
	body.position=a
	mover.set_target(b)
	mover.advance(0)
	grid.set_traversal_modifier(&"live",Rect2(4,2,3,2.5),0.2)
	mover.advance(0)
	check(mover.current_path().size()>2,"Traversal revision replans an active target")
	grid.remove_traversal_modifier(&"live")
	mover.advance(0)
	check(mover.current_path().size()==2,"Removal immediately restores active direct route")
	body.free()
	await corridor()
	print("Weighted navigation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func corridor() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.social_events.enabled=false
	for runtime in world.resident_runtimes:
		runtime.decision._deciding=true
		runtime.intents.abort_current(runtime.intents.current_intent)
		runtime.view.set_physics_process(false)
	await physics_frame
	var hut = Instance.new(&"corridor_hut",Def.for_type(Types.LUMBERJACK_HUT),C.to_sim(Vector3(33,0,10)))
	var saw = Instance.new(&"corridor_saw",Def.for_type(Types.SAWMILL),C.to_sim(Vector3(40,0,10)))
	for building in [hut,saw]:
		world.buildings.append(building)
		world._show_building(building)
	var trees: Array = []
	for z in [8.0,12.0]:
		trees.append(world.spawn_sapling(C.to_sim(Vector3(36,0,z))))
	var start := Vector3(36,0,10)
	var end := Vector3(36,0,5)
	# Reproduce old hard-blocker state with the same physical geometry.
	var old = Grid.new()
	for building in world.buildings: old.add_blocker(building.id,G.footprint(building))
	for tree in trees: old.add_blocker(tree.id,world.tree_footprint(tree))
	check(old.find_path(start,end).is_empty(),"Original two-tree hut/sawmill corridor regression really was trapped")
	check(not world.navigation.find_path(start,end).is_empty(),"Same corridor remains reachable with two soft saplings")
	check(world.runtime_placement_blockers.has_blocker(trees[0].id),"Trees retain independent placement blocking")
	world.placement.select(Def.for_type(Types.HOME))
	world.placement.update_world_position(C.to_world(trees[0].position))
	check(not world.placement.can_place(),"Soft tree still rejects building placement")
	world.placement.cancel()
	var actor = world.resident_runtimes[0]
	actor.view.global_position=start
	check(world.player_control.move_to(actor.data.id,C.to_sim(end)),"Real Stephan receives ordinary PlayerCommand")
	var slow_seen := false
	var normal_seen := false
	for frame in range(250):
		var before: Vector3 = actor.view.get_world_position()
		actor.view._physics_process(0.02)
		var after: Vector3 = actor.view.get_world_position()
		var speed_at: float = world.navigation.get_world_speed_multiplier(before.lerp(after,0.5))
		var moved: float = before.distance_to(after)
		var expected: float = actor.view.movement.speed*0.02
		if speed_at<1.0 and absf(moved-expected*0.2)<0.0001: slow_seen=true
		if speed_at==1.0 and absf(moved-expected)<0.0001: normal_seen=true
		if not actor.view.movement.is_moving(): break
	check(slow_seen and normal_seen,"Actual executor slows in tree cells and restores ground speed")
	check(actor.view.get_world_position().distance_to(end)<0.0001 and actor.commands.active_command==null,"Corridor MOVE_TO arrives and completes")
	var tree = trees[0]
	var stable_id: StringName = tree.id
	world._grow_trees(world.game_time.total_minutes+Balance.TREE_GROWTH_MINUTES)
	check(tree.id==stable_id and is_equal_approx(world.navigation.get_world_speed_multiplier(C.to_world(tree.position)),0.2),"Growth preserves ID and replaces modifier cells without hard blocking")
	check(tree.claim(&"test_chop") and tree.add_work(&"test_chop",tree.work_required),"Normal domain chopping depletes mature tree")
	world._deplete_tree(tree)
	check(world.navigation.get_world_speed_multiplier(C.to_world(tree.position))==1.0 and not world.runtime_placement_blockers.has_blocker(tree.id),"Depletion removes slow source and placement registration")
	check(world.ground_resources.drops.size()==3,"Forestry yield remains three physical LOG")
	world.spawn_sapling(tree.position)
	check(is_equal_approx(world.navigation.get_world_speed_multiplier(C.to_world(tree.position)),0.2),"Replanting restores slow traversal")
	check(not world.navigation.is_world_walkable(C.to_world(hut.position)) and not world.navigation.is_world_walkable(C.to_world(saw.position)),"Buildings remain hard navigation blockers")
	world.free()
