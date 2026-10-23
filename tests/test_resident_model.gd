extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const Model=preload("res://scripts/world_3d/resident_model_3d.gd")
const Executor=preload("res://scripts/world_3d/resident_executor_3d.gd")
const Movement=preload("res://scripts/world_3d/grid_movement_3d.gd")
const Grid=preload("res://scripts/navigation_grid.gd")
const Resident=preload("res://scripts/resident_data.gd")
const G=preload("res://scripts/world_3d/world_geometry.gd")
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
var checks:=0
var failures:=0
var observer: Callable
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func observe(world: Node,label: String) -> void:
	if observer.is_valid():await observer.call(world,label)
func meshes(node: Node) -> Array:
	var found: Array=[]
	if node is MeshInstance3D:found.append(node)
	for child in node.get_children():found.append_array(meshes(child))
	return found
func colliders(node: Node) -> Array:
	return node.find_children("*","CollisionShape3D",true,false)
func facing(model: Node3D) -> Vector3:
	# Imported visible front is +Z. Include the local GLB correction and heading.
	return (model.model_basis.global_basis*Vector3.BACK).normalized()
func run() -> void:
	await movement_contract()
	await world_contract()
	print("Resident model/camera: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func movement_contract() -> void:
	var actor=Executor.new();actor.navigation=Grid.new(Rect2(-12,-12,24,24));root.add_child(actor)
	actor.setup(Resident.new("model_motion","Проверка",30));actor.set_physics_process(false)
	var reference=Node3D.new();root.add_child(reference)
	var mover=Movement.new();mover.body=reference;mover.navigation=actor.navigation;reference.add_child(mover)
	var physics=actor.view.get_children().filter(func(node):return node is CollisionShape3D)[0]
	var initial_shape: Transform3D=physics.transform
	var initial_scale: Vector3=actor.scale
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,Vector3(1,0,1).normalized(),Vector3(-1,0,-1).normalized()]:
		actor.position=Vector3(.25,0,.25);reference.position=actor.position
		var destination: Vector3=actor.position+direction*3
		actor.move_to(Coord.to_sim(destination));mover.set_target(destination)
		var last_direction:=Vector3.ZERO
		for frame in 120:
			var previous: Vector3=actor.position
			actor._physics_process(.025)
			mover.speed=actor.movement.speed;mover.advance(.025)
			check(actor.position.is_equal_approx(reference.position),"Artwork preserves exact path integration")
			if actor.position.distance_squared_to(previous)>0.000001:
				last_direction=(actor.position-previous).normalized()
				check(facing(actor.view.model).dot(last_direction)>.99999,"Imported front follows actual cardinal/diagonal movement")
			if not actor.movement.is_moving():break
		check(not actor.movement.is_moving() and actor.position.distance_to(destination)<.00001,"New appearance preserves arrival")
		var heading: Vector3=actor.view.model.rotation
		actor._physics_process(.05)
		check(actor.view.model.rotation==heading,"Stationary resident keeps last heading")
	check(actor.scale==initial_scale and physics.transform==initial_shape and actor.view.rotation==Vector3.ZERO,"Heading never rotates/scales gameplay view or collider")
	check(not actor.movement.trace_enabled,"Artwork does not enable navigation tracing")
	# Escort-owned motion uses the same artwork without changing its speed/distance cap.
	var owner=Node.new();root.add_child(owner)
	actor.position=Vector3(.25,0,.25);check(actor.claim_movement(owner),"Movement owner admission unchanged")
	actor.movement.set_target(actor.position+Vector3(2,0,0))
	actor.advance_owned(owner,.1,.5,.03)
	check(is_equal_approx(actor.position.x,.28) and facing(actor.view.model).dot(Vector3.RIGHT)>.99999,"Owned motion keeps distance cap and rotates only artwork")
	actor.release_movement(owner,true)
	var visual=actor.view.model;var instance=visual.instance
	actor.queue_free();await process_frame
	check(not is_instance_valid(visual) and not is_instance_valid(instance),"Removing executor deletes its GLB representation")
	reference.free();owner.free()
