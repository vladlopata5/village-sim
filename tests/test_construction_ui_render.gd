extends SceneTree
## Rendered E3 QA uses real GUI input, physics queries and production building work.
const OUT="C:/Users/SW/Documents/Codex/outputs/ui-e3-construction/"
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const B=preload("res://scripts/resident_builder_controller.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
var checks:=0
var failures:=0
var world: Node
var rendered:=false
var shots:=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func mouse(point: Vector2, button: MouseButton=MOUSE_BUTTON_LEFT, down: bool=true) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	root.push_input(motion,true)
	var event:=InputEventMouseButton.new()
	event.position=point;event.button_index=button;event.pressed=down
	root.push_input(event,true)
func click(control: Control) -> void:
	var point:=control.get_global_rect().get_center()
	mouse(point)
	mouse(point,MOUSE_BUTTON_LEFT,false)
func key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	root.push_input(event,true)
func capture(label: String) -> void:
	if not rendered: return
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"Capture "+label)
	var ui=world.game_ui
	shots.append({"name":label,"window":str(root.size),"viewport":str(root.get_visible_rect()),"stretch":str(root.get_stretch_transform()),"green":str(world.construction_panel.get_global_rect()),"blue":str(ui.info_panel.get_global_rect()),"residents":str(world.settlement_panel.get_global_rect()),"camera":str(world.get_node("World/Camera3D").global_transform)})
func world_click(point: Vector3) -> void:
	var camera: Camera3D=world.get_node("World/Camera3D")
	var screen:=camera.unproject_position(point)
	check(not world.game_ui.pointer_blocked(screen),"World confirmation lies outside UI: "+str(screen))
	mouse(screen)
	mouse(screen,MOUSE_BUTTON_LEFT,false)
	world._physics_process(0)
