extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const R = preload("res://scripts/resource_type.gd").Type
const Skill = preload("res://scripts/skill_type.gd").Type
const Locations = preload("res://scripts/world_3d/natural_source_locations_3d.gd")
class CountedLocations extends Locations:
	var queries := 0
	func resolve(source: RefCounted, origin: Vector2) -> Variant:
		queries += 1
		return super.resolve(source,origin)
var checks := 0
var failures := 0
var scene: Node
var rendered := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(1800):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func capture(name: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/stone-mining-phase1/"+name+".png")
func run() -> void:
	rendered = "--rendered" in OS.get_cmdline_user_args()
	scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for actor in scene.resident_runtimes:
		actor.view.set_physics_process(false)
		actor.decision._deciding = true
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
	await physics_frame
	var actor = scene.resident_runtimes[3]
	var worker = actor.get_node("Miner")
	var counted := CountedLocations.new()
	counted.navigation = scene.navigation
	worker.locations = counted
	check(R.FOOD==0 and R.LOG==1 and R.PLANK==2 and R.STONE==3,"Existing resource IDs preserved")
	check(scene.rocks.size()==10 and scene.rock_views.size()==10,"Ten starter rocks with views")
	check(scene.warehouse_data.resources.get_capacity(R.STONE)==100 and scene.warehouse_data.resources.get_amount(R.STONE)==0,"Town Center stone capacity and initial zero")
	check(scene.player_control.assign_profession(actor.data.id,P.MINER),"MINER without building allowed")
	scene.game_time.total_minutes = 420
	check(not actor.decision._has_work(),"No area means no WORK")
	actor.data.work_area_id = &"missing"
	check(not actor.decision._has_work(),"Missing area safely unavailable")
	var area = scene.work_areas.create(C.to_sim(Vector3(30,0,-9)),C.length_to_sim(15))
	check(scene.player_control.assign_work_area(actor.data.id,area.id),"Reuse existing WorkArea for miner")
	check(not scene.player_control.assign_work_area(actor.data.id,&"missing") and actor.data.work_area_id==area.id,"Invalid reassignment atomic")
	check(worker.has_work(),"Area exposes mining")
	var source = worker._available.rock
	var topology: int = scene.navigation.topology_generation
	check(worker.request_work() and worker.rock==source and counted.queries==1,"One-use selection cache")
	check(not scene.navigation.is_world_walkable(C.to_world(source.position)),"Rock center hard blocked")
	walk(actor)
	check(worker.mining and scene.rock_locations.in_range(source,actor.view.get_sim_position()),"Physical annulus arrival starts work")
	scene.game_time.debug_skip_minutes(17)
	worker.abort(false)
	check(source.work_done==17 and source.reservation_owner_id.is_empty() and scene.ground_resources.drops.is_empty(),"Interrupted partial persists without yield")
	check(actor.data.get_skill_xp(Skill.GATHERING)==0,"Partial awards no XP")
	check(worker.request_work(),"Resume mining")
	walk(actor)
	scene.player_control.clear_work_assignment(actor.data.id)
	scene.game_time.debug_skip_minutes(43)
	check(source.stock==9 and source.work_done==0 and scene.ground_resources.drops.size()==1,"17+43 produces exactly one stone")
	check(actor.data.inventory.amount==0 and worker.rock==null,"FREE leaves resource and finishes action")
	check(actor.data.get_skill_xp(Skill.GATHERING)==1,"Exactly one GATHERING XP")
	check(scene.navigation.topology_generation==topology,"Intermediate stock/claim/work do not change topology")
	var drop = scene.ground_resources.drops[0]
	check(drop.resource_type==R.STONE and scene.rock_locations.is_available(drop.world_position),"Ground STONE on walkable worker position")
	scene._complete_rock_cycle(source,source.completed_cycles,drop.world_position)
	check(scene.ground_resources.drops.size()==1,"Repeated world callback deduplicated")
	var camera: Camera3D = scene.get_node("World/Camera3D")
	camera.position=Vector3(50,30,12)
	camera.look_at(Vector3(30,0,-9))
	camera.set_zoom_distance(40 / (2 * tan(deg_to_rad(camera.fov / 2))))
	scene.resident_selection.select(actor.data)
	await capture("miner_ground_stone")
	# True phase dispatch; two miners choose distinct rocks in one shared region.
	scene.player_control.assign_work_area(actor.data.id,area.id)
	var second = scene.resident_runtimes[2]
	scene.player_control.assign_profession(second.data.id,P.MINER)
	scene.player_control.assign_work_area(second.data.id,area.id)
	actor.intents.abort_current(actor.intents.current_intent)
	second.intents.abort_current(second.intents.current_intent)
	actor.decision._deciding=false
	second.decision._deciding=false
	scene.game_time.total_minutes=419
	scene.game_time.debug_skip_minutes(1)
	actor.decision._deciding=true
	second.decision._deciding=true
	check(worker.rock!=null and second.get_node("Miner").rock!=null and worker.rock!=second.get_node("Miner").rock,"Real normal WORK dispatch and exclusive competition")
	walk(actor)
	walk(second)
	check(worker.mining and second.get_node("Miner").mining,"Two physical miners start")
	await capture("shared_area_miners")
	worker.abort(false)
	second.get_node("Miner").abort(false)
	# Real command/critical interrupt uses the existing forced-interrupt pipeline.
	check(worker.request_work(),"Action before command interrupt")
	walk(actor)
	var partial = worker.rock
	scene.game_time.debug_skip_minutes(7)
	check(scene.player_control.move_to(actor.data.id,C.to_sim(Vector3(16,0,-4))),"PlayerCommand interrupts miner")
	check(partial.work_done==7 and partial.reservation_owner_id.is_empty() and worker.rock==null,"Command retains partial and releases claim")
	actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
	check(worker.request_work(),"Action before critical interrupt")
	walk(actor)
	var critical_source = worker.rock
	scene.game_time.debug_skip_minutes(2)
	actor.decision._deciding=false
	actor.data.fatigue=100
	actor.decision._deciding=true
	check(critical_source.reservation_owner_id.is_empty() and worker.rock==null and actor.intents.current_intent.reason_id==&"critical_sleep","Critical fatigue pipeline interrupts mining")
	actor.data.fatigue=0
	actor.intents.abort_current(actor.intents.current_intent)
	# Revision invalidates even in same frame; no stale target.
	worker.has_work()
	area.update(C.to_sim(Vector3(55,0,30)),C.length_to_sim(1))
	check(not worker.request_work(),"Same-frame area revision invalidates cache")
	area.update(C.to_sim(Vector3(30,0,-9)),C.length_to_sim(15))
	check(worker.request_work(),"Restored area available")
	walk(actor)
	var final_source = worker.rock
	final_source.stock=1
	final_source.work_done=59
	scene.work_areas.remove(area.id)
	scene.game_time.debug_skip_minutes(1)
	check(final_source.stock==0 and final_source not in scene.rocks and not scene.rock_views.has(final_source.id),"Captured action finishes after area deletion and depletes rock")
	check(scene.navigation.is_world_walkable(C.to_world(final_source.position)),"Last yield removes hard blocker")
	check(scene.ground_resources.drops.size()==2,"Last resource survives removed source")
	# Reentrant interrupt at completion: receipt publication and XP still finish exactly once.
	var fresh_area = scene.work_areas.create(C.to_sim(Vector3(30,0,-9)),C.length_to_sim(15))
	scene.player_control.assign_work_area(actor.data.id,fresh_area.id)
	check(worker.request_work(),"Reentrant test action")
	walk(actor)
	var edge = worker.rock
	edge.work_done=59
	var edge_callback := func():
		if edge.completed_cycles>0: worker.abort(false)
	edge.changed.connect(edge_callback)
	var before: int = scene.ground_resources.drops.size()
	var xp: int = actor.data.get_skill_xp(Skill.GATHERING)
	scene.game_time.debug_skip_minutes(1)
	check(scene.ground_resources.drops.size()==before+1 and actor.data.get_skill_xp(Skill.GATHERING)==xp+1 and worker.rock==null,"Completion-edge reentrant interrupt no duplication or lost yield")
	edge.changed.disconnect(edge_callback)
	# Generic logistics: Porter retrieves Ground STONE.
	var porter = scene.resident_runtimes[0]
	scene.player_control.assign_profession(porter.data.id,P.PORTER)
	porter.intents.abort_current(porter.intents.current_intent)
	var jobs = scene.logistics.collect_candidates(porter.data.id)
	check(not jobs.is_empty(),"Porter sees Ground STONE")
	var job = scene.logistics._claim_candidate(porter.data,jobs[0])
	check(job!=null and scene.logistics.start_claimed_job(job,porter.data.id),"Claim generic stone transport")
	walk(porter)
	scene.game_time.debug_skip_minutes(10)
	walk(porter)
	scene.game_time.debug_skip_minutes(10)
	check(scene.warehouse_data.resources.get_amount(R.STONE)==1,"Porter deposits stone into Town Center")
	await capture("porter_stone_delivered")
	# Mixed requirements use the unchanged Builder material executor.
	var definition = preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME)
	definition.construction_requirements = {R.LOG:1,R.STONE:1}
	definition.construction_work_required = 3
	var site = preload("res://scripts/building_instance.gd").new(&"mixed_site",definition,C.to_sim(Vector3(4,0,-12)),preload("res://scripts/building_instance.gd").State.UNDER_CONSTRUCTION)
	scene.buildings.append(site)
	scene._show_building(site)
	scene.ground_resources.create_drop(R.LOG,1,C.to_sim(Vector3(0,0,-9)))
	scene.ground_resources.create_drop(R.STONE,1,C.to_sim(Vector3(1,0,-9)))
	var builder = scene.resident_runtimes[1]
	scene.player_control.assign_profession(builder.data.id,P.BUILDER)
	builder.intents.abort_current(builder.intents.current_intent)
	check(builder.builder.request_work(),"Builder accepts mixed LOG/STONE site")
	walk(builder)
	scene.game_time.debug_skip_minutes(10)
	walk(builder)
	scene.game_time.debug_skip_minutes(10)
	builder.builder.abort("test boundary")
	builder.intents.abort_current(builder.intents.current_intent)
	check(site.get_uncovered_construction_amount(R.LOG)==0,"Mixed site receives LOG")
	check(builder.builder.request_work(),"Builder requests second mixed material")
	walk(builder)
	scene.game_time.debug_skip_minutes(10)
	walk(builder)
	scene.game_time.debug_skip_minutes(10)
	check(site.get_uncovered_construction_amount(R.STONE)==0,"Mixed site receives STONE through generic source")
	builder.builder.abort("test boundary")
	builder.intents.abort_current(builder.intents.current_intent)
	check(builder.builder.request_work(),"Mixed site starts construction")
	walk(builder)
	scene.game_time.debug_skip_minutes(3)
	check(site.is_built(),"Mixed site completes existing lifecycle")
	scene.free()
	print("Free mining: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
