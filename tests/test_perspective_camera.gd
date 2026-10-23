extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const OUT="C:/Users/SW/Documents/Codex/outputs/e6-perspective-camera/"
var failures:=0
var checks:=0
var records:=[]
var world: Node
var camera: Camera3D
var baseline:=false
var rendered:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func settle() -> void: await physics_frame;await process_frame;await process_frame
func focus() -> Vector3:
	var middle:=root.get_visible_rect().size/2
	return Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(middle),camera.project_ray_normal(middle))
func capture(label: String) -> void:
	await settle()
	var item:={"name":label,"projection":camera.projection,"transform":str(camera.global_transform),"focus":str(focus()),"fov":camera.fov,"size":camera.size,"center_span":camera.unproject_position(Vector3(2,2,0)).distance_to(camera.unproject_position(Vector3(-2,2,0))),"window":str(root.size),"viewport":str(root.get_visible_rect()),"ui":str(world.game_ui.info_panel.get_global_rect())}
	if rendered:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUT+label+".png")==OK,"Capture "+label)
	records.append(item)
func click_world(point: Vector3) -> void:
	var screen:=camera.unproject_position(point)
	check(not world.game_ui.pointer_blocked(screen),"Projected world point outside UI")
	F.click_at(self,screen)
	world._physics_process(0)
