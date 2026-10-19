extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const B=preload("res://scripts/resident_builder_controller.gd")
const OUT="C:/Users/SW/Documents/Codex/outputs/e6-perspective-camera/"
var checks:=0
var failures:=0
var captures:=[]
var world: Node
var rendered:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle() -> void:await process_frame;await process_frame
func nodes(node: Node) -> int:
	var result:=1
	for child in node.get_children():result+=nodes(child)
	return result
func capture(label: String) -> void:
	if not rendered:return
	await settle();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"Capture "+label)
	captures.append({"name":label,"viewport":str(root.get_visible_rect()),"blue":str(world.game_ui.info_panel.get_global_rect()),"window":str(world.settlement_panel.get_global_rect())})
func click_world(point: Vector3) -> void:
	var camera: Camera3D=world.get_node("World/Camera3D")
	var screen:=camera.unproject_position(point)
	check(not world.game_ui.pointer_blocked(screen),"Integration point outside UI")
	F.click_at(self,screen);world._physics_process(0)
func assign(actor: Node, building: RefCounted, role: Variant) -> void:
	if role is int: check(world.player_control.assign_profession(actor.data.id,role),"Explicit profession before workplace selection")
	world.resident_selection.select_building(building)
	world.game_ui.open_window(&"residents")
	world.settlement_panel.preset_profession()
	await settle()
	await F.row_click(self,world.settlement_panel,actor.data.id)
	await settle()
	check(world.assignment_dialog.visible and world.assignment_dialog.buttons.has(role),"One contextual dialog offers correct role")
	await capture("e6_%d_assignment_%s" % [root.size.x,str(role)])
	F.click(self,world.assignment_dialog.buttons[role]);await settle()
	check(world.settlement_panel.visible and world.resident_selection.selected_building==building and not world.assignment_dialog.visible,"Success retains same roster and building")
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution;world=F.create(self)
		world.set_process(false);world.set_physics_process(false)
		await physics_frame;await settle()
		var camera: Camera3D=world.get_node("World/Camera3D")
		var original:=camera.global_transform
		await capture("e6_%d_idle"%resolution.x)
		F.click(self,world.construction_panel.collapse_button);await settle()
		world.construction_panel.catalogue.select_category(&"production");await settle()
		F.click(self,world.construction_panel.catalogue.tile_for_type(T.SAWMILL))
		F.key(self,KEY_R)
		click_world(Vector3(-10,0,8))
		var saw=world.buildings[-1]
		check(not saw.is_built() and saw.quarter_turns==1 and world.placement.is_active(),"Real rotated Sawmill site and continuing tool")
		await capture("e6_%d_site_and_ghost"%resolution.x)
		F.key(self,KEY_ESCAPE);await settle()
		world.construction_panel.set_collapsed(true)
		world.resident_selection.select_building(saw);world.game_ui.info_panel.set_expanded(true)
		await capture("e6_%d_construction"%resolution.x)
		world.debug_spawn.spawn_resources(Vector3(-15,0,8),7,R.LOG)
		world.debug_spawn.spawn_resources(Vector3(-15,0,4),6,R.STONE)
		var builder=world.resident_runtimes[3]
		check(world.player_control.assign_profession(builder.data.id,P.BUILDER),"Existing Builder profession")
		for cycle in range(8):
			if saw.is_built():break
			world.game_time.total_minutes=420
			check(world._request_work(builder),"Normal Builder work request")
			for leg in range(40):
				if builder.builder.phase not in [B.Phase.GOING_TO_SOURCE,B.Phase.CARRYING_TO_SITE]:break
				F.walk(world,builder)
			F.walk(world,builder)
			check(builder.builder.phase==B.Phase.BUILDING,"Physical construction materials and access")
			world.game_time.debug_skip_minutes(60)
		check(saw.is_built() and saw.construction_delivered=={R.LOG:6,R.STONE:6},"Authoritative construction completes exact recipe")
		check(&"production" in world.game_ui.info_panel._tabs,"Same BuildingInstance unlocks real production tab")
		var producer=world.resident_runtimes[1]
		var porter=world.resident_runtimes[0]
		await assign(producer,saw,P.SAWYER)
		await assign(porter,saw,P.PORTER)
		check(world.player_control.get_production_workers(saw.id).size()==1 and world.player_control.get_porters(saw.id).size()==1,"Actual distinct worker/Porter staffing")
		world.game_ui.close_window()
		check(world._request_work(porter),"Normal Porter claims remaining Ground LOG for own Sawmill")
		var job=world.logistics.get_job(porter.data.id)
		check(job!=null and job.resource_type==R.LOG and job.destination_location_id==saw.id,"Real Ground haul to production buffer")
		if job!=null:
			for leg in range(5):
				if not job.is_active():break
				F.walk(world,porter);preload("res://tests/handling_test_step.gd").finish(porter)
		check(saw.resources.get_amount(R.LOG)==1 and porter.data.inventory.amount==0,"Physical hauling deposits exactly one input")
		check(world._request_work(producer),"Normal Sawyer starts actual work")
		F.walk(world,producer)
		world.game_time.debug_skip_minutes(30)
		check(saw.resources.get_amount(R.LOG)==0 and saw.resources.get_amount(R.PLANK)==1,"Normal clock/production consumes one LOG and creates one PLANK")
		world.game_ui.info_panel.select_tab(&"production");await settle()
		await capture("e6_%d_production"%resolution.x)
		world.resident_selection.select_building(world.warehouse_data)
		world.game_ui.info_panel.select_tab(&"storage");await settle()
		await capture("e6_%d_storage"%resolution.x)
		var home=F.building(world,T.HOME,Vector3(-5,0,-12))
		await assign(producer,home,&"home")
		check(producer.data.home_location_id==home.id and world.building_card_view().housing_count.text.contains("1 / 4"),"Real housing updates same blue card")
		await assign(producer,home,&"clear_home")
		check(producer.data.home_location_id.is_empty(),"Existing clear-home action works")
		world.game_ui.close_window();world.resident_selection.clear();await settle()
		# Warm the same final presentation context before comparing allocations.
		world.resident_selection.select(producer.data)
		world.game_ui.info_panel.set_expanded(true)
		world.game_ui.open_window(&"residents")
		world.resident_selection.select_building(saw)
		world.game_ui.close_window();world.resident_selection.clear();await settle()
		var base_nodes:=nodes(world.game_ui)
		var need=producer.data.needs.values()[0]
		var subscriptions: int=need.changed.get_connections().size()
		var rows_created: int=world.settlement_panel.row_creation_count
		for cycle in range(100):
			world.resident_selection.select(producer.data)
			world.game_ui.info_panel.set_expanded(true)
			world.game_ui.open_window(&"residents")
			world.resident_selection.select_building(saw)
			world.game_ui.close_window();world.resident_selection.clear()
			await settle()
		print(JSON.stringify({"cycle_nodes_before":base_nodes,"cycle_nodes_after":nodes(world.game_ui),"connections_before":subscriptions,"connections_after":need.changed.get_connections().size()}))
		check(nodes(world.game_ui)==base_nodes and need.changed.get_connections().size()==subscriptions,"100 reopen/switch cycles have no GUI node/subscription growth")
		check(world.settlement_panel.row_creation_count==rows_created,"100 cycles preserve resident TreeItems")
		check(camera.global_transform==original,"Integrated gameplay and all UI transitions never move camera")
		world.resident_selection.select(producer.data);await settle()
		await capture("e6_%d_resident"%resolution.x)
		world.game_ui.open_window(&"residents");await settle()
		await capture("e6_%d_roster"%resolution.x)
		F.key(self,KEY_ESCAPE)
		F.key(self,KEY_F10);world.game_time.toggle_pause();await settle()
		await capture("e6_%d_f10_pause"%resolution.x)
		world.game_time.toggle_pause();F.key(self,KEY_F10)
		world.free();await settle()
	var file:=FileAccess.open(OUT+("integration-rendered" if rendered else "integration-headless")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures},"\t"))
	print("E6 integration: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
