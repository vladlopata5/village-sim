extends SceneTree
const P = preload("res://scripts/resident_profession.gd")
const Fixture = preload("res://tests/forestry_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Connectivity = preload("res://scripts/navigation_connectivity.gd")
var checks := 0
var failures := 0
class CountedConnectivity extends Connectivity:
	var builds := 0
	func _rebuild(grid: RefCounted) -> void:
		builds += 1
		super._rebuild(grid)
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	scene.navigation._connectivity = CountedConnectivity.new()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.game_logger.console_enabled = false
	check(scene.navigation._connectivity.builds==1,"Canonical startup prepares once")
	for actor in scene.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
	var a = scene.resident_runtimes[3]
	var b = scene.resident_runtimes[2]
	var hut = Fixture.hut(scene)
	var area = scene.work_areas.create(hut.position,C.length_to_sim(15))
	for actor in [a,b]:
		scene.player_control.assign_profession(actor.data.id,P.Type.LUMBERJACK)
		scene.player_control.assign_work_area(actor.data.id,area.id)
		actor.view.global_position = Vector3(40,0,25)
	scene.game_time.total_minutes = 419
	scene.game_time.set_speed(20)
	if "--rendered" in OS.get_cmdline_user_args():
		var camera = scene.get_node("World/Camera3D")
		camera.global_position = Vector3(-20,0,-8) + Vector3(20,28,20)
		camera.set_zoom_distance(50 / (2 * tan(deg_to_rad(camera.fov / 2))))
	scene.navigation.add_blocker(&"test_wall",Rect2(-10,-40,1,80))
	var before: int = scene.navigation._connectivity.builds
	scene.game_time.advance(0.05) # Actual x20 minute/phase boundary, including HUD signals.
	for actor in [a,b]:
		check(not actor.get_node("Lumberjack").has_work(),"Shared FREE area unreachable")
	check(scene.navigation._connectivity.builds==before+1,"Two workers share one lazy rebuild")
	for iteration in range(3):
		for actor in [a,b]: check(not actor.get_node("Lumberjack").has_work(),"Repeated availability unchanged")
	check(scene.navigation._connectivity.builds==before+1,"Repeated negative queries never rebuild")
	scene.player_control.assign_workplace(a.data.id,hut.id)
	check(not a.get_node("Lumberjack").has_work(),"BUILDING unreachable forestry unchanged")
	var other = scene.work_areas.create(C.to_sim(Vector3(-26,0,-8)),C.length_to_sim(15))
	scene.player_control.assign_work_area(b.data.id,other.id)
	check(not b.get_node("Lumberjack").has_work(),"Different independent area shares same topology")
	scene.navigation.set_traversal_modifier(&"test_road",Rect2(35,20,1,1),1.25)
	check(not b.get_node("Lumberjack").has_work(),"Road cost edit cannot open wall")
	check(scene.navigation._connectivity.builds==before+1,"Road edits avoid connectivity rebuild")
	scene.navigation.remove_blocker(&"test_wall")
	check(a.get_node("Lumberjack").has_work() and b.get_node("Lumberjack").has_work(),"Removing wall enables both modes same frame")
	check(a.get_node("Lumberjack").request_work() and b.get_node("Lumberjack").request_work(),"Both modes create normal committed actions")
	check(a.get_node("Lumberjack").tree!=b.get_node("Lumberjack").tree,"Shared forest claims distinct targets")
	if "--rendered" in OS.get_cmdline_user_args():
		scene.navigation_debug.set_enabled(true)
		await process_frame
		await process_frame
		get_root().get_texture().get_image().save_png("user://connectivity_reachable.png")
	for actor in [a,b]:
		actor.intents.abort_current(actor.intents.current_intent)
	scene.navigation.add_blocker(&"test_wall",Rect2(-10,-40,1,80))
	check(not a.get_node("Lumberjack").has_work() and not b.get_node("Lumberjack").has_work(),"Added wall immediately makes work unavailable")
	other.update(C.to_sim(Vector3(40,0,25)),C.length_to_sim(15))
	check(not b.get_node("Lumberjack").has_work(),"Same-frame WorkArea edit revalidates eligible trees")
	if "--rendered" in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		get_root().get_texture().get_image().save_png("user://connectivity_unreachable.png")
	scene.free()
	print("Connectivity forestry: %d checks, %d failures"%[checks,failures])
	quit(1 if failures>0 else 0)
