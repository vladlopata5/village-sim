extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const A = preload("res://scripts/work_area.gd")
const T = preload("res://scripts/tree_data.gd")
const R = preload("res://scripts/resource_type.gd").Type
const Locations = preload("res://scripts/world_3d/tree_locations_3d.gd")
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
	for step in range(1400):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func capture(name: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/free-forestry/"+name+".png")
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
	var worker = actor.get_node("Lumberjack")
	var counted := CountedLocations.new()
	counted.navigation = scene.navigation
	worker.locations = counted
	check(actor.data.work_area_id.is_empty(),"New resident area is empty")
	check(scene.player_control.assign_profession(actor.data.id,P.LUMBERJACK),"Profession without hut allowed")
	scene.game_time.total_minutes = 420
	check(not actor.decision._has_work(),"No area means no WORK")
	actor.data.work_area_id = &"missing"
	check(not actor.decision._has_work(),"Missing area safely unavailable")
	var area = scene.work_areas.create(C.to_sim(Vector3(-29,0,-9)),C.length_to_sim(15))
	check(area.contains(area.center+Vector2(375,0)) and not area.contains(area.center+Vector2(375.01,0)),"Circle boundary in simulation units")
	check(C.to_world(area.center)==Vector3(-29,0,-9) and C.length_to_world(area.radius)==15,"Coordinate bridge and fixed radius")
	check(scene.player_control.assign_work_area(actor.data.id,area.id),"Assign existing area")
	check(actor.data.work_location_id.is_empty() and actor.data.work_area_id==area.id,"Exclusive FREE references")
	check(not scene.player_control.assign_work_area(actor.data.id,&"missing") and actor.data.work_area_id==area.id,"Failed area assignment preserves previous")
	check(not scene.player_control.assign_workplace(actor.data.id,&"missing") and actor.data.work_area_id==area.id,"Failed workplace preserves area")
	counted.queries = 0
	check(worker.has_work(),"Area exposes CHOP")
	var picked = worker._available_task.tree
	check(worker.request_work() and worker.tree==picked,"One-use availability starts same tree")
	check(counted.queries==1,"Availability/request reuse one region query")
	check(worker.hut==null and worker.kind==&"CHOP" and not worker.chopping,"Free claim before travel; no hut")
	walk(actor)
	check(worker.chopping,"Physical approach begins chopping")
	scene.player_control.clear_work_assignment(actor.data.id)
	check(worker.chopping and picked.reservation_owner_id==StringName(actor.data.id),"Clear assignment does not interrupt committed chop")
	scene.game_time.debug_skip_minutes(17)
	worker.abort(false)
	check(picked.work_done==17 and picked.reservation_owner_id.is_empty(),"Interrupt preserves partial work and releases tree")
	scene.player_control.assign_work_area(actor.data.id,area.id)
	actor.intents.abort_current(actor.intents.current_intent)
	check(worker.request_work(),"Resume extraction")
	walk(actor)
	var completing = worker.tree
	scene.player_control.clear_work_assignment(actor.data.id)
	scene.game_time.debug_skip_minutes(60-int(completing.work_done))
	check(completing.state==T.State.DEPLETED and scene.ground_resources.drops.size()==3,"Exactly three LOG on completion")
	check(actor.data.inventory.amount==0 and worker.kind.is_empty(),"FREE leaves Ground, no collect/export/plant")
	check(actor.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.GATHERING)==1,"Existing extraction XP awarded once")
	var drops_before: int = scene.ground_resources.drops.size()
	scene._deplete_tree(completing)
	check(scene.ground_resources.drops.size()==drops_before,"No duplicate yield")
	var camera: Camera3D = scene.get_node("World/Camera3D")
	camera.position=Vector3(-9,30,11)
	camera.look_at(Vector3(-29,0,-9))
	camera.set_zoom_distance(40 / (2 * tan(deg_to_rad(camera.fov / 2))))
	scene.resident_selection.select(actor.data)
	await capture("free_ground_logs")
	# Shared area and normal phase decision (no direct request_work).
	scene.player_control.assign_work_area(actor.data.id,area.id)
	actor.intents.abort_current(actor.intents.current_intent)
	var second = scene.resident_runtimes[2]
	scene.player_control.assign_profession(second.data.id,P.LUMBERJACK)
	scene.player_control.assign_work_area(second.data.id,area.id)
	check(second.data.work_area_id==actor.data.work_area_id,"Two workers share single area ID")
	actor.decision._deciding=false
	second.decision._deciding=false
	scene.game_time.total_minutes=419
	scene.game_time.debug_skip_minutes(1)
	var other = second.get_node("Lumberjack")
	check(worker.tree!=null and other.tree!=null and worker.tree!=other.tree,"Normal 07:00 AI selects different claimed trees")
	walk(actor)
	walk(second)
	check(worker.chopping and other.chopping,"Both normal AI workers physically chop")
	await capture("shared_area_chopping")
	actor.decision._deciding=true
	second.decision._deciding=true
	worker.abort(false)
	other.abort(false)
	actor.intents.abort_current(actor.intents.current_intent)
	second.intents.abort_current(second.intents.current_intent)
	# Cache invalidation and deletion do not invalidate an active source.
	check(worker.has_work(),"Candidate available before area edit")
	var far_area = scene.work_areas.create(C.to_sim(Vector3(40,0,25)),area.radius)
	scene.player_control.assign_work_area(actor.data.id,far_area.id)
	check(not worker.request_work(),"Same-frame reassignment invalidates cached tree")
	scene.player_control.assign_work_area(actor.data.id,area.id)
	check(worker.has_work(),"Availability restored before revision test")
	area.update(C.to_sim(Vector3(40,0,25)),area.radius)
	check(not worker.request_work(),"Same-frame revision invalidates cached tree")
	area.update(C.to_sim(Vector3(-29,0,-9)),area.radius)
	check(worker.request_work(),"Edited area restored")
	var claimed = worker.tree
	scene.work_areas.remove(area.id)
	walk(actor)
	check(worker.chopping and worker.tree==claimed,"Area deletion permits committed chop")
	worker.abort(false)
	actor.intents.abort_current(actor.intents.current_intent)
	check(not worker.has_work(),"Deleted area prevents next work")
	# Hut compatibility and mode switching.
	var hut = preload("res://tests/forestry_fixture.gd").hut(scene)
	check(scene.player_control.assign_workplace(actor.data.id,hut.id) and actor.data.work_area_id.is_empty(),"FREE to BUILDING replaces references")
	var replacement = scene.work_areas.create(C.to_sim(Vector3(-29,0,-9)),C.length_to_sim(15))
	check(worker.best_task().kind==&"COLLECT" and worker.request_work(),"Hut retains Ground collection priority")
	walk(actor)
	scene.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1,"Existing hut loading picks one LOG")
	scene.player_control.assign_work_area(actor.data.id,replacement.id)
	walk(actor)
	scene.game_time.debug_skip_minutes(10)
	check(hut.resources.get_amount(R.LOG)==1 and actor.data.inventory.amount==0 and hut.resources.get_reserved_in(R.LOG)==0,"BUILDING to FREE finishes old courier without lost cargo")
	check(worker.best_task().kind==&"CHOP","Next action uses FREE policy despite loose Ground LOG")
	scene.player_control.assign_workplace(scene.resident_runtimes[0].data.id,hut.id)
	check(not scene.player_control.assign_workplace(second.data.id,hut.id) and second.data.work_area_id==area.id,"Full hut does not erase old area reference")
	scene.resident_selection.select(actor.data)
	var card = scene.resident_card_view()
	card._refresh()
	check("Свободная область" in card.work_place_label.text and card.area_choice.item_count>1,"Card shows context and reusable area")
	# Tool confirmation/cancellation and no forced command.
	scene._start_work_area(actor.data.id)
	scene.handle_world_click(MOUSE_BUTTON_LEFT,{"position":Vector3(-29,0,-9)})
	check(scene.work_area_tool.locked and scene.area_confirm.visible,"Map click freezes preview pending confirm")
	await capture("area_preview")
	scene._confirm_work_area()
	check(not scene.work_area_tool.active() and actor.data.work_area_id!=replacement.id,"Confirm creates real assigned area")
	var count: int = scene.work_areas.all().size()
	scene._start_work_area(actor.data.id)
	scene._cancel_work_area()
	check(scene.work_areas.all().size()==count,"Cancel preview creates nothing")
	# Builder source-selection fixture is deliberately single-resource.
	var builder = scene.resident_runtimes[1].builder
	var loose_plank = scene.ground_resources.create_drop(R.PLANK,1,C.to_sim(Vector3(-24,0,-8)))
	var build_definition = preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.HOME)
	build_definition.construction_requirements = {R.PLANK:1}
	var site = preload("res://scripts/building_instance.gd").new(&"ground_source_site",build_definition,C.to_sim(Vector3(-17,0,-16)),preload("res://scripts/building_instance.gd").State.UNDER_CONSTRUCTION)
	scene.buildings.append(site)
	scene._show_building(site)
	var material: Dictionary = builder._material_trip(site)
	check(not material.is_empty() and material.reference.kind==1 and material.reference.id==loose_plank.id,"Existing Builder chooses Ground PLANK under unchanged construction rules")
	# Ground pickup through the existing Porter flow.
	var porter = scene.resident_runtimes[0]
	scene.player_control.assign_workplace(porter.data.id,scene.warehouse_data.id)
	var candidates: Array = scene.logistics.collect_candidates(porter.data.id).filter(func(c): return c.source_ref.kind==1 and c.resource_type==R.LOG)
	check(not candidates.is_empty(),"Porter sees free-extraction Ground LOG")
	if not candidates.is_empty():
		var job = scene.logistics._claim_candidate(porter.data,candidates[0])
		check(job!=null and scene.logistics.start_claimed_job(job,porter.data.id),"Existing Porter claims ground haul")
		walk(porter)
		scene.game_time.debug_skip_minutes(10)
		walk(porter)
		scene.game_time.debug_skip_minutes(10)
		check(job.state==job.State.COMPLETED and porter.data.inventory.amount==0,"Porter physically delivers free LOG")
		await capture("porter_delivered")
	check(worker.request_work(),"Free action available before transition to hut")
	var captured = worker.tree
	check(scene.player_control.assign_workplace(actor.data.id,hut.id),"FREE to BUILDING during active trip")
	walk(actor)
	check(worker.chopping and worker.tree==captured and worker.committed_context.hut==null,"Active free chop retains captured context after hut assignment")
	worker.abort(false)
	scene.free()
	print("Free forestry: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
