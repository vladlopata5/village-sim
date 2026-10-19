extends SceneTree
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const D=preload("res://scripts/building_definition.gd")
const B=preload("res://scripts/building_instance.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const S=preload("res://scripts/resource_source_ref.gd")
const Inventory=preload("res://scripts/resident_inventory.gd")
const Drop=preload("res://scripts/cargo_drop_result.gd")
var failures:=0
var checks:=0
var world: Node
var hut: RefCounted
var actor: Node
var observer: Callable
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func observe(label: String) -> void:
	if observer.is_valid(): await observer.call(world,label,actor)
func cell_at(point: Vector3) -> Vector2i:return world.build_grid.world_to_cell(point)
func clear_nature() -> void: world.mycelium.clear_cells(world.mycelium.mushroom_cells())
func arrival(worker: Node) -> void:
	var executor=world.logistics._executors[worker.data.id]
	for step in range(8000):
		if executor.handling.is_active() or executor.job==null:break
		worker.view._physics_process(0.05)
	check(executor.job!=null and executor.handling.is_active(),"Physical movement reaches the handling point")
func cancel() -> void:
	var job=world.logistics.get_job(actor.data.id)
	if job!=null:world.logistics.cancel_transport(job,"test interruption")
func start_at(cell: Vector2i, quantity: int = 1) -> bool:
	world.mycelium.add_mushrooms(cell,quantity)
	return actor.self_logistics.request_work()
func run() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_time.total_minutes=420;world.game_logger.console_enabled=false
	for worker in world.resident_runtimes:
		worker.decision._deciding=true;worker.intents.abort_current(worker.intents.current_intent);worker.schedule._phase="День";worker.view.set_physics_process(false)
		for need in worker.data.needs.values():need.value=0;need.base_weight=0
	actor=world.resident_runtimes[0]
	hut=B.new(&"physical_gatherer",D.for_type(T.GATHERER_HUT),C.to_sim(Vector3(-3,0,-5)))
	world.buildings.append(hut);world._show_building(hut)
	await physics_frame
	check(world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER),"Explicit hut assignment works")
	check(hut.resources.get_capacity(R.MUSHROOM)==5 and hut.definition.worker_capacity==4,"Hut retains 5 units and 4 workers")
	check(not world.player_control.can_assign_work_area(actor.data.id),"Gatherer never receives a personal FREE area")
	world._view_registered_building(hut.id);world.game_ui.info_panel.select_tab(&"info")
	check(world.building_card_view().work_area_section.visible and world.building_card_view().work_area_label.text.contains("15.0"),"Gatherer building card exposes the shared standard-area controls")
	world.resident_selection.select(actor.data);world.game_ui.info_panel.select_tab(&"work")
	check(not world.resident_card_view().area_button.visible,"Gatherer resident card does not offer a personal area")
	var original: Array=world.authored_mycelium_cells()
	var selected: Array=world.mycelium.cells()
	check(original.size()==150 and selected.size()==30,"Thirty cells retained from the original 150")
	var expected: Array=[];var random:=RandomNumberGenerator.new();random.seed=preload("res://scripts/balance_config.gd").MUSHROOM_GROWTH_SEED
	for band in range(30):expected.append(original[band*5+random.randi_range(0,4)])
	check(expected==selected and selected.all(func(cell):return cell in original),"Fixed-seed selection is reproducible and remains a subset")
	check(selected[-1].y-selected[0].y>=9,"Selected cells span the former territory")
	var attempts: Array=[0]
	world.mushroom_growth.attempted.connect(func(_cell,_minute,_result):attempts[0]+=1)
	world.game_time.debug_skip_minutes(960)
	check(world.mushroom_growth.pending_count()+attempts[0]==150,"Thirty cells schedule 150 attempts per full night")
	world.game_time.total_minutes=420
	var land=world.mycelium
	var target:=cell_at(Vector3(-4.25,0,2.25))
	var farther:=cell_at(Vector3(-6.25,0,2.25))
	check(land.add_mushrooms(target,4)==4,"Natural cell holds four units")
	var id: StringName=land.source_id(target)
	for i in range(4):check(land.reserve(id,StringName("owner%d"%i)),"Four distinct unit claims succeed")
	check(not land.reserve(id,&"fifth") and land.amount(target)==4,"Fifth claim fails without reducing physical stock")
	check(land.reserve(id,&"owner0") and land.available_amount(id)==0,"Repeated reserve does not claim a second unit")
	land.release(id,&"owner0");check(land.available_amount(id)==1 and land.reserved(id,&"owner1"),"Release preserves other owners")
	check(land.remove_mushrooms(target,4)==1 and land.amount(target)==3,"Unowned removal cannot consume reserved units")
	var inventory=Inventory.new();var observed: Array=[]
	var ownership_observer: Callable=func(_cell,_amount):observed.append([land.total(),inventory.amount])
	land.mushrooms_changed.connect(ownership_observer)
	check(inventory.receive(R.MUSHROOM,1,land.take_reserved.bind(id,&"owner1")),"One reserved fungus transfers into real inventory")
	check(land.amount(target)==2 and land.source_id(target)==id and land.reserved(id,&"owner2"),"Partial pickup retains generation and foreign claim")
	check(observed.is_empty(),"No observer sees source removal before inventory commit")
	await process_frame
	check(not observed.is_empty() and observed[0]==[2,1],"Natural-stock notification observes committed ownership")
	land.mushrooms_changed.disconnect(ownership_observer)
	land.clear_cells([target]);check(not land.reserved(id,&"owner2") and land.source_cell(id)==null,"Construction-style clearing invalidates all claims")
	land.add_mushrooms(target);check(land.source_id(target)!=id and not land.take_reserved(id,&"owner3"),"Regrowth never revives an old source claim")
	clear_nature()
	var ordinary: Dictionary=world.place_ground_resources(R.MUSHROOM,1,C.to_sim(Vector3(-4.25,0,2.25)))
	check(ordinary.placed==1 and not actor.self_logistics.has_work(),"Dropped MUSHROOM is not a natural gathering target")
	for stack in world.ground_resources.drops.duplicate():world.ground_resources.remove_drop(stack)
	land.add_mushrooms(target);land.add_mushrooms(farther)
	var original_route: Callable=world.logistics.sources.route_available
	var route_calls: Array=[0]
	var blocked: Vector2=land.position(land.source_id(target))
	world.logistics.sources.route_available=func(start,finish):route_calls[0]+=1;return start!=blocked and finish!=blocked
	var chosen=world.production.find_source(actor.data)
	check(chosen!=null and chosen.id==land.source_id(farther),"Unreachable nearest source is skipped")
	var calls: int=route_calls[0]
	check(world.production.find_source(actor.data).id==chosen.id and route_calls[0]==calls,"Unchanged proposal avoids repeated route checks")
	world.logistics.sources.route_available=original_route
	# Invalidate the synthetic route result using actual source revision.
	clear_nature()
	var area=world.work_areas.create(C.to_sim(Vector3(25,0,25)),25.0)
	check(world.player_control.assign_building_work_area(hut.id,area.id),"Existing building-area assignment supports Gatherer Hut")
	land.add_mushrooms(target)
	check(not actor.self_logistics.has_work(),"Assigned building area excludes otherwise nearby fungus")
	check(world.player_control.reset_building_work_area(hut.id) and actor.self_logistics.has_work(),"Reset restores standard 15-world-unit building circle")
	var source_ref=world.production.find_source(actor.data)
	var foreign=world.resident_runtimes[1]
	check(world.logistics.claim_transport(foreign.data.id,source_ref,hut,R.MUSHROOM,func():return true)==null,"Ordinary logistics cannot claim natural mushrooms")
	clear_nature()
	for speed in [1,2,4,10,20]:
		world.game_time.total_minutes=420;world.game_time.set_speed(speed)
		if speed==20: actor.data.add_skill_xp(0,100)
		var xp_before: int=actor.data.get_skill_xp(0)
		check(start_at(target,4),"Physical gathering starts at each supported speed")
		check(hut.resources.get_reserved_in(R.MUSHROOM)==1 and land.amount(target)==4,"Dispatch promises hut room, never removes fungus")
		await observe("outbound")
		arrival(actor)
		world.game_time.advance(9.0/speed)
		check(land.amount(target)==4 and actor.data.inventory.amount==0,"First nine minutes leave the reserved fungus in nature")
		await observe("gathering")
		world.game_time.advance(1.0/speed)
		check(land.amount(target)==3 and actor.data.inventory.amount==1,"Exactly ten minutes produce one physical cargo")
		await observe("returning")
		arrival(actor)
		world.game_time.advance(9.0/speed)
		check(hut.resources.get_amount(R.MUSHROOM)==0 and actor.data.inventory.amount==1,"First nine unloading minutes retain cargo")
		world.game_time.advance(1.0/speed)
		check(hut.resources.get_amount(R.MUSHROOM)==1 and actor.data.inventory.amount==0 and world.logistics.get_job(actor.data.id)==null,"Ten-minute unload completes once and releases job")
		check(actor.data.get_skill_xp(0)==xp_before+1,"Completed natural gathering trip awards exactly one gathering XP")
		await observe("unloaded")
		hut.resources.try_take(R.MUSHROOM,1);clear_nature()
	# Four independent trips require 80 handling minutes, without old 30-minute work.
	world.game_time.total_minutes=420;world.game_time.set_speed(1)
	var trip_start: int=world.game_time.total_minutes
	land.add_mushrooms(target,4)
	for trip in range(4):
		check(actor.self_logistics.request_work(),"Each of four mushrooms requires a new physical trip")
		arrival(actor);world.game_time.debug_skip_minutes(10)
		arrival(actor);world.game_time.debug_skip_minutes(10)
	check(world.game_time.total_minutes-trip_start==80 and hut.resources.get_amount(R.MUSHROOM)==4 and land.amount(target)==0,"Four one-unit trips need 80 handling minutes before travel is counted")
	hut.resources.try_take(R.MUSHROOM,4)
	# Ordinary phase change preserves the already accepted haul, as in E1/E2.
	world.game_time.total_minutes=1019
	check(start_at(target),"Trip accepted before the end of shift")
	arrival(actor);world.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1 and world.game_time.get_phase()!="День","Accepted collection survives the phase boundary")
	arrival(actor);world.game_time.debug_skip_minutes(10)
	check(hut.resources.get_amount(R.MUSHROOM)==1 and world.logistics.get_job(actor.data.id)==null,"Accepted return unloads after the shift; no new ordinary trip starts")
	hut.resources.try_take(R.MUSHROOM,1);world.game_time.total_minutes=420
	# Two overlapping building areas share natural stock, never exclusive ownership.
	var second_hut=B.new(&"second_gatherer",D.for_type(T.GATHERER_HUT),C.to_sim(Vector3(5,0,-15)))
	world.buildings.append(second_hut);world._show_building(second_hut)
	var shared=world.work_areas.create(C.to_sim(Vector3(-5,0,2)),100.0)
	world.player_control.assign_building_work_area(hut.id,shared.id)
	world.player_control.assign_building_work_area(second_hut.id,shared.id)
	var second=world.resident_runtimes[1]
	world.player_control.assign_workplace(second.data.id,second_hut.id,P.GATHERER)
	land.add_mushrooms(target,2)
	check(actor.self_logistics.request_work() and second.self_logistics.request_work(),"Two huts can claim different units of one pile in a shared area")
	arrival(actor);arrival(second)
	await observe("two-huts-gathering")
	world.game_time.debug_skip_minutes(10)
	check(land.amount(target)==0 and actor.data.inventory.amount==1 and second.data.inventory.amount==1,"Two physical workers collect two reserved units without conflict")
	arrival(actor);arrival(second);world.game_time.debug_skip_minutes(10)
	check(hut.resources.get_amount(R.MUSHROOM)==1 and second_hut.resources.get_amount(R.MUSHROOM)==1,"Each worker physically unloads at its own hut")
	hut.resources.try_take(R.MUSHROOM,1);second_hut.resources.try_take(R.MUSHROOM,1)
	world.player_control.reset_building_work_area(hut.id)
	var xp_after_completed: int=actor.data.get_skill_xp(0)
	# Source invalidation differs from destination/assignment cleanup; test both.
	world.player_control.assign_workplace(actor.data.id,second_hut.id,P.GATHERER)
	check(start_at(target),"Trip to a second hut starts before receiver removal")
	world.logistics.remove_building(second_hut.id)
	check(world.logistics.get_job(actor.data.id)==null and land.amount(target)==1 and second_hut.resources.get_reserved_in(R.MUSHROOM)==0,"Removing a receiver promptly releases natural and inbound claims")
	world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER);clear_nature()
	# Player commands and critical needs use the unchanged forced-interrupt path.
	for picked_up in [false,true]:
		check(start_at(target),"Command-interruption fixture claims a real mushroom")
		if picked_up:arrival(actor);world.game_time.debug_skip_minutes(10)
		actor.commands.move_to(Vector2(100,100))
		check(world.logistics.get_job(actor.data.id)==null and hut.resources.get_reserved_in(R.MUSHROOM)==0 and actor.data.inventory.amount==0,"Player command cancels gathering and settles its cargo")
		check(land.amount(target)==(0 if picked_up else 1),"Command before pickup retains natural stock; after pickup it never recreates nature")
		actor.commands.cancel_current();clear_nature()
		for stack in world.ground_resources.drops.duplicate():world.ground_resources.remove_drop(stack)
	for critical in ["hunger","fatigue"]:
		check(start_at(target),"Critical-interruption fixture starts a physical trip")
		arrival(actor);world.game_time.debug_skip_minutes(10)
		actor.decision._deciding=false
		actor.data.set(critical,100)
		check(actor.intents.forced_priority>0 and world.logistics.get_job(actor.data.id)==null and actor.data.inventory.amount==0 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Critical hunger/fatigue promptly interrupt gathering through existing cleanup")
		actor.decision._deciding=true;actor.data.hunger=0;actor.data.fatigue=0
		actor.needs._cancel_own_action();actor.intents.abort_current(actor.intents.current_intent)
		clear_nature()
		for stack in world.ground_resources.drops.duplicate():world.ground_resources.remove_drop(stack)
	check(start_at(target),"Return-route failure fixture starts")
	arrival(actor);world.game_time.debug_skip_minutes(10)
	actor.view.movement.failed.emit() # Existing executor failure boundary, not arrival.
	check(world.logistics.get_job(actor.data.id)==null and actor.data.inventory.amount==0 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Failed return route cancels and drops owned cargo without pretending to deliver")
	for stack in world.ground_resources.drops.duplicate():world.ground_resources.remove_drop(stack)
	# Reentrant command inside receive's inventory notification must settle once.
	check(start_at(target),"Reentrant pickup fixture starts")
	arrival(actor)
	var interrupt: Callable=func():
		if actor.data.inventory.amount==1:actor.commands.move_to(Vector2(100,100))
	actor.data.inventory.changed.connect(interrupt)
	world.game_time.debug_skip_minutes(10)
	actor.data.inventory.changed.disconnect(interrupt)
	check(world.logistics.get_job(actor.data.id)==null and actor.data.inventory.amount==0 and land.amount(target)==0 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Nested command during pickup settles ownership and reservations once")
	var nested_units:=0
	for stack in world.ground_resources.drops:
		if stack.resource_type==R.MUSHROOM:nested_units+=stack.amount
	check(nested_units==1,"Reentrant pickup produces one dropped mushroom, no loss or duplicate")
	actor.commands.cancel_current()
	for stack in world.ground_resources.drops.duplicate():world.ground_resources.remove_drop(stack)
	# Shared stock / separate incoming promises for all four staff slots.
	land.add_mushrooms(target,4)
	for worker in world.resident_runtimes:
		check(world.player_control.assign_workplace(worker.data.id,hut.id,P.GATHERER) and worker.self_logistics.request_work(),"Four staff claim different units of one natural pile")
	check(hut.resources.get_reserved_in(R.MUSHROOM)==4 and land.available_amount(land.source_id(target))==0,"Parallel incoming room and source claims agree")
	for worker in world.resident_runtimes:world.logistics.cancel_transport(world.logistics.get_job(worker.data.id),"parallel test")
	check(hut.resources.get_reserved_in(R.MUSHROOM)==0 and land.amount(target)==4 and land.available_amount(land.source_id(target))==4,"Cancellation releases only owned claims without consuming stock")
	hut.resources.add(R.MUSHROOM,4)
	check(actor.self_logistics.request_work(),"Last free buffer unit can be promised")
	check(not world.resident_runtimes[1].self_logistics.has_work(),"Full buffer including inbound promises prevents second dispatch")
	cancel();hut.resources.try_take(R.MUSHROOM,4)
	check(actor.self_logistics.request_work(),"New trip after released capacity")
	world.player_control.assign_building_work_area(hut.id,area.id)
	check(world.logistics.get_job(actor.data.id)==null and land.amount(target)==4 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Area change cancels pre-pickup task and releases both claims")
	world.player_control.reset_building_work_area(hut.id)
	check(actor.self_logistics.request_work(),"Reset allows subsequent ordinary gathering decision")
	land.clear_cells([target])
	check(world.logistics.get_job(actor.data.id)==null and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Destroyed source cancels traveling worker immediately")
	check(start_at(target,1),"New source generation can be gathered")
	arrival(actor);world.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1,"Pre-interruption cargo exists")
	world.player_control.assign_profession(actor.data.id,P.NONE)
	check(world.logistics.get_job(actor.data.id)==null and actor.data.inventory.amount==0 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Assignment change drops owned cargo through E1 and frees incoming promise")
	var units:=0
	for stack in world.ground_resources.drops:if stack.resource_type==R.MUSHROOM:units+=stack.amount
	check(units==1,"Interruption creates exactly one ordinary dropped mushroom")
	cancel();world.logistics.recalculate()
	var after:=0
	for stack in world.ground_resources.drops:if stack.resource_type==R.MUSHROOM:after+=stack.amount
	check(after==units,"Repeated cancellation cannot duplicate cargo")
	world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER)
	check(start_at(farther),"Next gathering task can start")
	arrival(actor);world.game_time.debug_skip_minutes(10)
	world.logistics.cargo_drop_handler=func(_resource,_amount,_resident):return Drop.Status.FAILED
	world.logistics.cancel_transport(world.logistics.get_job(actor.data.id),"technical refusal")
	check(actor.data.inventory.amount==1 and hut.resources.get_reserved_in(R.MUSHROOM)==0,"Technical drop failure retains cargo and releases reservations")
	check(actor.data.get_skill_xp(0)==xp_after_completed,"Cancelled trips award no experience, including after pickup")
	clear_nature();world.game_time.debug_skip_minutes(120)
	check(hut.resources.get_amount(R.MUSHROOM)==0,"No virtual generation after physical source exhaustion")
	check(land.add_mushrooms(farther)==1 and second.self_logistics.request_work(),"World teardown also tolerates an active natural-source trip")
	await process_frame
	world.free()
	await process_frame
	print("Physical gathering: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
