extends SceneTree
const Roads = preload("res://scripts/road_grid.gd")
const Grid = preload("res://scripts/navigation_grid.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
const Clock = preload("res://scripts/game_time.gd")
var checks := 0
var failures := 0
var entries: Array[Vector2i] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func model_checks() -> void:
	var roads = Roads.new(Rect2(0,0,8,8))
	var cell := Vector2i(2,2)
	check(roads.levels.size()==256 and Roads.new().levels.size()==40960,"Dense data follows real geometry")
	roads.setup_trampling(360,17)
	roads.chance = 0
	roads.visit(cell)
	check(roads.trample_level(cell)==0,"Zero chance never raises level")
	roads.chance = 1
	roads.visit(cell)
	check(roads.trample_level(cell)==1,"Certain single physical visit raises by one")
	roads.set_trample_level(cell,99)
	check(roads.trample_level(cell)==15,"Upper clamp")
	roads.visit(cell)
	roads.on_minute(1379)
	check(roads.trample_level(cell)==15,"No decay before 23:00")
	roads.on_minute(1380)
	check(roads.trample_level(cell)==15,"Used saturated cell survives night")
	roads.on_minute(1380)
	roads.on_minute(1440)
	check(roads.trample_level(cell)==15,"Duplicate boundary and midnight preserve used cell")
	roads.on_minute(3240)
	check(roads.trample_level(cell)==14,"Unused level15 also decays")
	roads.chance = 0
	roads.visit(cell)
	roads.on_minute(4680)
	check(roads.trample_level(cell)==14,"Failed roll still records use")
	roads.on_minute(6120)
	check(roads.trample_level(cell)==13,"Use marks reset after night")
	roads.set_trample_level(cell,1)
	roads.on_minute(7560)
	check(roads.trample_level(cell)==0 and roads.trampled_cells().is_empty(),"Zero leaves active set")
	roads.set_trample_level(cell,-8)
	check(roads.trample_level(cell)==0 and not roads.set_trample_level(Vector2i(-1,0),7),"Lower clamp and bounds")
	roads.setup_trampling(14000)
	roads.set_trample_level(cell,15)
	roads.on_minute(14000)
	check(roads.trample_level(cell)==15,"Creating mid-night does not backdate decay")
	roads.decay_per_night = 2
	roads.on_minute(20000)
	check(roads.trample_level(cell)==11,"Every completed night once; at most one decay per night")
	roads.visit(cell)
	roads.clear_trampling([cell])
	check(roads._active.is_empty() and roads._used.is_empty(),"Footprint cleanup removes active/use marks")
	var a = Roads.new(); var b = Roads.new()
	a.setup_trampling(360,91); b.setup_trampling(360,91)
	var untouched := RandomNumberGenerator.new(); untouched.seed=78
	var expected := RandomNumberGenerator.new(); expected.seed=78
	for index in range(80):
		var point := Vector2i(index%16,floori(float(index)/16))
		a.visit(point); b.visit(point)
	check(a.levels==b.levels and untouched.state==expected.state,"Seed reproducibility; independent generator")
	seed(109)
	var expected_global: int=randi()
	seed(109)
	for index in range(30):a.visit(Vector2i(index,20))
	check(randi()==expected_global,"Natural RNG never consumes global random stream")
	var nested=Roads.new();nested.setup_trampling(360);nested.set_trample_level(cell,3)
	var repeat_night: Callable=func(_cells):nested.on_minute(1800)
	nested.levels_changed.connect(repeat_night)
	nested.on_minute(1800)
	check(nested.trample_level(cell)==2,"Reentrant duplicate night cannot decay twice")
	nested.levels_changed.disconnect(repeat_night)
	var clock = Clock.new(); root.add_child(clock); clock.set_process(false)
	roads.setup_trampling(clock.total_minutes)
	roads.set_trample_level(cell,3)
	clock.minute_changed.connect(roads.on_minute)
	clock._advance_game_minutes(1020+1440*2+420)
	check(roads.trample_level(cell)==0,"Real GameTime emits all three crossed nights")
	clock.free()
func trajectory(nav, roads, points: Array[Vector3], speed_value: float, step: float) -> Array[Vector2i]:
	var body := Node3D.new(); root.add_child(body); body.position=points[0]
	var mover = Movement.new(); body.add_child(mover)
	mover.body=body; mover.navigation=nav; mover.speed=speed_value
	mover.surface_speed=roads.execution_speed
	entries.clear()
	mover.cell_entered.connect(func(entered_cell): entries.append(entered_cell))
	for index in range(1,points.size()):
		mover.set_target(points[index])
		for frame in range(10000):
			mover.advance(step)
			if not mover.is_moving(): break
	var result: Array[Vector2i] = entries.duplicate()
	body.free()
	return result
func motion_checks() -> void:
	var nav = Grid.new(Rect2(0,0,12,10),0.0)
	var roads = Roads.new(Rect2(0,0,12,10))
	var points: Array[Vector3] = [Vector3(1.25,0,1.25),Vector3(5.25,0,1.25),Vector3(5.25,0,5.25)]
	var slow := trajectory(nav,roads,points,1,1.0/30)
	check(slow.size()==16 and slow[0]==Vector2i(3,2) and slow[-1]==Vector2i(10,10),"All turns/cells once, no spawn entry")
	check(trajectory(nav,roads,points,1,1.0/144)==slow,"30/144 FPS same entry sequence")
	for speed_value in Clock.SUPPORTED_SPEEDS:
		check(trajectory(nav,roads,points,float(speed_value),0.2)==slow,"Speed x%d loses no cells" % speed_value)
	points=[Vector3(1.25,0,1.25),Vector3(3.25,0,3.25)]
	var diagonal := trajectory(nav,roads,points,20,1)
	check(diagonal.size()==4 and diagonal.all(func(entered_cell):return entered_cell.x==entered_cell.y),"Diagonal has no side/corner-only cells")
	points=[Vector3(1.25,0,1.25),Vector3(1.5,0,1.25)]
	check(trajectory(nav,roads,points,1,1).is_empty(),"Touching destination boundary is not entry")
	var body := Node3D.new(); root.add_child(body); body.position=Vector3(1.25,0,1.25)
	var mover=Movement.new(); body.add_child(mover); mover.body=body; mover.navigation=nav; mover.speed=1
	mover.surface_speed=roads.execution_speed
	entries.clear(); mover.cell_entered.connect(func(entered_cell):entries.append(entered_cell))
	mover.set_target(Vector3(5.25,0,1.25)); mover.advance(0)
	check(entries.is_empty(),"Zero time/spawn has no visit")
	mover.advance(0.1); mover.stop(); mover.set_target(Vector3(5.25,0,1.25)); mover.advance(0.05)
	nav.add_blocker(&"far",Rect2(9,8,1,1)); mover.advance(0.01)
	check(entries.is_empty(),"Stop/start/replan inside cell has no new entry")
	mover.advance(0.2)
	check(entries==[Vector2i(3,2)],"First actual boundary enters once")
	mover.set_target(Vector3(1.25,0,1.25)); mover.advance(1)
	check(entries[-1]==Vector2i(2,2) and entries.size()==2,"Returning after exit is new entry")
	mover.stop(); body.position=Vector3(8.25,0,6.25)
	mover.set_target(Vector3(9.25,0,6.25)); entries.clear(); mover.advance(1)
	check(entries==[Vector2i(17,12),Vector2i(18,12)],"Direct relocation creates no intervening cells")
	# Live speed changes keep already travelled geometric progress.
	body.position=Vector3(1.1,0,1.25); mover.set_target(Vector3(5.25,0,1.25)); mover.advance(0.1)
	var before := body.position.x
	var cell := Vector2i(2,2)
	roads.set_trample_level(cell,10); mover.advance(0.1)
	check(is_equal_approx(body.position.x-before,0.1),"Level10 uses ordinary speed")
	before=body.position.x; roads.set_trample_level(cell,11); mover.advance(0)
	check(body.position.x==before,"Promotion at rest has no position jump")
	mover.advance(0.1)
	check(is_equal_approx(body.position.x-before,0.125),"Level11 applies to remaining segment")
	before=body.position.x; roads.set_trample_level(cell,10); mover.advance(0.01)
	check(is_equal_approx(body.position.x-before,0.01),"Demotion restores speed without replay")
	roads.set_trample_level(cell,15)
	check(roads.execution_speed(cell,1)==1.25 and roads.execution_speed(cell,1.25)==1.25 and roads.execution_speed(cell,0.2)==0.2,"Level15/manual overlap/tree minimum")
	var baseline: PackedVector3Array=nav.find_path(Vector3(1.25,0,1.25),Vector3(8.25,0,1.25))
	var revision: int=nav.revision
	for x in range(2,20):roads.set_trample_level(Vector2i(x,1),15)
	check(nav.revision==revision and nav.find_path(Vector3(1.25,0,1.25),Vector3(8.25,0,1.25))==baseline,"Natural levels affect neither revision nor route")
	mover.stop(); body.position=Vector3(1.25,0,1.25); mover.set_target(Vector3(5.25,0,1.25))
	var interrupt: Callable=func(_cell):mover.stop()
	mover.cell_entered.connect(interrupt); mover.advance(1)
	check(not mover.is_moving() and body.position.x<=1.5,"Synchronous cancel stops stale segment loop")
	mover.cell_entered.disconnect(interrupt)
	body.free()
func run() -> void:
	model_checks()
	motion_checks()
	print("Trampling: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
