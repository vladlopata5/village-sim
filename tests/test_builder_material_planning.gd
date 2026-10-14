extends SceneTree
const Grid=preload("res://scripts/navigation_grid.gd")
const Sources=preload("res://scripts/resource_sources.gd")
const Ground=preload("res://scripts/ground_resources.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const R=preload("res://scripts/resource_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const Def=preload("res://scripts/building_definition.gd")
const Types=preload("res://scripts/building_type.gd").Type
const Builder=preload("res://scripts/resident_builder_controller.gd")
const Step=preload("res://tests/handling_test_step.gd")
class CountingGrid extends "res://scripts/navigation_grid.gd":
	var raw_calls:=0
	var smooth_calls:=0
	func find_raw_path(a: Vector3,b: Vector3) -> PackedVector3Array:
		raw_calls+=1
		return super.find_raw_path(a,b)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls+=1
		return super.smooth_path(raw)
var checks:=0
var failures:=0
var navigation: CountingGrid
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func lower(a: Vector2,b: Vector2,c: Vector2) -> float:
	return navigation.minimum_path_cost(C.to_world(a),C.to_world(b))+navigation.minimum_path_cost(C.to_world(b),C.to_world(c))
func path(a: Vector2,b: Vector2) -> Dictionary:
	var start:=C.to_world(a);var target:=C.to_world(b)
	if not navigation.can_reach_point(start,target):return {}
	var raw:=navigation.find_raw_path(start,target)
	if not navigation.is_raw_path_walkable(raw):return {}
	return {"raw":raw,"start":start,"target":target,"navigation_id":navigation.get_instance_id(),"revision":navigation.revision}
func plan(a: Vector2,b: Vector2,c: Vector2) -> Dictionary:
	var first:=path(a,b)
	if first.is_empty():return {}
	var second:=path(b,c)
	if second.is_empty():return {}
	return {"source_path":first,"delivery_path":second,"cost":navigation.raw_path_travel_cost(first.raw)+navigation.raw_path_travel_cost(second.raw)}
func quiet_world() -> Node:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	world.navigation=CountingGrid.new()
	root.add_child(world)
	world.game_time.set_process(false);world.set_process(false);world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.view.set_physics_process(false)
		actor.wander.target_provider=Callable()
		actor.decision.work_available=func():return false
		actor.decision.work_request=Callable()
		actor.schedule.work_decision=Callable()
		world.game_time.minute_changed.disconnect(actor.need_dynamics._on_minute_changed)
		for need in actor.data.needs.values():need.value=0
		actor.intents.clear_reason(&"day_work")
		actor.schedule._phase="День"
	world.game_time.total_minutes=420
	return world
func site(world: Node):
	var definition=Def.for_type(Types.HOME)
	definition.construction_requirements={R.PLANK:2} # Ownership edge fixture; normal recipes covered by full suite/soak.
	world.placement.select(definition);world.placement.update_world_position(Vector3(-10,0,25))
	return world.placement.confirm()
func finish_leg(actor: Node,phase: int) -> void:
	for i in range(800):
		if actor.builder.phase!=phase:break
		Step.move_3d(actor,0.05)
	check(actor.builder.phase!=phase,"Actual 3D movement/loading/unloading finishes the leg")
func run() -> void:
	var clock=preload("res://scripts/game_time.gd").new();root.add_child(clock);clock.set_process(false)
	var ground=Ground.new();root.add_child(ground);ground.setup(clock)
	var provider=Sources.new();provider.bind_ground(ground)
	navigation=CountingGrid.new(Rect2(-20,-20,40,40),0.15)
	var origin:=Vector2(-2.25,0.25)*25;var target:=Vector2(-2.25,8.25)*25
	var near=ground.create_drop(R.LOG,1,Vector2(2.25,0.25)*25)
	var far=ground.create_drop(R.LOG,1,Vector2(-12.25,8.25)*25)
	navigation.add_blocker(&"wall",Rect2(-0.3,-14,0.6,28))
	var revision: int=provider.revision
	var trip: Dictionary=provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower)
	check(trip.reference.id==far.id,"Large wall detour chooses the sensible farther straight-line source")
	check(navigation.is_raw_path_walkable(trip.source_path.raw) and navigation.is_raw_path_walkable(trip.delivery_path.raw),"Both selected raw legs pass mandatory clearance/LOS checks")
	check(navigation.smooth_calls==0,"Rejected and selected candidates are not smoothed during selection")
	check(provider.revision==revision and provider._claims.is_empty() and near.reservation_owner_id.is_empty() and far.reservation_owner_id.is_empty(),"Availability query takes no resource reservations")
	navigation.add_blocker(&"wall",Rect2(-0.3,-20,0.6,40))
	for i in range(7):ground.create_drop(R.LOG,1,Vector2(2.25,float(i)+1.25)*25)
	trip=provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower)
	check(trip.reference.id==far.id,"Search passes more than five unreachable candidates instead of reporting no work")
	provider.reserve(trip.reference,R.LOG,&"other")
	check(provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower).is_empty(),"Reserved last unit and disconnected alternatives cannot be assigned")
	provider.release(trip.reference,R.LOG,&"other")
	ground.remove_drop(far)
	check(provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower).is_empty(),"Removed source is re-resolved, never reused by ID alone")
	navigation.remove_blocker(&"wall")
	check(not provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower).is_empty(),"Opening topology restores work, with no permanent negative cache")
	# Same lower bound remains conservative for accelerated and slow surfaces.
	navigation.set_traversal_modifier(&"road",Rect2(-19,-19,1,5),1.25)
	navigation.set_traversal_modifier(&"slow",Rect2(-1,-3,5,8),0.5)
	trip=provider.find_construction_trip(R.LOG,origin,target,&"",plan,lower)
	check(trip.cost>=lower(origin,provider.point(trip.reference),target),"Weighted raw score uses movement travel cost and admissible fastest-surface bound")
	ground.free();clock.free();provider=null
	# Exact matching route handoff avoids another A*, but geometry changes invalidate it.
	navigation=CountingGrid.new(Rect2(-10,-10,20,20),0.15)
	var body:=Node3D.new();root.add_child(body);body.position=Vector3(-4.25,0,0.25)
	var movement=preload("res://scripts/world_3d/grid_movement_3d.gd").new();root.add_child(movement)
	movement.body=body;movement.navigation=navigation
	var goal:=Vector3(4.25,0,0.25)
	var packet:=path(C.to_sim(body.position),C.to_sim(goal))
	var raw_before:=navigation.raw_calls
	movement.set_target(goal,packet);movement.advance(0)
	check(navigation.raw_calls==raw_before and navigation.smooth_calls==1,"One-use selected raw path is smoothed once at execution without repeated A*")
	check(movement.raw_path[-1]==goal and navigation.is_raw_path_walkable(movement.current_path()),"Execution retains target and safe geometry")
	navigation.add_blocker(&"detour",Rect2(-0.5,-1,1,2))
	movement.advance(0)
	check(navigation.raw_calls==raw_before+1 and navigation.is_raw_path_walkable(movement.current_path()),"Navigation revision replans safely after blocker edits")
	packet["raw"]=PackedVector3Array([body.position,Vector3(0,0,0.25)])
	packet["revision"]=navigation.revision
	raw_before=navigation.raw_calls
	movement.set_target(goal,packet);movement.advance(0)
	check(navigation.raw_calls==raw_before+1 and movement.raw_path[-1]==goal,"Mismatched raw endpoint is rejected even when packet target metadata matches")
	packet=path(C.to_sim(body.position),C.to_sim(goal))
	body.position=Vector3(-4.25,0,1.25);raw_before=navigation.raw_calls
	movement.set_target(goal,packet);movement.advance(0)
	check(navigation.raw_calls==raw_before+1,"Changed origin invalidates a formerly valid hint")
	var arrival_count: Array=[0];movement.arrived.connect(func():arrival_count[0]+=1)
	movement.speed=10;movement.advance(100)
	check(body.position==goal and arrival_count[0]==1,"Real weighted movement reaches the intended target exactly once")
	movement.free();body.free()
	# Canonical controller reuses offers but reads current stock, identity and needs.
	var world=quiet_world();var building=site(world)
	var first=world.resident_runtimes[1];var second=world.resident_runtimes[3]
	world.warehouse_data.resources.try_take(R.PLANK,world.warehouse_data.resources.get_amount(R.PLANK))
	var drop=world.ground_resources.create_drop(R.PLANK,1,Vector2(-4.25,-1.25)*25)
	world.player_control.assign_profession(first.data.id,P.BUILDER);world.player_control.assign_profession(second.data.id,P.BUILDER)
	check(first.builder.has_work() and second.builder.has_work(),"Two builders see the same unreserved real material")
	var searches: int=first.builder.source_search_count
	check(first.builder.has_work() and first.builder.source_search_count==searches,"Repeated unchanged availability reuses the proposal")
	check(drop.reservation_owner_id.is_empty() and building.get_construction_reserved_in(R.PLANK)==0,"Both proposals are read-only")
	check(first.builder.request_work() and first.builder.source_search_count==searches,"Availability to acquisition reuses the source search")
	check(not second.builder.request_work() and building.get_construction_reserved_in(R.PLANK)==1,"Second builder rechecks the last unit instead of over-reserving")
	check(first.builder.phase==Builder.Phase.GOING_TO_SOURCE,"The successful query becomes a genuine construction trip")
	first.commands.move_to(Vector2(0,0))
	check(drop.reservation_owner_id.is_empty() and building.get_construction_reserved_in(R.PLANK)==0,"Interrupt before pickup releases both reservations")
	first.intents.clear_reason(&"player_move")
	var trip_before: Dictionary=second.builder._material_trip(building)
	var old_raw: int=world.navigation.raw_calls
	world.ground_resources.create_drop(R.PLANK,1,Vector2(-6.25,-1.25)*25)
	var trip_after: Dictionary=second.builder._material_trip(building)
	check(trip_after.reference.id==trip_before.reference.id and world.navigation.raw_calls==old_raw,"Unrelated quantity changes preserve valid geometry while stock is re-read")
	old_raw=world.navigation.raw_calls
	world.navigation.set_traversal_modifier(&"p1_cost_change",Rect2(-8,-3,3,1),0.5)
	second.builder._material_trip(building)
	check(world.navigation.raw_calls>old_raw,"Changed navigation weights invalidate the old proposal")
	check(second.builder.request_work(),"Builder can acquire after quantity/navigation updates")
	finish_leg(second,Builder.Phase.GOING_TO_SOURCE)
	check(second.data.inventory.amount==1 and building.get_construction_reserved_in(R.PLANK)==1,"Physical pickup owns exactly one material")
	finish_leg(second,Builder.Phase.CARRYING_TO_SITE)
	check(building.get_delivered_amount(R.PLANK)==1 and second.data.inventory.amount==0,"First material is physically delivered without duplication")
	finish_leg(second,Builder.Phase.GOING_TO_SOURCE)
	finish_leg(second,Builder.Phase.CARRYING_TO_SITE)
	check(building.get_delivered_amount(R.PLANK)==2 and building.get_construction_reserved_in(R.PLANK)==0 and world.ground_resources.drops.is_empty(),"Sequential real deliveries consume both units and free all inbound reserves")
	for i in range(6):
		if building.is_built():break
		if second.builder.phase==Builder.Phase.NONE:second.builder.request_work()
		finish_leg(second,Builder.Phase.GOING_TO_SITE)
		world.game_time.debug_skip_minutes(60)
	check(building.is_built() and building.active_builder_ids.is_empty(),"Actual builder work completes the site and releases ownership")
	check(second.builder._trip_offer.is_empty() and second.builder._delivery_path.is_empty(),"Completed work retains no stale material proposal")
	world.free()
	world=quiet_world();building=site(world);first=world.resident_runtimes[1]
	world.warehouse_data.resources.try_take(R.PLANK,world.warehouse_data.resources.get_amount(R.PLANK))
	world.ground_resources.create_drop(R.PLANK,1,Vector2(-4.25,-1.25)*25)
	world.player_control.assign_profession(first.data.id,P.BUILDER)
	first.view.global_position=C.to_world(world.warehouse_data.position)
	check(not first.builder.has_work(),"Blocked original position produces a genuine negative availability")
	first.view.global_position=Vector3(-3,0,-4)
	check(first.builder.has_work(),"Moving to a reachable origin invalidates negative availability without a stock/topology edit")
	world.free()
	print("Builder material planning: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
