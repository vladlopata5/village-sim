extends SceneTree
const Roads = preload("res://scripts/road_grid.gd")
const Tool = preload("res://scripts/world_3d/road_tool_3d.gd")
const Layer = preload("res://scripts/world_3d/road_layer_3d.gd")
const Grid = preload("res://scripts/build_grid.gd")
const Nav = preload("res://scripts/navigation_grid.gd")
const Blockers = preload("res://scripts/runtime_placement_blockers.gd")
const Movement = preload("res://scripts/world_3d/grid_movement_3d.gd")
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func run() -> void:
	var bounds := Rect2(0,0,12,8)
	var roads=Roads.new(bounds)
	check(roads.CELL_SIZE==0.5 and preload("res://scripts/balance_config.gd").DIRT_ROAD_SPEED_MULTIPLIER==1.25,"Road cell size and centralized speed")
	check(roads.add_road(Vector2i(2,3)) and roads.contains(Vector2i(2,3)),"Generic add/query without player ownership")
	check(not roads.add_road(Vector2i(2,3)) and roads.cells().size()==1,"Duplicate adds are idempotent")
	check(not roads.add_road(Vector2i(-1,0)),"Road model rejects out-of-bounds cells")
	check(roads.remove_road(Vector2i(2,3)) and roads.cells().is_empty(),"Remove road state")
	var nav=Nav.new(bounds,0)
	var tool=Tool.new()
	tool.roads=roads
	tool.build_grid=Grid.new(bounds)
	tool.runtime_blockers=Blockers.new()
	tool.select()
	var many=tool.stroke_cells(Vector2i(2,2),Vector2i(20,2))
	check(many.size()==40,"Fast stroke fills every intervening 2-cell brush column")
	var diagonal=tool.stroke_cells(Vector2i(2,2),Vector2i(12,12))
	var combined: Dictionary={}
	for cell in tool.stroke_cells(Vector2i(2,2),Vector2i(7,7)): combined[cell]=true
	for cell in tool.stroke_cells(Vector2i(7,7),Vector2i(12,12)): combined[cell]=true
	check(diagonal.size()==combined.size() and diagonal.all(func(cell): return combined.has(cell)),"Collinear diagonal sampling leaves identical connected stroke")
	check(tool.stroke_cells(Vector2i(12,12),Vector2i(2,2)).all(func(cell): return cell in diagonal),"Rasterization independent of drag direction")
	var layer=Layer.new()
	root.add_child(layer)
	layer.setup(roads)
	var projection=preload("res://scripts/world_3d/road_navigation_3d.gd").new()
	projection.setup(roads,nav)
	check(tool.paint(Vector3(1.25,0,1.25)) and tool.paint(Vector3(10.25,0,1.25)),"Paint fast drag via common tool")
	check(roads.cells().size()==40 and layer.multimesh.instance_count==40,"Batch visual matches authoritative road cells")
	var revision: int=nav.revision
	var old_mesh: MultiMesh=layer.multimesh
	tool.end_stroke()
	tool.paint(Vector3(1.25,0,1.25))
	tool.paint(Vector3(10.25,0,1.25))
	check(nav.revision==revision and layer.multimesh==old_mesh,"Duplicate painting creates no sources, visuals or nav updates")
	check(is_equal_approx(nav.get_world_speed_multiplier(Vector3(5.25,0,1.25)),1.25),"Road speed does not compound")
	tool.end_stroke()
	tool.paint(Vector3(1.25,0,1.25),true)
	tool.paint(Vector3(10.25,0,1.25),true)
	check(roads.cells().is_empty() and layer.multimesh.instance_count==0 and nav.get_world_speed_multiplier(Vector3(5.25,0,1.25))==1.0,"Erase removes state, visual and modifier")
	var a := Vector3(1.25,0,3.25)
	var b := Vector3(11.25,0,3.25)
	check(nav.find_path(a,b).size()==2,"Ground-only path remains direct")
	layer.visible=false
	roads.add_road(Vector2i(1,1))
	check(is_equal_approx(nav.get_cell_speed_multiplier(Vector2i(1,1)),1.25),"Navigation projection does not depend on road mesh visibility")
	roads.remove_road(Vector2i(1,1))
	layer.visible=true
	var row: Array[Vector2i]=[]
	for x in range(2,23): row.append(Vector2i(x,5))
	roads.edit(row,false)
	var path: PackedVector3Array=nav.find_path(a,b)
	check(path.size()>2 and nav.path_travel_cost(path)<a.distance_to(b),"Slightly longer road detour wins by travel time")
	print("Road detour: ",path," cost=",nav.path_travel_cost(path)," ground=",a.distance_to(b))
	roads.edit(row,true)
	check(nav.find_path(a,b).size()==2,"Removing road restores ground path")
	row.clear()
	for x in range(2,23): row.append(Vector2i(x,0))
	roads.edit(row,false)
	check(nav.find_path(a,b).size()==2,"Very long road detour loses to faster ground route")
	roads.edit(row,true)
	# Same distance timing and FPS independence in the shared movement layer.
	var body := Node3D.new()
	root.add_child(body)
	var mover=Movement.new()
	body.add_child(mover)
	mover.body=body
	mover.navigation=nav
	mover.speed=1
	body.position=a
	mover.set_target(b)
	mover.advance(8)
	check(mover.is_moving() and is_equal_approx(body.position.x,9.25),"Ground: 8 seconds of 10 required")
	row.clear()
	for x in range(2,23): row.append(Vector2i(x,6))
	roads.edit(row,false)
	body.position=a
	mover.set_target(b)
	mover.advance(8)
	check(not mover.is_moving() and body.position==b,"Road same 10-unit distance takes 8 seconds, 80% ground time")
	body.position=a
	mover.set_target(b)
	for frame in range(15): mover.advance(1.0/30.0)
	var fps30: Vector3=body.position
	body.position=a
	mover.set_target(b)
	for frame in range(72): mover.advance(1.0/144.0)
	check(body.position==fps30 and is_equal_approx(body.position.x-a.x,0.625),"Road movement identical at 30/144 FPS")
	nav.set_traversal_modifier(&"tree_test",Rect2(3,3,1,1),0.2)
	check(is_equal_approx(nav.get_world_speed_multiplier(Vector3(3.25,0,3.25)),0.2),"Injected road/tree overlap preserves minimum source semantics")
	roads.remove_road(Vector2i(6,6))
	check(is_equal_approx(nav.get_world_speed_multiplier(Vector3(3.25,0,3.25)),0.2),"Erasing road preserves tree modifier")
	body.free()
	layer.free()
	await integration()
	print("Dirt roads: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func integration() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.social_events.enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	await physics_frame
	check(world.roads.cells().is_empty(),"No starter roads or duplicate simulation objects")
	var actor=world.resident_runtimes[0]
	world.resident_selection.select(actor.data)
	var toggle=world.get_node("HUD/NavigationDebugToggle")
	toggle.button_pressed=true
	check(world.navigation_debug.visible and world.navigation_debug._grid.mesh!=null,"Existing toggle enables grid and route renderer")
	var grid_mesh=world.navigation_debug._grid.mesh
	toggle.button_pressed=false
	check(not world.navigation_debug.visible and world.navigation_debug._grid.mesh==grid_mesh,"OFF hides both layers without rebuilding grid")
	world._select_road_tool()
	check(world.road_tool.active and not world.placement.is_active(),"Road mode excludes building placement")
	var tree=world.trees[0]
	world.road_tool.paint(C.to_world(tree.position))
	var tree_cell: Vector2i=world.build_grid.world_to_cell(C.to_world(tree.position))
	check(not world.roads.contains(tree_cell) and world.roads.cells().size()>0 and world.tree_views.has(tree.id),"Tree-overlap cells skipped while adjacent brush cells painted; tree intact")
	check(tree.claim(&"road_fixture") and tree.add_work(&"road_fixture",tree.work_required),"Normal forestry domain work finishes tree")
	world._deplete_tree(tree)
	world.road_tool.end_stroke()
	world.road_tool.paint(C.to_world(tree.position))
	check(world.roads.contains(tree_cell) and world.ground_resources.drops.size()==3,"After chop road paint allowed; forestry yield unchanged")
	# Residents may stand on roads; they remain building-placement blockers only.
	var resident_cell: Vector2i=world.build_grid.world_to_cell(actor.view.get_world_position())
	check(world.road_tool.can_paint(resident_cell),"Movable residents do not prevent instant road surface painting")
	world.road_tool.end_stroke()
	world.road_tool.paint(Vector3(26.25,0,20.25))
	world.road_tool.paint(Vector3(34.25,0,20.25))
	var before: Array=world.roads.cells()
	world._select_building_definition(Def.for_type(Types.HOME))
	check(not world.road_tool.active and world.placement.is_active(),"Building selection exits road mode")
	world.placement.update_world_position(Vector3(30,0,20.5))
	var cells: Array=world.placement.proposed_cells()
	var site=world.placement.confirm()
	check(site!=null and not site.is_built(),"Placement succeeds over road with existing UNDER_CONSTRUCTION lifecycle")
	check(cells.all(func(cell): return not world.roads.contains(cell)),"Road under actual footprint deleted")
	check(before.filter(func(cell): return cell not in cells).all(func(cell): return world.roads.contains(cell)),"Road outside footprint preserved")
	check(cells.all(func(cell): return world.navigation.get_cell_speed_multiplier(cell)==1.0),"Only covered road modifiers removed")
	check(not world.navigation.is_world_walkable(C.to_world(site.position)),"Building hard blocker active normally")
	check(world.cancel_construction(site.id) and cells.all(func(cell): return not world.roads.contains(cell)),"Cancellation does not restore hidden roads")
	world.resident_selection.select(actor.data)
	world._select_road_tool()
	world.handle_world_click(MOUSE_BUTTON_RIGHT,{"collider":world.get_node("World/Ground"),"position":Vector3(28,0,20)})
	check(actor.commands.active_command==null,"Road mode cannot issue MOVE_TO")
	var camera: Camera3D=world.get_node("World/Camera3D")
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.position=camera.unproject_position(Vector3(28.25,0,24.25))
	world._unhandled_input(press)
	var motion:=InputEventMouseMotion.new()
	motion.position=camera.unproject_position(Vector3(34.25,0,24.25))
	world._unhandled_input(motion)
	world._physics_process(0)
	check(world.roads.contains(world.build_grid.world_to_cell(Vector3(31.25,0,24.25))),"Actual queued mouse A->B paints intermediate cells")
	check(actor.commands.active_command==null and world.buildings.size()==7,"Drag does not issue commands or buildings")
	var release:=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_LEFT
	world._input(release)
	world._physics_process(0)
	press.shift_pressed=true
	world._unhandled_input(press)
	motion.shift_pressed=true
	world._unhandled_input(motion)
	world._physics_process(0)
	check(not world.roads.contains(world.build_grid.world_to_cell(Vector3(31.25,0,24.25))),"Shift+LMB drag erases through actual input flow")
	var escape:=InputEventKey.new()
	escape.pressed=true
	escape.keycode=KEY_ESCAPE
	world._unhandled_input(escape)
	check(not world.road_tool.active,"Escape exits road tool")
	world.handle_world_click(MOUSE_BUTTON_RIGHT,{"collider":world.get_node("World/Ground"),"position":Vector3(28,0,20)})
	check(actor.commands.active_command!=null,"MOVE_TO restored after road tool exit")
	var camera_before: Vector3=camera.position
	camera.pan(Vector2.RIGHT,0.1)
	camera.zoom(1)
	check(camera.position!=camera_before and camera.size<44,"Camera pan/zoom unchanged")
	toggle.button_pressed=true
	actor.view._physics_process(0)
	check(world.navigation_debug._smooth.mesh!=null and world.navigation_debug._smooth.mesh.get_surface_count()>0,"Toggle ON keeps real committed route visualization")
	toggle.button_pressed=false
	check(not world.navigation_debug._smooth.is_visible_in_tree() and not world.navigation_debug._grid.is_visible_in_tree() and world.road_layer.is_visible_in_tree(),"Toggle OFF hides routes and grid while road layer remains visible")
	actor.commands.cancel_current()
	world._select_road_tool()
	var ui_before: int=world.roads.cells().size()
	var ui_press:=InputEventMouseButton.new()
	ui_press.button_index=MOUSE_BUTTON_LEFT
	ui_press.pressed=true
	ui_press.position=world.get_node("HUD/DebugPanel").collapse_button.get_global_rect().get_center()
	var ui_motion:=InputEventMouseMotion.new()
	ui_motion.position=ui_press.position
	root.push_input(ui_motion,true)
	root.push_input(ui_press,true)
	await process_frame
	await physics_frame
	var ui_release:=InputEventMouseButton.new()
	ui_release.button_index=MOUSE_BUTTON_LEFT
	ui_release.position=ui_press.position
	root.push_input(ui_release,true)
	await physics_frame
	check(world.roads.cells().size()==ui_before,"Real viewport UI click does not paint road")
	var right_click:=InputEventMouseButton.new()
	right_click.pressed=true
	right_click.button_index=MOUSE_BUTTON_RIGHT
	world._unhandled_input(right_click)
	check(not world.road_tool.active,"RMB exits without issuing MOVE_TO")
	world._select_road_tool()
	var network_start := Time.get_ticks_msec()
	for row_index in range(12):
		world.road_tool.end_stroke()
		world.road_tool.paint(Vector3(22.25,0,26.25+row_index))
		world.road_tool.paint(Vector3(54.25,0,26.25+row_index))
	print("Network cells=%d, edit_ms=%d" % [world.roads.cells().size(),Time.get_ticks_msec()-network_start])
	check(world.roads.cells().size()>1500,"Long network uses one batched layer with many road cells")
	var network_revision: int=world.navigation.revision
	var network_mesh: MultiMesh=world.road_layer.multimesh
	for frame in range(5): await physics_frame
	check(world.navigation.revision==network_revision and world.road_layer.multimesh==network_mesh,"Idle frames rebuild neither road visuals nor navigation weights")
	check(world.road_layer.multimesh.instance_count==world.roads.cells().size() and world.road_layer.get_child_count()==0,"No per-tile presentation nodes or duplicates")
	world.free()