func world_contract() -> void:
	root.size=Vector2i(1280,720)
	var world=F.create(self)
	var camera: Camera3D=world.get_node("World/Camera3D");camera.set_process(false)
	await physics_frame;await process_frame
	var actor=world.resident_runtimes[0]
	var view=actor.view.view
	var first: Array=meshes(view.model.instance)
	check(first.size()==5,"Imported frog replaces capsule artwork with all five authored meshes")
	check(Model.MODEL.resource_path=="res://assets/models/creatures/zhabka.glb","One preloaded replaceable PackedScene")
	for runtime in world.resident_runtimes:
		var visual=runtime.view.view.model
		var other: Array=meshes(visual.instance)
		check(visual.instance!=view.model.instance or runtime==actor,"Each resident owns its own scene instance")
		check(visual.instance.scene_file_path==Model.MODEL.resource_path and other.size()==first.size(),"Every existing resident automatically receives the model")
		for index in first.size():
			check(other[index].mesh==first[index].mesh and other[index].material_override==null,"All scene instances share imported mesh resources without material overrides")
			for surface in first[index].mesh.get_surface_count():
				check(other[index].mesh.surface_get_material(surface)==first[index].mesh.surface_get_material(surface),"Original Blender materials shared without copies")
	check(view.model.find_children("*","PhysicsBody3D",true,false).is_empty() and colliders(view.model).is_empty(),"GLB creates no gameplay collision shapes")
	check(view.collision_layer==2 and view.collision_mask==0 and view.position==Vector3.ZERO,"Resident picking layer and position unchanged")
	var collider=colliders(view)[0]
	check(collider.shape is CapsuleShape3D and is_equal_approx(collider.shape.radius,.4) and is_equal_approx(collider.shape.height,1.44) and is_equal_approx(collider.position.y,.72),"Original explicit picking capsule dimensions retained")
	check(G.RESIDENT_RADIUS==.4 and G.RESIDENT_HEIGHT==1.44,"Gameplay dimensions unchanged")
	check(is_equal_approx(view.model.height(),G.RESIDENT_HEIGHT) and is_equal_approx(view.model.fitted_scale,1.44/.941482186317444),"Uniform scale derives from measured imported height")
	var boxes: Array[AABB]=[];Model._collect_bounds(view.model,Transform3D.IDENTITY,boxes)
	var box: AABB=boxes[0]
	for item in boxes.slice(1):box=box.merge(item)
	check(absf(box.position.y)<.00001 and is_equal_approx(box.end.y,1.44) and absf(box.get_center().x)<.00001 and absf(box.get_center().z)<.00001,"Imported pivot compensated; lowest mesh rests on ground and artwork is centered")
	check(view.name_label.position.y>box.end.y and view.name_label.text==actor.data.resident_name,"Original resident name remains above frog head")
	var transform: Transform3D=actor.view.transform;var collision: Transform3D=collider.transform
	var requests: int=world.decision_dispatcher.requests
	view.model.visual_scale=1.5
	check(is_equal_approx(view.model.height(),2.16) and view.name_label.position.y>2.16,"Single visual scale knob keeps proportions and updates name clearance")
	check(actor.view.transform==transform and collider.transform==collision and is_equal_approx(collider.shape.radius,.4) and world.decision_dispatcher.requests==requests,"Artwork rescale does not change position, collision or AI")
	view.model.visual_scale=1
	check(world.debug_spawn.spawn_residents(Vector3(12,0,22),2,P.NONE).created==2,"Existing spawn creates new residents normally")
	check(world.resident_runtimes.slice(-2).all(func(runtime):return runtime.view.view.model.instance.scene_file_path==Model.MODEL.resource_path),"Spawned residents also receive the shared artwork")
	var mill=F.building(world,T.SAWMILL,Vector3(7,0,16))
	check(world.player_control.assign_workplace(actor.data.id,mill.id) and actor.data.work_location_id==mill.id,"Ordinary production assignment retained with new model")
	var area=world.work_areas.create(Coord.to_sim(Vector3(30,0,-9)),Coord.length_to_sim(15))
	check(world.player_control.assign_profession(actor.data.id,P.MINER) and world.player_control.assign_work_area(actor.data.id,area.id) and actor.get_node("Miner").has_work(),"Personal work area and work discovery retained")
	world.player_control.clear_work_assignment(actor.data.id)
	actor.view.position=Vector3(-20.25,0,8.25)
	await physics_frame
	var original_rotation: Vector3=camera.rotation
	var maximum: float=camera.max_distance
	check(is_equal_approx(camera.min_distance,19.02956881/2) and is_equal_approx(maximum,253.72758419) and is_equal_approx(camera.distance_step,5.07455168),"Only minimum camera distance halves")
	camera.global_position+=actor.view.global_position-camera.get_focus_position()
	camera.set_zoom_distance(19.02956881)
	await observe(world,"old-minimum")
	camera.zoom(1000)
	check(is_equal_approx(camera.get_zoom_distance(),9.514784405) and camera.position.y>0 and camera.rotation==original_rotation,"Closer zoom clamps above ground without changing camera pitch/yaw")
	await physics_frame
	var point: Vector2=camera.unproject_position(actor.view.global_position+Vector3(0,.72,0))
	F.click_at(self,point);world._physics_process(0)
	check(world.resident_selection.selected_resident==actor.data and view.indicator.visible and world.resident_card_view().visible,"Real close-view ray click opens resident card and highlight")
	await observe(world,"new-minimum-selected")
	world.resident_selection.clear()
	check(not view.indicator.visible,"Clearing selection hides existing ring")
	camera.global_position+=Coord.to_world(world.warehouse_data.position)-camera.get_focus_position()
	await physics_frame
	point=camera.unproject_position(Coord.to_world(world.warehouse_data.position)+Vector3(0,2.5,0))
	F.click_at(self,point);world._physics_process(0)
	check(world.resident_selection.selected_building==world.warehouse_data,"Building selection works at new minimum distance")
	world.resident_selection.clear()
	camera.zoom(-1000)
	check(is_equal_approx(camera.get_zoom_distance(),maximum),"Old far zoom retained")
	var before: Vector3=camera.position
	camera.pan(Vector2.RIGHT,.25)
	check(is_equal_approx(camera.position.distance_to(before),5),"Keyboard pan speed retained after close/far zoom")
	var pivot: Vector3=camera.get_focus_position()
	camera.orbit_to_yaw(-25)
	check(camera.get_focus_position().distance_to(pivot)<.001 and is_equal_approx(camera.rotation_degrees.x,-50),"Yaw rotation retains focus, pitch and far distance")
	camera.set_zoom_distance(-100)
	check(is_equal_approx(camera.get_zoom_distance(),camera.min_distance),"Direct distance setter respects new lower limit")
	camera.set_zoom_distance(9999)
	check(is_equal_approx(camera.get_zoom_distance(),maximum) and camera.position.y>0,"Direct distance setter respects unchanged upper limit")
	await observe(world,"far-control")
	world.free();await process_frame
