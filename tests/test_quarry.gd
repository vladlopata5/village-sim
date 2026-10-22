extends SceneTree
const Categories = preload("res://scripts/resource_category.gd").Type
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Builder = preload("res://scripts/resident_builder_controller.gd")
const Job = preload("res://scripts/haul_job.gd")
const Skill = preload("res://scripts/skill_type.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
var world: Node
var rendered := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(4000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func clear(actor: Node) -> void:
	actor.intents.abort_current(actor.intents.current_intent)
	for need in actor.data.needs.values(): need.value=0
func decision(actor: Node) -> void:
	clear(actor)
	actor.decision._deciding=false
	actor.decision.request_decision("quarry_fixture")
	await preload("res://tests/ai_queue_fixture.gd").drain(world)
	actor.decision._deciding=true
func capture(name: String) -> void:
	if not rendered: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/quarry-generic-logistics/"+name+".png")
func run() -> void:
	rendered = "--rendered" in OS.get_cmdline_user_args()
	world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.view.set_physics_process(false)
		clear(actor)
		for need in actor.data.needs.values(): need.base_weight=0
	await physics_frame
	world.game_time.total_minutes=419
	world.game_time.debug_skip_minutes(1) # Real phase event synchronizes schedule and AI.
	var miner = world.resident_runtimes[3]
	var controller = miner.get_node("Miner")
	var definition = Definition.for_type(BT.QUARRY)
	check(definition.construction_requirements=={R.LOG:8,R.STONE:4} and definition.construction_work_required==180 and definition.max_builders==2,"Quarry approved mixed recipe/work/builders")
	check(definition.worker_capacity==1 and definition.work_radius==15 and definition.local_resource_capacity==12,"Quarry worker/radius/buffer")
	check(definition.footprint_cells==Vector2i(12,8) and definition.allows_internal_import(R.STONE) and not definition.allows_external_import(R.STONE) and definition.allows_external_export(R.STONE),"Footprint and separate policies")
	var layout = preload("res://scripts/world_3d/building_layouts_3d.gd").create(definition)
	check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(layout,definition),"Authored worker/courier/entrance/construction slots valid")
	layout.free()
	check(world.player_control.assign_profession(miner.data.id,P.MINER),"FREE miner profession without Quarry")
	var area = world.work_areas.create(C.to_sim(Vector3(30,0,-9)),C.length_to_sim(15))
	world.player_control.assign_work_area(miner.data.id,area.id)
	for cycle in range(4):
		await decision(miner)
		check(controller.rock!=null,"Real normal FREE WORK selects rock")
		walk(miner)
		world.game_time.debug_skip_minutes(60)
	check(Stacks.total(world.ground_resources)==4 and miner.data.inventory.amount==0,"Four actual FREE cycles produce ground STONE")
	# Natural wood fixture: four real FREE chops, no free building materials.
	var lumberjack = world.resident_runtimes[2]
	world.player_control.assign_profession(lumberjack.data.id,P.LUMBERJACK)
	var forest = world.work_areas.create(C.to_sim(Vector3(-29,0,-9)),C.length_to_sim(15))
	world.player_control.assign_work_area(lumberjack.data.id,forest.id)
	world.game_time.total_minutes=420
	for cycle in range(4):
		await decision(lumberjack)
		check(lumberjack.get_node("Lumberjack").tree!=null,"Normal FREE forestry supplies recipe LOG")
		walk(lumberjack)
		world.game_time.debug_skip_minutes(60)
	world.game_time.total_minutes=420
	world.placement.select(definition)
	world.placement.update_world_position(Vector3(29,0,1))
	var quarry = world.placement.confirm()
	check(quarry!=null and not quarry.is_built() and quarry in world.buildings,"Player placement creates real Quarry site")
	if quarry==null:
		world.free()
		quit(1)
		return
	check(not world.player_control.assign_workplace(miner.data.id,quarry.id) and miner.data.work_area_id==area.id,"Unbuilt assignment rejected atomically")
	# Collect distant extraction output locally, then build from real global stock.
	var porter = world.resident_runtimes[0]
	check(world.player_control.set_warehouse_category_quota(world.warehouse_data.id,Categories.STONE,8).ok and world.player_control.set_warehouse_category_quota(world.warehouse_data.id,Categories.LOG,12).ok,"Reallocate two quota places for all twelve extracted LOG within total 100")
	for dropped in world.ground_resources.drops.duplicate():
		for unit in range(dropped.amount):
			world.game_time.total_minutes=420
			porter.commands.move_to(dropped.world_position)
			walk(porter)
			check(world._request_work(porter),"Local Porter claims real extraction output")
			walk(porter); world.game_time.debug_skip_minutes(10)
			walk(porter); world.game_time.debug_skip_minutes(10)
	var builder = world.resident_runtimes[1]
	world.game_time.total_minutes=420
	world.player_control.assign_profession(builder.data.id,P.BUILDER)
	clear(builder)
	check(builder.builder.request_work(),"Builder starts ordinary mixed-material workflow")
	for step in range(16000):
		preload("res://tests/handling_test_step.gd").move_3d(builder,0.05)
		if builder.builder.phase==Builder.Phase.BUILDING: break
	check(quarry.get_delivered_amount(R.LOG)==0 and quarry.get_delivered_amount(R.STONE)==4,"First stage receives only extracted stone before timber demand")
	for task in range(80):
		if quarry.is_built():break
		if builder.builder.phase==Builder.Phase.NONE:check(builder.builder.request_work(),"Ordinary request resumes staged Quarry")
		if builder.builder.phase==Builder.Phase.BUILDING:
			var minutes: int=mini(quarry.current_work_remaining(),Balance.BUILDER_WORK_CYCLE_MINUTES-builder.builder.work_minutes)
			world.game_time.total_minutes+=minutes;builder.builder._on_minute(world.game_time.total_minutes)
		else:
			var old_phase: int=builder.builder.phase
			for step in range(16000):
				if builder.builder.phase!=old_phase:break
				preload("res://tests/handling_test_step.gd").move_3d(builder,.05)
	check(quarry.get_delivered_amount(R.LOG)==8 and quarry.get_delivered_amount(R.STONE)==4,"All extracted LOG and STONE physically delivered across stages")
	check(quarry.is_built() and quarry.construction_progress==180,"Existing incremental construction completes Quarry")
	check(quarry.resources.get_capacity(R.STONE)==12 and world.logistics._buildings.get(quarry.id)==quarry,"Built activation creates normal buffer and registry")
	clear(miner)
	check(world.player_control.assign_workplace(miner.data.id,quarry.id) and miner.data.work_area_id.is_empty(),"FREE -> BUILDING assignment")
	check(not world.player_control.assign_workplace(lumberjack.data.id,quarry.id),"Second Quarry worker rejected")
	world.game_time.total_minutes=420
	await decision(miner)
	check(controller.mining or controller.rock!=null,"Normal BUILDING AI selects MINE")
	world.resident_selection.select_building(quarry)
	world.building_card_view()._refresh()
	check(world.building_card_view().get_node("%NaturalProgress").text.contains("%d / %d" % [controller.rock.work_done,controller.rock.work_required]),"Quarry card reads captured active rock progress")
	check(quarry.resources.get_reserved_in(R.STONE)==0,"MINE does not reserve future output")
	walk(miner)
	world.game_time.debug_skip_minutes(60)
	check(miner.data.inventory.amount==0 and controller.rock==null,"MINE yields Ground and ends ordinary action")
	check(controller.has_work() and controller._available.kind==&"COLLECT","Next normal work prefers COLLECT")
	check(controller.request_work(),"Generic internal collection starts")
	var collect = world.logistics.get_job(miner.data.id)
	world.resident_selection.select_building(quarry)
	world.building_card_view()._refresh()
	check("Камень" in world.building_card_view().resources_label.text,"Real BuildingCard describes actual stone resource")
	check(collect!=null and collect.admission==Job.Admission.INTERNAL and quarry.resources.get_reserved_in(R.STONE)==1,"Owned inbound created only at COLLECT")
	walk(miner)
	world.game_time.debug_skip_minutes(10)
	walk(miner)
	check(miner.view._marker!=null and miner.view._marker.purpose==1,"Physical portal arrival acquires interior COURIER")
	world.resident_selection.select(miner.data)
	var camera: Camera3D = world.get_node("World/Camera3D")
	camera.position=Vector3(45,30,20)
	camera.look_at(Vector3(29,0,-2))
	camera.set_zoom_distance(30 / (2 * tan(deg_to_rad(camera.fov / 2))))
	await capture("quarry_internal_courier")
	world.game_time.debug_skip_minutes(10)
	check(collect.state==Job.State.COMPLETED and quarry.resources.get_amount(R.STONE)==1 and miner.view._marker==null,"Unload commits and exits portal")
	quarry.resources.add(R.STONE,11)
	check(controller.best_task().kind==&"EXPORT" and controller.best_target().is_empty(),"Full buffer suppresses MINE and selects EXPORT")
	check(controller.has_work() and controller.request_work(),"Generic worker STONE export starts")
	var export_job = world.logistics.get_job(miner.data.id)
	walk(miner)
	world.game_time.debug_skip_minutes(10)
	check(miner.data.inventory.amount==1,"Export loads from own buffer inside courier slot")
	world.player_control.assign_work_area(miner.data.id,area.id)
	walk(miner)
	world.game_time.debug_skip_minutes(10)
	check(export_job.state==Job.State.COMPLETED and world.warehouse_data.resources.get_amount(R.STONE)==1,"Captured EXPORT delivers to Town Center after reassignment")
	check(quarry.resources.get_amount(R.STONE)==11,"EXPORT freed one place")
	world.player_control.assign_workplace(miner.data.id,quarry.id)
	check(controller.best_task().kind==&"MINE","Mining resumes after freeing room")
	world.resident_selection.select_building(quarry)
	await capture("quarry_built_buffer")
	check(miner.data.get_skill_xp(Skill.GATHERING)==5,"Only completed mining cycles award extraction XP")
	world.free()
	print("Quarry: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
