extends SceneTree
const TreeData = preload("res://scripts/tree_data.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const P = preload("res://scripts/resident_profession.gd")
const Fixture = preload("res://tests/forestry_fixture.gd")
var checks := 0
var failures := 0
const Locations = preload("res://scripts/world_3d/tree_locations_3d.gd")
class CountedLocations extends Locations:
	var queried: Array[StringName] = []
	func resolve(tree: RefCounted,origin: Vector2) -> Variant:
		queried.append(tree.id)
		return super.resolve(tree,origin)
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func walk(actor: Node) -> void:
	for step in range(1200):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func capture(label: String,scene: Node,actor: Node) -> void:
	if not "--render-qa" in OS.get_cmdline_user_args(): return
	for panel in scene.get_node("HUD").get_children():
		if panel.has_method("set_collapsed"): panel.set_collapsed(true)
	if label=="three_logs_delivered": scene.resident_selection.select_building(scene.player_control.get_building(actor.data.work_location_id))
	else: scene.resident_selection.select(actor.data)
	var camera := scene.get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z
	var center := camera.global_position+forward*(-camera.global_position.y/forward.y)
	camera.global_position += Vector3(-23-center.x,0,-8-center.z)
	camera.size=20
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/forestry_qa")
	scene.get_viewport().get_texture().get_image().save_png("res://.godot/forestry_qa/%s.png"%label)
func run() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.game_logger.console_enabled=false
	for actor in scene.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value=0
			need.base_weight=0
	await physics_frame
	var hut = Fixture.hut(scene)
	hut.definition.target_tree_count=0
	var actor = scene.resident_runtimes[3]
	check(scene.player_control.assign_profession(actor.data.id,P.Type.LUMBERJACK),"Actual main3d profession management")
	var worker = actor.get_node("Lumberjack")
	var resolver = CountedLocations.new()
	resolver.navigation=scene.navigation
	worker.locations=resolver
	var near = TreeData.new(&"near_hut",C.to_sim(Vector3(-24,0,-8)))
	var far = TreeData.new(&"near_resident",C.to_sim(Vector3(-28,0,-8)))
	worker.trees=[far,near]
	actor.view.global_position=Vector3(-30,0,-8)
	check(worker.best_target().tree==near,"Distance rank is from work-area hut, not resident")
	check(resolver.queried==[near.id],"Sort itself issues no navigation; first reachable tree stops search")
	resolver.queried.clear()
	var equal = TreeData.new(&"aaa_equal",C.to_sim(Vector3(-24,0,-8)))
	worker.trees=[near,equal]
	check(worker.best_target().tree==equal,"Equal squared distance uses stable ID")
	worker.trees=[far,near]
	near.claim(&"other")
	check(worker.best_target().tree==far,"Occupied nearest tree excluded")
	near.release(&"other")
	near.state=TreeData.State.DEPLETED
	check(worker.best_target().tree==far,"Depleted nearest tree excluded")
	near.state=TreeData.State.STANDING
	var outside = TreeData.new(&"outside",C.to_sim(Vector3(30,0,20)))
	worker.trees=[outside]
	check(worker.best_target().is_empty(),"Outside work area excluded")
	worker.trees=[far,near]
	# Cover the whole approach disk; far tree remains reachable from left.
	scene.navigation.add_blocker(&"covered_tree",Rect2(-26.3,-10.3,4.6,4.6))
	resolver.queried.clear()
	check(worker.best_target().tree==far and resolver.queried==[near.id,far.id],"Unreachable nearest tree skipped; next reachable wins")
	scene.navigation.remove_blocker(&"covered_tree")
	scene.game_time.total_minutes=420
	resolver.queried.clear()
	check(worker.has_work() and worker.request_work(),"Availability followed by request starts task")
	check(resolver.queried==[near.id],"Availability candidate reused, not searched twice")
	check(near.reservation_owner_id==StringName(actor.data.id) and not worker.chopping,"Tree claimed before real physical approach")
	walk(actor)
	check(worker.chopping and resolver.in_range(near,actor.view.get_sim_position()),"Only valid interaction distance begins chopping")
	worker.abort(false)
	check(near.reservation_owner_id.is_empty(),"Interrupt releases ownership")
	actor.view.global_position=Vector3(-30,0,-8)
	check(worker.has_work(),"Stale claim fixture exposes work")
	near.claim(&"competitor")
	check(worker.request_work() and worker.tree==far,"Claim revalidation skips tree taken since availability")
	worker.abort(false)
	near.release(&"competitor")
	check(worker.has_work(),"Removal fixture exposes work")
	worker.trees.erase(near)
	check(worker.request_work() and worker.tree==far,"Removed availability target is never claimed")
	worker.trees.erase(far)
	scene.game_time.debug_skip_minutes(1)
	check(worker.tree==null and far.reservation_owner_id.is_empty() and not actor.view.movement.is_moving(),"Removal during travel releases ownership/stops executor")
	worker.trees=[near,far]
	scene._register_tree(near) # Use the normal domain/view lifecycle for full-cycle QA.
	scene.game_time.total_minutes=419
	actor.view.global_position=Vector3(-30,0,-8)
	actor.decision._deciding=false
	scene.game_time.advance(1.0)
	check(worker.tree==near and actor.intents.current_intent.reason_id==&"chop_tree","Real 06:59 to 07:00 schedule chooses forestry work")
	actor.view._physics_process(0.4)
	await capture("07_00_approach",scene,actor)
	walk(actor)
	check(worker.chopping,"Normal AI action physically approaches then chops")
	await capture("chopping",scene,actor)
	var second = scene.resident_runtimes[2]
	var second_hut = Fixture.hut(scene,&"second_hut",Vector3(-20,0,-2))
	check(scene.player_control.assign_profession(second.data.id,P.Type.LUMBERJACK) and scene.player_control.assign_workplace(second.data.id,second_hut.id),"Second lumberjack uses overlapping hut area")
	var other = second.get_node("Lumberjack")
	other.trees=[near,far]
	other.locations=resolver
	check(other.request_work() and other.tree==far and near.reservation_owner_id!=far.reservation_owner_id,"Two workers claim different trees, never same ownership")
	walk(second)
	check(other.chopping,"Second worker physically arrives at own tree")
	await capture("two_lumberjacks",scene,actor)
	other.abort(false)
	actor.decision._deciding=true
	scene.game_time.debug_skip_minutes(60)
	check(near.state==TreeData.State.DEPLETED and scene.ground_resources.drops.size()==3,"Unchanged 60-minute chop yields three LOG")
	await capture("three_ground_logs",scene,actor)
	var logs := preload("res://scripts/resource_type.gd").Type.LOG
	for trip in range(3):
		check(worker.request_work() and scene.logistics.get_job(actor.data.id)!=null,"Existing Ground collection retains task priority")
		walk(actor)
		preload("res://tests/handling_test_step.gd").finish(actor)
		walk(actor)
		if trip==0: await capture("hut_unloading",scene,actor)
		preload("res://tests/handling_test_step.gd").finish(actor)
		check(hut.resources.get_amount(logs)==trip+1 and actor.data.inventory.amount==0,"10+10-minute handling deposits one LOG, preserving reservations")
	check(scene.ground_resources.drops.is_empty(),"Full tree-to-ground-to-hut cycle deposits all three LOG")
	await capture("three_logs_delivered",scene,actor)
	Fixture.clear_drops(scene)
	worker.trees=[]
	hut.resources.try_take(logs,3)
	scene.game_time.total_minutes=420
	check(not worker.has_work() and not worker.request_work(),"No trees/plant/export returns unavailable without forced action")
	scene.free()
	print("Forestry selection: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
