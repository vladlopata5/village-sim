extends SceneTree
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
	await physics_frame
	var roads=world.roads
	check(roads.chance==0.25 and roads.decay_per_night==1,"Canonical world keeps approved balance")
	check(not world.construction_panel.catalogue.entries.has(&"dirt_road"),"No ordinary dirt-road brush")
	var cell:=Vector2i(150,110)
	var view=world.road_layer
	check(view.multimesh.instance_count==40960 and view.multimesh.visible_instance_count==0,"One allocated buffer, no initial natural tiles")
	check(view.color_for(cell)==Color(0.28,0.43,0.27),"Level zero original grass")
	var changed: Array=[]
	roads.levels_changed.connect(func(cells):changed.append(cells.duplicate()))
	var nav_revision: int=world.navigation.revision
	var nav_events: Array=[]
	world.navigation.changed.connect(func(value):nav_events.append(value))
	var mm: MultiMesh=view.multimesh
	for level in range(1,16):roads.set_trample_level(cell,level)
	check(view._dirty.size()==1,"Many changes coalesce to one dirty cell")
	view.flush_updates()
	check(view.multimesh==mm and view.multimesh.visible_instance_count==1 and view._cells.size()==1,"Addressed update reuses buffer")
	check(view.color_for(cell)==view.DIRT_COLOR,"Level15 exact existing dirt colour")
	roads.set_trample_level(cell,7)
	check(view.color_for(cell).is_equal_approx(Color(0.28,0.43,0.27).lerp(view.DIRT_COLOR,7.0/15)),"Intermediate colour interpolation")
	var other:=cell+Vector2i.RIGHT
	roads.set_trample_level(other,5);view.flush_updates()
	roads.set_trample_level(cell,0);view.flush_updates()
	check(view.multimesh.visible_instance_count==1 and view._slots[other]==0 and not view._slots.has(cell),"Delete swaps last instance and fixes index")
	roads.add_road(other)
	check(view.multimesh.visible_instance_count==1 and view.color_for(other)==view.DIRT_COLOR,"Manual/natural share one tile")
	roads.remove_road(other)
	check(view.multimesh.visible_instance_count==1,"Manual erasure retains natural tile")
	# Preserve mushroom stock, source identity and independent claims through every level.
	var nature: Vector2i=world.mycelium.cells()[0]
	for road in roads.cells():roads.remove_road(road)
	world.mycelium.add_mushrooms(nature,4)
	var id: StringName=world.mycelium.source_id(nature)
	check(world.mycelium.reserve(id,&"collector_a") and world.mycelium.reserve(id,&"collector_b"),"Two collector claims before wear")
	var base: Color=world.mycelium_view.LAND_COLOR
	for level in [1,10,11,15]:
		roads.set_trample_level(nature,level)
		check(world.mycelium.has_mycelium(nature) and world.mycelium.amount(nature)==4 and world.mycelium.reserved(id,&"collector_a") and world.mycelium.reserved(id,&"collector_b") and world.mycelium.can_grow(nature)==false,"Wear preserves land/stock/claims; full cell remains full")
	roads.set_trample_level(nature,7)
	check(view.color_for(nature).is_equal_approx(base.lerp(view.DIRT_COLOR,7.0/15)),"Mycelium base tint participates")
	world.mycelium.release(id,&"collector_a");world.mycelium.release(id,&"collector_b")
	world.mycelium.remove_mushrooms(nature,1)
	check(world.mycelium.can_grow(nature),"Natural path does not block mushroom growth")
	var dropped: Dictionary=world.ground_resources.try_place(R.LOG,3,cell)
	check(dropped.stack!=null,"Ordinary stack fixture")
	var stack: RefCounted=dropped.stack
	stack.reserve(&"owner")
	roads.set_trample_level(cell,15)
	check(stack.amount==3 and stack.reserved_amount(&"owner")==1 and world.ground_resources.get_at(cell)==stack,"Natural levels retain stack and reserve")
	check(world._demolition_cell_allowed(cell,[world.build_grid.cell_to_world(cell)]),"Natural path permits D1 resource return")
	check(world.navigation.revision==nav_revision+2 and nav_events.size()==2,"Only explicit manual road add/remove change navigation")
	# Real physical entry, late arrival and another resident sharing a live cell.
	roads.chance=1
	var actor=world.resident_runtimes[0]
	actor.view.global_position=Vector3(35.25,0,24.25)
	actor.view.movement.speed=1
	actor.view.movement.set_target(Vector3(37.25,0,24.25))
	var seen: Array=[]
	actor.view.movement.cell_entered.connect(func(entered):seen.append(entered))
	actor.view.movement.advance(2)
	check(seen.size()==4 and seen.all(func(entered):return roads.trample_level(entered)==1),"Real canonical mover wears each entered cell once")
	var final_cell: Vector2i=seen[-1]
	actor.view.movement.set_target(Vector3(37.3,0,24.25));actor.view.movement.advance(1)
	check(roads.trample_level(final_cell)==1,"Restart within final cell adds no visit")
	var second=world.resident_runtimes[1]
	second.view.global_position=Vector3(35.25,0,24.25);second.view.movement.speed=1
	second.view.movement.set_target(Vector3(37.25,0,24.25));second.view.movement.advance(2)
	check(roads.trample_level(final_cell)==2,"Second physical resident independently visits same source cell")
	# Real portal transitions are not physical movement and do not emit cell entries.
	var intent=preload("res://scripts/resident_intent.gd").new()
	intent.type=intent.Type.MOVE_TO;intent.reason_id=&"portal_test"
	intent.building_id=world.warehouse_data.id
	intent.slot_purpose=preload("res://scripts/world_3d/building_slot_3d.gd").Purpose.COURIER
	actor.view.movement.stop()
	actor.view.global_position=world.building_uses.entrance(intent.building_id)
	actor.view.movement.reset_physical_origin()
	actor.data.activity=preload("res://scripts/resident_activity.gd").Type.WORKING
	actor.view._active=intent
	var before_portal: int=seen.size()
	actor.view._enter_or_wait()
	check(actor.view.is_inside_building(intent.building_id),"Portal fixture actually acquired interior slot")
	actor.view._exit_building()
	check(seen.size()==before_portal,"Portal entry/exit creates no physical cell entries")
	# The source footprint is the only area cleared after successful placement.
	world.placement.select(D.for_type(T.HOME));world.placement.update_world_position(Vector3(30,0,15))
	var footprint: Array=world.placement.proposed_cells()
	var adjacent: Vector2i=footprint[-1]+Vector2i.RIGHT
	for point in footprint+[adjacent]:roads.set_trample_level(point,6);roads.visit(point)
	check(footprint.all(func(point):return roads.trample_level(point)>0),"Preview preserves path")
	var site=world.placement.confirm()
	check(site!=null and footprint.all(func(point):return roads.trample_level(point)==0 and not roads._used.has(roads._index(point))) and roads.trample_level(adjacent)>0,"Only confirmed footprint clears levels and use")
	var tree=world.trees[0]
	var tree_cell: Vector2i=world.build_grid.world_to_cell(C.to_world(tree.position))
	var old: int=roads.trample_level(tree_cell)
	roads.visit(tree_cell)
	check(roads.trample_level(tree_cell)==old,"Static natural obstacle prevents inappropriate wear")
	roads.visit(footprint[0])
	check(roads.trample_level(footprint[0])==0,"Occupied footprint cannot wear")
	world.free()
	print("Trampling world: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