func run() -> void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	rendered="--rendered" in OS.get_cmdline_user_args()
	for resolution in [Vector2i(1920,1080),Vector2i(1600,900)]:
		root.size=resolution
		world=F.create(self)
		world.set_process(false);world.set_physics_process(false)
		camera=world.get_node("World/Camera3D")
		camera.set_process(false)
		await settle()
		var original:=camera.global_transform
		var original_size:=camera.size
		var initial_focus:=focus()
		var label:="%s_%d_" % ["orthographic" if baseline else "perspective",resolution.x]
		await capture(label+"initial")
		var old:=Camera3D.new()
		world.get_node("World").add_child(old)
		old.projection=Camera3D.PROJECTION_ORTHOGONAL;old.size=44
		old.global_transform=Transform3D(camera.global_basis,Vector3(30,50.56,30))
		var center: Vector3=preload("res://scripts/world_3d/world_coordinates.gd").to_world(world.warehouse_data.position)+Vector3(0,2,0)
		var old_width:=old.unproject_position(center+Vector3(2,0,0)).distance_to(old.unproject_position(center-Vector3(2,0,0)))
		var new_width:=camera.unproject_position(center+Vector3(2,0,0)).distance_to(camera.unproject_position(center-Vector3(2,0,0)))
		records[-1]["town_scale_ratio"]=new_width/old_width
		records[-1]["town_screen_old"]=str(old.unproject_position(center))
		records[-1]["town_screen_new"]=str(camera.unproject_position(center))
		check(new_width/old_width>0.85 and new_width/old_width<1.15,"Real Town Center central scale comparable to original")
		old.free()
		if not baseline:
			check(camera.projection==Camera3D.PROJECTION_PERSPECTIVE,"Canonical uses perspective")
			check(absf(camera.rotation_degrees.x+50)<0.001 and absf(camera.rotation_degrees.y-45)<0.001,"Original pitch/yaw")
			check(camera.fov==35 and is_equal_approx(camera.near,0.1) and camera.far==500,"Moderate constant FOV and clipping")
			check(initial_focus.distance_to(Vector3.ZERO)<0.02,"Original ground interest point")
			check(absf(camera.get_zoom_distance()-76.0)<0.001,"Calibrated center-plane scale")
		for zoom in [1,-1]:
			camera.zoom(1000.0*zoom)
			if not baseline:
				check(is_equal_approx(camera.get_zoom_distance(),camera.min_distance if zoom==1 else camera.max_distance),"Zoom clamps real distance")
				check(focus().distance_to(initial_focus)<0.001 and camera.fov==35,"Zoom preserves focus and FOV")
				check(camera.global_position.y>=camera.min_distance*sin(deg_to_rad(50.0))-0.001,"Camera stays above ground at the configured minimum distance")
			await capture(label+("near" if zoom==1 else "far"))
			camera.global_transform=original;camera.size=original_size
		if not baseline:
			for yaw in [45.0,-25.0,135.0]:
				for distance in [camera.min_distance,camera.get_zoom_distance(),camera.max_distance]:
					camera.global_transform=original
					camera.orbit_to_yaw(yaw)
					check(focus().distance_to(initial_focus)<0.001,"Yaw orbit retains focus")
					camera.set_zoom_distance(distance)
					var mouse:=Vector2(620,300)
					var grabbed: Vector3=Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
					var drag:=Vector2(35,22)
					camera.drag_pan(drag,mouse+drag)
					check(camera.unproject_position(grabbed).distance_to(mouse+drag)<0.002,"Perspective map point follows actual off-center cursor")
					var before:=camera.global_position
					camera.pan(Vector2.RIGHT,0.25)
					check(is_equal_approx(camera.global_position.distance_to(before),5),"Original keyboard speed at all distances")
			camera.global_transform=original
			camera.orbit_to_yaw(-25)
		else:
			camera.rotation_degrees.y=-25
			camera.global_position=initial_focus+camera.global_basis.z*(original.origin.distance_to(initial_focus))
		await capture(label+"rotated")
		camera.global_transform=original;camera.size=original_size
		var actor=world.resident_runtimes[0]
		var actor_screen:=camera.unproject_position(actor.view.global_position+Vector3(0,0.9,0))
		F.click_at(self,actor_screen);world._physics_process(0)
		check(world.resident_selection.selected_resident==actor.data,"Real perspective resident ray selection")
		world.resident_selection.clear()
		click_world(preload("res://scripts/world_3d/world_coordinates.gd").to_world(world.warehouse_data.position)+Vector3(0,2.5,0))
		check(world.resident_selection.selected_building==world.warehouse_data,"Real Town Center ray selection")
		world.resident_selection.clear()
		var original_camera:=camera.global_transform
		F.click(self,world.construction_panel.collapse_button)
		await settle()
		world.construction_panel.catalogue.select_category(&"settlement")
		await settle()
		F.click(self,world.construction_panel.catalogue.tile_for_type(T.HOME))
		F.key(self,KEY_R)
		var point:=Vector3(-10,0,8)
		var screen:=camera.unproject_position(point)
		var ground: Dictionary=world.ground_pick(screen)
		check(ground.has("position") and ground.position.distance_to(point)<0.01,"Physical ground ray matches cursor point")
		world.placement.update_world_position(ground.position)
		world.building_ghost.refresh()
		await capture(label+"ghost")
		var count: int=world.buildings.size()
		click_world(point)
		check(world.buildings.size()==count+1 and world.placement.is_active() and world.placement.quarter_turns==1,"One perspective click registers site and rearms rotated tool")
		var site=world.buildings[-1]
		click_world(Vector3(-10,0,-2))
		check(world.buildings.size()==count+2 and world.buildings[-1].quarter_turns==1,"Separate second click creates exactly second site")
		await capture(label+"two_sites")
		world._cancel_active_world_tool()
		world.construction_panel.set_collapsed(true)
		await settle()
		click_world(preload("res://scripts/world_3d/world_coordinates.gd").to_world(site.position)+Vector3.UP)
		check(world.resident_selection.selected_building==site,"Construction site ray selection")
		world.resident_selection.clear()
		world._select_road_tool()
		var road_point:=Vector3(7,0,1)
		F.click_at(self,camera.unproject_position(road_point));world._physics_process(0)
		check(world.roads.cells().size()>0,"Real road stroke paints cell")
		check(world.roads.contains(world.roads.geometry.world_to_cell(road_point)),"Road lies in cursor cell")
		await capture(label+"road")
		world._cancel_active_world_tool()
		world.player_control.assign_profession(actor.data.id,preload("res://scripts/resident_profession.gd").Type.LUMBERJACK)
		world._start_work_area(actor.data.id)
		var area_point:=Vector3(-12,0,-12)
		click_world(area_point)
		check(world.work_area_tool.locked and world.work_area_tool.preview.center.distance_to(preload("res://scripts/world_3d/world_coordinates.gd").to_sim(area_point))<0.1,"WorkArea center uses the cursor ground ray")
		F.key(self,KEY_ENTER)
		check(not actor.data.work_area_id.is_empty() and not world.work_area_tool.active(),"Real WorkArea confirmation assigns area")
		world.resident_selection.select(actor.data)
		world.game_ui.info_panel.set_expanded(true)
		await settle()
		var blue_rect: Rect2=world.game_ui.info_panel.get_global_rect()
		var count_after: int=world.buildings.size()
		F.click_at(self,blue_rect.get_center())
		F.click_at(self,blue_rect.get_center(),MOUSE_BUTTON_WHEEL_UP)
		await settle()
		check(camera.global_transform==original_camera and camera.fov==35 if not baseline else camera.global_transform==original_camera,"UI click/wheel cannot affect camera")
		check(world.buildings.size()==count_after and world.resident_selection.selected_resident==actor.data,"Blue click cannot select or place in world")
		await capture(label+"resident_ui")
		world.free();await process_frame
	var file:=FileAccess.open(OUT+("baseline" if baseline else "camera")+("-rendered" if rendered else "-headless")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"\t"))
	print("Camera QA: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
