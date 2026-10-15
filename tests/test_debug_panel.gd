extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const Definition = preload("res://scripts/building_definition.gd")
const Job = preload("res://scripts/haul_job.gd")
class CountedLogistics extends "res://scripts/logistics_controller.gd":
	var checked_candidates := 0
	func _routes_available(candidate: Candidate, point: Vector2) -> bool:
		checked_candidates+=1
		return super._routes_available(candidate,point)
var checks := 0
var failures := 0
var world: Node
var rendered := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event,true)
func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	root.push_input(event,true)
	event.pressed=false
	root.push_input(event,true)
func capture(label: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/debug-panel/"+label+".png")
func quiet(actor: Node) -> void:
	actor.decision._deciding=true
	actor.view.set_physics_process(false)
	actor.intents.abort_current(actor.intents.current_intent)
	for need in actor.data.needs.values():
		need.value=0
		need.base_weight=0
func walk(actor: Node) -> void:
	for i in 4000:
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	world=load("res://scenes/main_3d.tscn").instantiate()
	world.logistics=CountedLogistics.new()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for actor in world.resident_runtimes: quiet(actor)
	var panel = world.developer_panel
	check(panel!=null and not panel.visible,"Development-only panel initially hidden")
	key(KEY_F10)
	check(panel.visible,"Real F10 opens")
	await process_frame
	await physics_frame
	await capture("panel")
	var tabs: TabContainer=panel.get_child(0).get_child(0).get_child(2)
	tabs.current_tab=1
	panel.resource_choice.select(panel.resource_choice.get_item_index(R.LOG))
	panel.resource_count.value=10
	await process_frame
	click(tabs.get_child(1).get_child(2).get_global_rect().get_center())
	await process_frame
	await capture("resources_tab")
	tabs.current_tab=2
	await capture("buildings_tab")
	tabs.current_tab=3
	await capture("time_tab")
	tabs.current_tab=1
	check(panel.active() and not world.placement.is_active() and not world.road_tool.active and not world.work_area_tool.active(),"Exclusive debug placement mode")
	var before: int = world.ground_resources.drops.size()
	click(panel.get_global_rect().position+Vector2(25,20))
	await physics_frame
	check(world.ground_resources.drops.size()==before and world._clicks.is_empty(),"UI clicks do not spawn or queue world command")
	key(KEY_ESCAPE)
	check(not panel.active(),"Escape cancels")
	panel.begin_placement(&"resource",R.LOG,1)
	world.handle_world_click(MOUSE_BUTTON_LEFT,{})
	check(panel.active() and panel.status.text.contains("Нет попадания"),"Missing ground hit reports failure")
	click(Vector2(760,500))
	await physics_frame
	await process_frame
	check(world.ground_resources.drops.size()==before+1 and not panel.active(),"Ground click creates and ends mode")
	panel.begin_placement(&"building",Definition.for_type(BT.STORAGE),1)
	world.handle_world_click(MOUSE_BUTTON_LEFT,{"position":world.get_node("World/BuildingViews").get_child(0).position})
	check(panel.active() and not panel.status.text.is_empty(),"Invalid overlap reports reason and stays active")
	key(KEY_F10)
	check(not panel.visible and not panel.active(),"F10 closes and cancels")
	world._select_road_tool()
	panel.begin_placement(&"resource",R.STONE,1)
	check(not world.road_tool.active,"Starting debug placement cancels roads")
	world._select_building_definition(Definition.for_type(BT.HOME))
	check(not panel.active() and world.placement.is_active(),"Building mode cancels debug placement")
	world.placement.cancel()
	# Full debug-spawned logistics settlement, ordinary AI and generic executor.
	var service = world.debug_spawn
	var result: Dictionary = service.spawn_building(Vector3(-15,0,15),Definition.for_type(BT.STORAGE))
	check(result.ok,"Debug Storage placed")
	var storage = result.objects[0]
	var workers: Array = service.spawn_residents(Vector3(-15,0,10),2,P.PORTER).objects
	for data in workers:
		check(world.player_control.assign_workplace(data.id,storage.id),"Normal explicit own Storage assignment")
		quiet(world.get_resident_runtime(data))
	var nav_before: int = world.navigation.revision
	var logs: Array = service.spawn_resources(Vector3(-15,0,5),100,R.LOG).objects
	check(logs.size()==100 and world.navigation.revision==nav_before,"100 Ground LOG without navigation edits")
	world.game_time.total_minutes=419
	world.game_time.debug_skip_minutes(1)
	world.logistics.checked_candidates=0
	var selection_started := Time.get_ticks_usec()
	var jobs: Array = []
	for data in workers:
		var porter_actor = world.get_resident_runtime(data)
		porter_actor.decision._deciding=false
		porter_actor.decision.request_decision("debug_settlement")
		for frame in 3: await process_frame # Ordinary Porter choice is frame-budgeted.
		porter_actor.decision._deciding=true
		var job = world.logistics.get_job(data.id)
		check(job!=null,"Spawned Porter chooses ordinary WORK")
		jobs.append(job)
	print("Debug 2-Porter / 100 LOG decision interval: %.3f ms" % ((Time.get_ticks_usec()-selection_started)/1000.0))
	check(world.logistics.checked_candidates==4,"Exact lazy selection checks only first feasible per availability/claim on 100 LOG")
	check(jobs[0].source_ref.id!=jobs[1].source_ref.id and storage.resources.get_reserved_in(R.LOG)==2,"Distinct Ground claims and inbound reservations")
	for data in workers: walk(world.get_resident_runtime(data))
	world.game_time.debug_skip_minutes(10)
	check(workers.all(func(data): return data.inventory.amount==1) and logs.filter(func(drop): return drop in world.ground_resources.drops).size()==98,"Real loading/pickup removes exactly two Ground units")
	world.resident_selection.select(workers[0])
	await capture("porter_carrying")
	for data in workers: walk(world.get_resident_runtime(data))
	world.game_time.debug_skip_minutes(10)
	await process_frame # Released COURIER wakes the waiting second resident.
	world.game_time.debug_skip_minutes(10)
	check(jobs.all(func(job): return job.state==Job.State.COMPLETED),"Real generic delivery completes")
	check(storage.resources.get_amount(R.LOG)==2 and storage.resources.get_reserved_in(R.LOG)==0 and workers.all(func(data): return data.inventory.amount==0),"Cargo conservation and reservation cleanup")
	# Real spawned Miner attaches ordinary Quarry work, not a debug action.
	result=service.spawn_building(Vector3(30,0,-22),Definition.for_type(BT.QUARRY))
	check(result.ok,"Debug Quarry placed")
	var quarry = result.objects[0]
	var miner = service.spawn_residents(Vector3(30,0,-17),1,P.MINER).objects[0]
	check(world.player_control.assign_workplace(miner.id,quarry.id),"Miner assigned through normal capacity rules")
	var actor = world.get_resident_runtime(miner)
	quiet(actor)
	actor.decision._deciding=false
	actor.decision.request_decision("debug_quarry")
	await preload("res://tests/ai_queue_fixture.gd").drain(world)
	actor.decision._deciding=true
	check(actor.get_node("Miner").rock!=null,"Normal mining work candidate")
	walk(actor)
	check(actor.get_node("Miner").mining,"Spawned Miner physically reaches rock and starts mining")
	world.resident_selection.select(miner)
	await capture("quarry_work")
	# Time controls work paused; no extra clock or simulation rewind.
	world.game_time.toggle_pause()
	check(paused,"Pause")
	key(KEY_F10)
	check(panel.visible,"F10 works while paused")
	var existing: int = world.ground_resources.drops.size()
	panel.begin_placement(&"resource",R.STONE,1)
	world.resident_selection.clear()
	await process_frame
	click(Vector2(760,500))
	await physics_frame
	await process_frame
	check(world.ground_resources.drops.size()==existing+1,"Placement commands work while paused")
	world.game_time.set_speed(20)
	check(world.game_time.speed_multiplier==20,"Supported speed")
	world.game_time.toggle_pause()
	check(not paused,"Resume")
	world.free()
	print("Debug panel integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