func walk(actor: Node) -> void:
	for step in range(16000):
		world.game_time.total_minutes=420
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving(): break
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution
		world=load("res://scenes/main_3d.tscn").instantiate()
		root.add_child(world)
		world.game_time.set_process(false)
		world.set_process(false)
		world.set_physics_process(false)
		world.game_time.total_minutes=420
		world.game_logger.console_enabled=false
		world.social_events.enabled=false
		for actor in world.resident_runtimes:
			actor.decision._deciding=true
			actor.intents.abort_current(actor.intents.current_intent)
			actor.view.set_physics_process(false)
			for need in actor.data.needs.values(): need.value=0;need.base_weight=0
		await physics_frame
		await settle()
		var prefix:="e3_%d_" % resolution.x
		var panel=world.construction_panel
		var catalog=panel.catalogue
		var info=world.game_ui.info_panel
		var camera: Camera3D=world.get_node("World/Camera3D")
		var before: Transform3D=camera.global_transform
		var zoom: float=camera.size
		check(panel.collapsed,"Collapsed initial menu")
		await capture(prefix+"collapsed")
		click(panel.collapse_button)
		await settle()
		for category in catalog.categories:
			click(catalog.category_buttons[category.id])
			await settle()
			check(catalog.category_id==category.id,"Actual category GUI "+category.title)
			for entry in category.entries:
				var tile: Button=catalog.tiles[entry.id]
				var title: Label=tile.get_node("Content/Title")
				check(tile.is_visible_in_tree() and tile.get_global_rect().encloses(title.get_global_rect()),"Readable permanent title "+entry.name)
			await capture(prefix+String(category.id))
		catalog.select_category(&"settlement")
		await settle()
		click(catalog.tile_for_type(T.HOME))
		check(info._preview_definition==world.placement.selected_definition and world.placement.selected_definition.type==T.HOME,"Actual Home tile and Definition preview")
		world.placement.update_world_position(Vector3(-7,0,8))
		world.building_ghost.refresh()
		await capture(prefix+"home_preview")
		click(catalog.tile_for_type(T.HOME))
		check(not world.placement.is_active(),"GUI active tile cancels")
		catalog.select_category(&"production")
		await settle()
		click(catalog.tile_for_type(T.SAWMILL))
		key(KEY_R)
		check(world.placement.quarter_turns==1,"Actual R rotates real footprint")
		# Central visible ground positions outside green/blue, no starting blockers.
		var first_point:=Vector3(-10,0,8)
		var second_point:=Vector3(-10,0,-2)
		world.placement.update_world_position(first_point)
		world.building_ghost.refresh()
		await capture(prefix+"sawmill_90")
		var count: int=world.buildings.size()
		world_click(first_point)
		check(world.buildings.size()==count+1 and world.placement.is_active() and world.placement.quarter_turns==1,"One GUI world click creates one site and preserves rotation")
		var first=world.buildings[-1]
		world_click(second_point)
		check(world.buildings.size()==count+2 and world.placement.is_active() and world.buildings[-1].quarter_turns==1,"Second GUI world click creates second site")
		check(world.player_control.get_building(first.id)==first and world.world_locations.get_view(first.id)!=null,"First real site registered through normal APIs")
		check(world.player_control.get_building(world.buildings[-1].id)==world.buildings[-1],"Second real site registered")
		world.building_ghost.refresh()
		await capture(prefix+"two_sites_invalid_ghost")
		world_click(second_point)
		check(world.buildings.size()==count+2 and not world.placement.can_place(),"GUI invalid ghost does not create another site")
		mouse(camera.unproject_position(first_point),MOUSE_BUTTON_RIGHT)
		world._physics_process(0)
		check(not world.placement.is_active() and not world.building_ghost.visible and info.day_summary.visible,"World RMB cancels without another site")
		await capture(prefix+"cancelled")
		catalog.select_category(&"objects")
		await settle()
		click(catalog.tiles[&"dirt_road"])
		check(world.road_tool.active and info.day_summary.visible,"Actual road tile uses road tool")
		var start:=camera.unproject_position(Vector3(7,0,1))
		mouse(start)
		world._physics_process(0)
		var gap: Vector2=panel.get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new()
		motion.position=gap;motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion,true)
		world._physics_process(0)
		check(world.road_tool._previous==null,"Entering catalogue ends road stroke")
		var cells_before: int=world.roads.cells().size()
		mouse(gap,MOUSE_BUTTON_LEFT,false)
		world._physics_process(0)
		check(not world._road_dragging and world.roads.cells().size()==cells_before,"UI release stops stroke without painting")
		check(cells_before>0,"Real road painted on ground")
		await capture(prefix+"road_ui_gap")
		key(KEY_ESCAPE)
		world.resident_selection.select(world.residents[0])
		info.set_expanded(true)
		await settle()
		check(not panel._contents.get_global_rect().intersects(info.get_global_rect()) and panel.strip.get_global_rect().intersects(info.get_global_rect()),"Catalogue avoids Blue; bottom strip intentionally underlays it")
		await capture(prefix+"green_blue_expanded")
		click(world.game_ui.residents_button)
		await settle()
		check(world.settlement_panel.visible and not world.settlement_panel.get_global_rect().intersects(info.get_global_rect()),"Existing Residents window and expanded blue coexist")
		await capture(prefix+"residents_window")
		key(KEY_ESCAPE)
		check(camera.global_transform==before and camera.size==zoom,"UI/placement/rotation/road/selection preserve camera")
		# Actual Ground sources, physical pickup/handling/delivery and Builder cycles.
		if resolution.x==1920:
			var logs: Dictionary=world.debug_spawn.spawn_resources(Vector3(-15,0,8),6,R.LOG)
			var stones: Dictionary=world.debug_spawn.spawn_resources(Vector3(-15,0,4),6,R.STONE)
			check(logs.created==6 and stones.created==6,"Normal Debug resource creation, exact Sawmill materials")
			var builder=world.resident_runtimes[1]
			check(world.player_control.assign_profession(builder.data.id,P.BUILDER),"Actual Builder assignment")
			world.resident_selection.select_building(first)
			info.set_expanded(true)
			for cycle in range(8):
				if first.is_built(): break
				world.game_time.total_minutes=420
				check(world._request_work(builder),"Normal Builder WORK request")
				for leg in range(40):
					if builder.builder.phase not in [B.Phase.GOING_TO_SOURCE,B.Phase.CARRYING_TO_SITE]: break
					walk(builder)
				walk(builder)
				check(builder.builder.phase==B.Phase.BUILDING,"Physical material pickup/delivery and construction access")
				world.game_time.debug_skip_minutes(10)
				if cycle==0: await capture(prefix+"builder_incremental_work")
				world.game_time.debug_skip_minutes(50)
			check(first.is_built() and first.construction_delivered=={R.LOG:6,R.STONE:6},"Actual supplied Sawmill completed through Builder work")
			check(first.construction_progress==first.definition.construction_work_required,"Required work reached in authoritative BuildingInstance")
			check(world.ground_resources.drops.is_empty() and builder.data.inventory.amount==0,"No material loss/duplication: twelve Ground units delivered, inventory empty")
			check(world.world_locations.get_view(first.id).building_data==first and &"production" in info._tabs,"Same site activates normal built presentation and E2 production tab")
			await capture(prefix+"sawmill_built")
		world.free()
		await settle()
	var file:=FileAccess.open(OUT+("rendered-measurements.json" if rendered else "headless-integration.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rendered":rendered,"checks":checks,"failures":failures,"captures":shots},"\t"))
	print("E3 rendered/integration: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
