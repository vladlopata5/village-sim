extends "res://tests/test_mycelium.gd"
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const Prof=preload("res://scripts/resident_profession.gd").Type
const DropResult=preload("res://scripts/cargo_drop_result.gd")
var world: Node
var observer: Callable
func observe(label: String, focus: Vector3) -> void:
	if observer.is_valid():await observer.call(world,label,focus)
func select(point: Vector3, turns: int = 0) -> void:
	world.placement.select(D.for_type(T.HOME));world.placement.update_world_position(point);world.placement.set_orientation(turns)
func walk(actor: Node, reason: StringName = &"") -> void:
	for step in range(4000):
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not reason.is_empty() and actor.intents.current_intent.reason_id!=reason:break
		if not actor.view.movement.is_moving():break
func run() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_time.total_minutes=420;world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.schedule._phase="День";actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	await physics_frame
	var land=world.mycelium
	var original_cells: Array=land.cells()
	check(original_cells.size()==30 and land.total()==0 and world.buildings.size()==1,"One visible authored land patch, no initial resource or building")
	await observe("initial",Vector3(-5,0,4))
	var piles: Array=[]
	for amount_value in range(1,5):
		var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-8.25+amount_value*0.5,0,3.75));piles.append(cell)
		check(land.add_mushrooms(cell,amount_value)==amount_value and world.mycelium_view.displayed_amount(cell)==amount_value,"One to four stable visual instances")
	var first: Vector2i=piles[0]
	var pile: Node=world.mycelium_view._piles[first]
	var transform_before: Transform3D=pile.get_child(0).multimesh.get_instance_transform(0)
	land.add_mushrooms(first);land.remove_mushrooms(first)
	check(pile.get_child(0).multimesh.get_instance_transform(0)==transform_before and world.mycelium_view.displayed_amount(first)==1,"Adding/removing retains transforms of existing mushrooms")
	check(world.ground_resources.drops.is_empty() and world.logistics.jobs.is_empty(),"Natural stock is absent from GroundResources and logistics")
	await observe("one-to-four",Vector3(-7,0,3.75))
	var point:=Vector3(-7,0,4)
	select(point)
	var occupied: Array=world.placement.proposed_cells()
	check(world.placement.can_place(),"Natural mushrooms/mycelium do not block building preview")
	await observe("preview",point)
	check(land.total()==10,"Preview never consumes mushrooms")
	world.placement.cancel();check(land.total()==10,"Cancel leaves natural stock")
	select(point);var building=world.placement.confirm()
	check(building!=null and land.cells()==original_cells,"Successful construction keeps every land property")
	for cell in occupied:check(land.amount(cell)==0 and not world._mushroom_cell_allowed(cell),"Whole actual footprint cleared and blocks growth")
	check(land.total()==0,"All four natural piles removed only after success")
	await observe("site-cleared",point)
	var source: Vector2i=occupied.filter(func(cell):return land.has_mycelium(cell))[0];check(land.has_mycelium(source),"Source under construction remains in land")
	var random=FixedRandom.new();random.choice=4
	check(not land.attempt(source,random).grew,"Occupied source cannot grow on itself")
	random.choice=3
	check(land.attempt(source,random).grew and land.amount(source+Vector2i.LEFT)==1,"Mycelium under construction still grows beside its footprint")
	await observe("growth-beside-site",point)
	check(world.cancel_construction(building.id) and land.cells()==original_cells and land.has_mycelium(source) and land.can_grow(source),"Actual cancellation releases ground without removing mycelium")
	check(land.add_mushrooms(source,4)==4,"Released site can grow again")
	world.road_tool.select();check(world.road_tool.paint(world.build_grid.cell_to_world(source)),"Actual road tool can paint over natural stock")
	check(land.amount(source)==0 and land.has_mycelium(source) and not land.can_grow(source),"Road removes natural stock, preserves land, forbids regrowth")
	world.road_tool.cancel()
	for cell in world.roads.cells():world.roads.remove_road(cell)
	check(land.can_grow(source),"Road removal restores growth eligibility")
	# Persistent occupancy is cached; moving residents are intentionally excluded.
	var actor=world.resident_runtimes[0]
	var previous_position: Vector3=actor.view.position
	actor.view.position=world.build_grid.cell_to_world(source)
	check(land.can_grow(source),"Resident standing on cell does not block growth")
	actor.view.position=previous_position
	for tree in world.trees:
		check(not land.can_grow(world.build_grid.world_to_cell(C.to_world(tree.position))),"Existing tree blocks growth through persistent registry")
	for rock in world.rocks:
		check(not land.can_grow(world.build_grid.world_to_cell(C.to_world(rock.position))),"Existing rock blocks growth")
	var provider: Callable=func():return world.build_grid.cell_to_world(source)
	world.runtime_placement_blockers.register_circle(&"test_static",provider,0.5,true,true)
	check(not land.can_grow(source),"New persistent object invalidates cached occupancy")
	for dy in range(-3,4):
		for dx in range(-3,4):
			var probe:=source+Vector2i(dx,dy)
			var box:=Rect2(C.world_plane(world.build_grid.cell_to_world(probe))-Vector2.ONE*0.25,Vector2.ONE*0.5)
			check(world.runtime_placement_blockers.static_cell_occupied(probe,world.build_grid)==not world.runtime_placement_blockers.first_overlap(box,true).is_empty(),"Static cell cache retains existing circle/rectangle tangency geometry")
	world.runtime_placement_blockers.unregister(&"test_static");check(land.can_grow(source),"Removed persistent object invalidates cached occupancy")
	var road_cell:=source+Vector2i(1,4)
	var road_stack: Dictionary=world.ground_resources.try_place(R.LOG,1,road_cell)
	world.road_tool.select();check(world.road_tool.paint(world.build_grid.cell_to_world(road_cell)) and road_stack.stack.amount==1,"Road policy for ordinary ground resources is unchanged; stack not erased")
	world.road_tool.cancel();world.ground_resources.remove_drop(road_stack.stack)
	for road in world.roads.cells():world.roads.remove_road(road)
	# Every ordinary type, including wild-looking dropped MUSHROOM, blocks a site.
	point=Vector3(2,0,14)
	var resource_cell: Vector2i=world.build_grid.world_to_cell(point)
	for resource in R.values():
		var result: Dictionary=world.ground_resources.try_place(resource,1,resource_cell)
		var stack=result.stack
		check(stack!=null and stack.reserve(&"blocking_owner"),"Ordinary stock can be reserved before placement")
		select(point)
		check(not world.placement.can_place() and world.placement.validation_reason().contains("лежат ресурсы") and world.placement.confirm()==null,"All ordinary stocks/reservations block final placement")
		check(not world.debug_spawn.spawn_building(point,D.for_type(T.HOME)).ok and stack.amount==1 and stack.reserved_amount(&"blocking_owner")==1,"Debug building uses same rule without deleting or moving resource")
		check(world.ground_resources.take_reserved(stack,&"blocking_owner"),"Authoritative pickup removes blocking unit")
		check(world.placement.can_place(),"Empty ground becomes buildable after pickup")
		world.placement.cancel()
	# A late resource after a valid preview rejects confirmation, preserving natural stock.
	select(point);check(world.placement.can_place(),"Initially valid proposal")
	var footprint: Array=world.placement.proposed_cells()
	land.add_mushrooms(footprint[0])
	var late: Dictionary=world.ground_resources.try_place(R.LOG,1,footprint[-1])
	check(world.placement.confirm()==null and land.amount(footprint[0])==1 and late.stack.amount==1,"Final revalidation does not partially clear natural or ordinary stock")
	await observe("ordinary-resource-blocks",point)
	world.ground_resources.remove_drop(late.stack);land.remove_mushrooms(footprint[0]);world.placement.cancel()
	# Adjacent cells outside a rotated footprint do not become fictitious blockers.
	select(point,1);footprint=world.placement.proposed_cells()
	var adjacent: Vector2i=footprint[-1]+Vector2i.RIGHT
	var outside: Dictionary=world.ground_resources.try_place(R.STONE,1,adjacent)
	check(world.placement.can_place(),"Neighboring ordinary stack outside rotated footprint permits construction")
	world.ground_resources.remove_drop(outside.stack);world.placement.cancel()
	# Real one-unit pickup/delivery, not just deletion of the blocker.
	world.place_ground_resources(R.LOG,1,C.to_sim(point))
	check(world.player_control.assign_workplace(actor.data.id,world.warehouse_data.id,Prof.PORTER) and world._request_work(actor),"Normal Porter accepts the ordinary blocking resource")
	walk(actor,&"haul_source");check(actor.data.inventory.amount==1 and world.ground_resources.get_at(resource_cell)==null,"Real HaulExecutor transfers blocker to one-unit inventory")
	walk(actor);select(point)
	check(actor.data.inventory.amount==0 and world.placement.can_place(),"After actual delivery, actor and resource no longer block site")
	world.placement.cancel()
	# Existing cargo contract protects errors; accepted nearby drops cannot occupy a building.
	var center: Vector2=world.warehouse_data.position
	check(world._place_worker_cargo(R.LOG,1,center)==DropResult.Status.FAILED,"Invalid inside-building drop origin is FAILED, never silent destruction")
	var dropped: Dictionary=world.place_ground_resources(R.LOG,1,C.to_sim(Vector3(7,0,10)),world.ground_resources.PlacementMode.WORKER)
	check(dropped.placed==1,"Valid exterior worker drop remains available")
	for stack in world.ground_resources.drops:check(world.build_grid.occupant(stack.cell).is_empty(),"New placement API does not put stock inside occupied building cells")
	check(world.logistics.jobs.is_empty(),"No hanging transport after real delivery")
	world.placement.cancel();world.free()
	print("Mycelium world: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
