extends "res://tests/test_multi_recipe_production.gd"
const Haul = preload("res://scripts/haul_job.gd")
const DropResult = preload("res://scripts/cargo_drop_result.gd")
const Balance = preload("res://scripts/balance_config.gd")
var measures: Array=[]

class ProbeSources extends "res://scripts/resource_sources.gd":
	var searches := 0
	var routes := 0
	func find_first(resource: int, origin: Vector2, destination: Vector2, excluded: StringName, workplace: RefCounted, area: RefCounted = null) -> Source:
		searches+=1
		return super.find_first(resource,origin,destination,excluded,workplace,area)
	func track_route(start: Vector2, end: Vector2, delegate: Callable) -> bool:
		routes+=1
		return delegate.call(start,end)

func definition():
	var result=super.definition()
	result.production_recipes[0].inputs={Resources.LOG:2,Resources.STONE:1}
	result.production_recipes[1].work_required=40
	return result
func setup_supply_world() -> Dictionary:
	var world=scene()
	var target=physical_building(world)
	for resource in Resources.values(): target.resources.try_take(resource,target.resources.get_amount(resource))
	target.definition.logistics_flow=target.definition.logistics_flow.duplicate(true)
	for resource in Resources.values():
		target.definition.logistics_flow[resource]={"import":true,"export":resource in [Resources.PLANK,Resources.FOOD]}
	only(target,A)
	var actors: Array=world.resident_runtimes.slice(1,4)
	for actor in actors: world.player_control.assign_workplace(actor.data.id,target.id)
	return {"world":world,"target":target,"actors":actors}
func instrument(world: Node) -> ProbeSources:
	var old=world.logistics.sources
	var probe=ProbeSources.new()
	probe.buildings=old.buildings; probe.locations=old.locations
	probe.work_object_current=old.work_object_current
	var route: Callable=old.route_available
	probe.route_available=probe.track_route.bind(route)
	old.changed.disconnect(world.logistics._on_state_changed)
	old.ground.availability_changed.disconnect(old._queue_changed)
	probe.bind_ground(old.ground)
	probe.changed.connect(world.logistics._on_state_changed)
	world.logistics.sources=probe
	return probe
func arrive(actor: Node) -> void:
	for step in range(2000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func assert_no_promises(target: RefCounted, world: Node, text: String) -> void:
	check(target.supply.needs.is_empty() and world.logistics.jobs.is_empty(),text+": no supply metadata or jobs")
	for resource in Resources.values(): check(target.resources.get_reserved_in(resource)==0 and target.resources.get_reserved_out(resource)==0,text+": no destination promises")

func priorities_and_physical() -> void:
	var f=setup_supply_world(); var world=f.world; var target=f.target
	var first=f.actors[0]; var second=f.actors[1]; var third=f.actors[2]
	target.resources.add(Resources.LOG,1); target.resources.add(Resources.STONE,2)
	world.warehouse_data.resources.add(Resources.LOG,5)
	target.set_production_order(A,1); target.set_maintain_target(B,1)
	var probe=instrument(world)
	var cold_at:=Time.get_ticks_usec()
	var offer=first.self_logistics.task()
	measures.append({"case":"cold ORDER supply selection","microseconds":Time.get_ticks_usec()-cold_at,"find_first":probe.searches,"route_checks":probe.routes})
	check(offer.kind==&"SUPPLY" and offer.recipe_id==A and offer.resource==Resources.LOG,"ORDER supply beats immediately available MAINTAIN start")
	var samples: Array=[]
	var warm_searches: int=probe.searches
	var warm_routes: int=probe.routes
	for sample_index in range(8):
		first.self_logistics._offer={}
		var sample_at:=Time.get_ticks_usec()
		first.self_logistics.task()
		samples.append(Time.get_ticks_usec()-sample_at)
	measures.append({"case":"8 fresh selections after first navigation query","microseconds_samples":samples,"find_first":probe.searches-warm_searches,"route_checks":probe.routes-warm_routes})
	var reads_at: int=probe.searches
	var routes_at: int=probe.routes
	var started_at:=Time.get_ticks_usec()
	for index in range(100): first.self_logistics.has_work()
	measures.append({"case":"100 positive same-frame has_work","microseconds":Time.get_ticks_usec()-started_at,"find_first":probe.searches-reads_at,"route_checks":probe.routes-routes_at})
	check(probe.searches==reads_at and probe.routes==routes_at and world.logistics.jobs.is_empty() and target.supply.needs.is_empty() and target.production_batches.is_empty() and target._recipe_cursors.is_empty(),"Preview reuses positive source without jobs, kits, batches or cursor changes")
	var claim_at:=Time.get_ticks_usec()
	check(world._request_work(first),"Worker accepts existing logistics SUPPLY")
	measures.append({"case":"live claim after positive has_work","microseconds":Time.get_ticks_usec()-claim_at,"find_first":probe.searches-reads_at,"route_checks":probe.routes-routes_at})
	check(probe.searches==reads_at,"has_work -> request does not repeat full source selection")
	var job=world.logistics.get_job(first.data.id)
	check(job!=null and job.amount==1 and job.resource_type==Resources.LOG and target.resources.get_reserved_in(Resources.LOG)==1 and world.warehouse_data.resources.get_reserved_out(Resources.LOG)==1,"Specific unit has real inbound/outbound reservations")
	check(target.production_batches.is_empty() and world.building_uses.inside_count(target.id)==0,"Supply kit holds neither a ProductionBatch nor physical WORKER")
	var pointer: Dictionary=target._recipe_cursors.duplicate()
	target.supply.accept(target.supply.find(A).id,job)
	check(target._recipe_cursors==pointer,"Accepted supply rotates common cursor exactly once")
	check(world._request_work(second) and second.recipe_work.batch.recipe_id==B,"Already-covered inbound does not make another worker wait; it starts MAINTAIN")
	check(third.self_logistics.task().is_empty() and target.resources.get_reserved_in(Resources.LOG)==1,"No duplicate unit for the same recipe shortage")
	walk(second)
	arrive(first)
	check(world.building_uses.occupied_by(world.warehouse_data.id,first.data.id,Slot.Purpose.COURIER) and world.logistics._executors[first.data.id].handling.is_active() and first.data.inventory.amount==0,"Real source COURIER arrival starts original loading")
	world.game_time.debug_skip_minutes(Balance.RESOURCE_LOADING_MINUTES)
	check(first.data.inventory.amount==1 and job.state==Haul.State.GOING_TO_DESTINATION,"Existing HaulExecutor physically picks one ingredient")
	arrive(first)
	check(world.building_uses.occupied_by(target.id,first.data.id,Slot.Purpose.COURIER) and target.resources.get_amount(Resources.LOG)==1 and first.data.inventory.amount==1,"Destination COURIER arrival precedes physical unloading")
	world.game_time.debug_skip_minutes(Balance.RESOURCE_UNLOADING_MINUTES)
	check(job.state==Haul.State.COMPLETED and target.resources.get_amount(Resources.LOG)==2 and first.data.inventory.amount==0 and target.resources.get_reserved_in(Resources.LOG)==0 and target.get_order_remaining(A)==1,"Delivery adds ingredient physically but does not count as ORDER output")
	check(world._request_work(first),"Delivered multi-component kit can START its ORDER")
	walk(first)
	check(first.recipe_work.batch.recipe_id==A and second.recipe_work.batch.recipe_id==B and target.production_batches.size()==2 and target.supply.needs.is_empty(),"Two actual recipe controllers run independent batches after supply")
	world.game_time.debug_skip_minutes(20)
	check(target.resources.get_amount(Resources.PLANK)==1 and target.resources.get_amount(Resources.FOOD)==1 and target.resources.get_amount(Resources.LOG)==0 and target.resources.get_amount(Resources.STONE)==0 and target.get_order_remaining(A)==0,"Per-type balance: one initial + one delivered LOG, two STONE consumed; one PLANK and FOOD produced")
	assert_no_promises(target,world,"Completed supply and production")
	check(world.warehouse_data.resources.get_amount(Resources.LOG)==4,"Only one source unit was consumed")
	world.free()

func shared_inputs_and_modes() -> void:
	var f=setup_supply_world(); var world=f.world; var target=f.target
	target.definition.production_recipes[1].inputs={Resources.LOG:1,Resources.PLANK:1}
	target.resources.add(Resources.LOG,1)
	world.warehouse_data.resources.add(Resources.LOG,5); world.warehouse_data.resources.add(Resources.STONE,5); world.warehouse_data.resources.add(Resources.PLANK,5)
	target.set_production_order(A,1); target.set_production_order(B,1)
	check(world._request_work(f.actors[0]) and world.logistics.get_job(f.actors[0].data.id).resource_type==Resources.LOG,"First kit needs one additional LOG")
	check(world._request_work(f.actors[1]) and world.logistics.get_job(f.actors[1].data.id).resource_type==Resources.LOG,"Second kit cannot reuse local LOG already allocated to the first future recipe")
	check(target.supply.deficits(A)=={Resources.STONE:1} and target.supply.deficits(B)=={Resources.PLANK:1},"Two own inbound LOG plus one shared local LOG cover exactly three required units")
	check(world._request_work(f.actors[2]) and world.logistics.get_job(f.actors[2].data.id).resource_type==Resources.STONE,"Common round-robin returns to a different missing component")
	var kept=world.logistics.get_job(f.actors[1].data.id)
	target.set_recipe_mode(A,Mode.OFF)
	check(kept.is_active() and world.logistics.jobs.size()==1 and target.supply.needs.size()==1 and target.supply.find(B).jobs.size()==1 and world.warehouse_data.resources.get_reserved_out(Resources.LOG)==1 and world.warehouse_data.resources.get_reserved_out(Resources.STONE)==0,"OFF for one recipe releases only its jobs, preserving shared-source reservation of another")
	check(world._request_work(f.actors[0]) and world.logistics.get_job(f.actors[0].data.id).resource_type==Resources.PLANK,"Remaining recipe continues useful supply without reordering old accepted LOG")
	target.set_production_order(B,0)
	assert_no_promises(target,world,"Reduced ORDER removes no-longer-useful supply")
	check(world.warehouse_data.resources.get_reserved_out(Resources.LOG)==0 and world.warehouse_data.resources.get_reserved_out(Resources.PLANK)==0,"All source reservations released before pickup")
	world.free()
	# Skip an unavailable first component, then stop at one bounded kit.
	f=setup_supply_world(); world=f.world; target=f.target
	world.warehouse_data.resources.add(Resources.STONE,5)
	target.set_production_order(A,5)
	var actor=f.actors[0]
	var offered=actor.self_logistics.task()
	check(offered.kind==&"SUPPLY" and offered.resource==Resources.STONE,"Missing unavailable LOG does not block useful STONE delivery")
	check(world._request_work(actor),"Partial multi-component supply accepted")
	walk(actor,&"haul_source"); walk(actor)
	for index in range(50): actor.self_logistics.task()
	check(world.logistics.jobs.is_empty() and target.resources.get_amount(Resources.STONE)==1 and target.supply.needs.size()==1,"Unavailable remaining component cannot cause repeated STONE accumulation")
	# A dormant kit may yield to other useful work without cancelling any accepted trip.
	target.resources.add(Resources.LOG,1)
	target.set_recipe_mode(C,Mode.UNLIMITED)
	check(actor.self_logistics.task().kind==&"PRODUCTION" and world._request_work(actor),"Unavailable high recipe does not block lower available recipe")
	check(actor.recipe_work.batch.recipe_id==C,"Ordinary use of free shared input is permitted")
	world.free()

func cancellation_and_failures() -> void:
	for stage in ["failed_claim","cancel_before","off_carrying_failed","source_removed","receiver_removed","reservation_lost","maintain_met","output_full"]:
		var f=setup_supply_world(); var world=f.world; var target=f.target; var actor=f.actors[0]
		target.resources.add(Resources.LOG,1); target.resources.add(Resources.STONE,1)
		world.warehouse_data.resources.add(Resources.LOG,2)
		if stage=="maintain_met": target.set_maintain_target(A,1)
		else: target.set_production_order(A,1)
		if stage=="failed_claim":
			world.warehouse_data.resources.reservations_changed.connect(func(_resource): actor.commands.move_to(Vector2(0,500)),CONNECT_ONE_SHOT)
			check(not world._request_work(actor) and target._recipe_cursors.is_empty() and world.warehouse_data.resources.get_amount(Resources.LOG)==2,"Failed/reentrant claim never advances pointer or spends source")
			assert_no_promises(target,world,stage)
			world.free(); continue
		check(world._request_work(actor),"Cancellation fixture accepts original haul")
		var job=world.logistics.get_job(actor.data.id)
		match stage:
			"cancel_before": actor.commands.move_to(Vector2(0,500))
			"off_carrying_failed":
				walk(actor,&"haul_source")
				world.logistics.cargo_drop_handler=func(_resource,_amount,_resident): return DropResult.Status.FAILED
				target.set_recipe_mode(A,Mode.OFF)
				check(actor.data.inventory.amount==1 and actor.data.inventory.resource_type==Resources.LOG and world.warehouse_data.resources.get_amount(Resources.LOG)==1,"FAILED retains real cargo; no teleport refund or destruction")
			"source_removed": world.logistics.remove_building(world.warehouse_data.id)
			"receiver_removed":
				walk(actor,&"haul_source")
				world.logistics.remove_building(target.id)
				check(actor.data.inventory.amount==0 and Stacks.total(world.ground_resources,Resources.LOG)==1,"Receiver removal after pickup uses existing physical ground drop")
			"reservation_lost": world.warehouse_data.resources.release_out(Resources.LOG,1)
			"maintain_met": target.resources.add(Resources.PLANK,1)
			"output_full": target.resources.add(Resources.PLANK,40)
		check(job.state==Haul.State.CANCELLED,stage+": accepted job cancels through existing executor")
		assert_no_promises(target,world,stage)
		world.free()

func limits_and_selection() -> void:
	var f=setup_supply_world(); var world=f.world; var target=f.target; var actor=f.actors[0]
	world.warehouse_data.resources.add(Resources.LOG,5); world.warehouse_data.resources.add(Resources.STONE,5)
	target.set_maintain_target(A,1); target.set_recipe_mode(C,Mode.UNLIMITED)
	target.resources.add(Resources.LOG,1)
	check(actor.self_logistics.task().kind==&"SUPPLY" and actor.self_logistics.task().recipe_id==A,"MAINTAIN supply beats ready UNLIMITED")
	var probe=instrument(world)
	target.set_recipe_mode(A,Mode.OFF)
	check(actor.self_logistics.task().kind==&"PRODUCTION" and probe.searches==0,"Ready START does not search supply sources for same recipe")
	check(world._request_work(actor),"Ready low recipe starts through normal provider")
	walk(actor); var batch=actor.recipe_work.batch
	actor.commands.move_to(Vector2(0,500)); actor.commands.cancel_current(); actor.intents.abort_current(actor.intents.current_intent)
	target.set_production_order(A,3)
	check(actor.self_logistics.task().kind==&"PRODUCTION" and probe.searches==0 and target.select_production_work(actor.data.id).kind==&"RESUME","Paid RESUME beats even available high-priority supply, without source probes")
	check(world._request_work(actor),"Paused paid work can be resumed")
	walk(actor)
	check(actor.recipe_work.batch==batch,"Same process resumed, no extra supply metadata")
	world.free()
	# One-unit output room bounds supply; no extra production reservation is created.
	f=setup_supply_world(); world=f.world; target=f.target; actor=f.actors[0]
	world.warehouse_data.resources.add(Resources.LOG,5); world.warehouse_data.resources.add(Resources.STONE,5)
	target.resources.set_capacity(Resources.PLANK,0)
	probe=instrument(world)
	check(actor.self_logistics.task().is_empty() and probe.searches==0 and target.supply.needs.is_empty(),"No output room: reject cheaply before source lookup")
	target.resources.set_capacity(Resources.PLANK,40)
	check(world._request_work(actor) and target.supply.needs.size()==1 and target.resources.get_reserved_in(Resources.PLANK)==0,"UNLIMITED supplies only a bounded next kit without reserving output or WORKER")
	check(world._request_work(f.actors[1]),"Second worker can provide another needed unit of same multi-input kit")
	check(world._request_work(f.actors[2]),"Third worker can provide last missing component")
	check(target.resources.get_reserved_in(Resources.LOG)==2 and target.resources.get_reserved_in(Resources.STONE)==1 and target.supply.needs.size()==1 and target.production_batches.is_empty(),"Three accepted deliveries cover exactly one LOG2+STONE1 kit, not unbounded prefetch")
	for worker in f.actors: check(worker.self_logistics.task().is_empty(),"Busy supplier cannot create another delivery")
	world.free()

func ground_capacity_and_pointer() -> void:
	var f=setup_supply_world(); var world=f.world; var target=f.target
	target.definition.production_recipes[1].inputs={Resources.LOG:1,Resources.PLANK:1}
	target.set_production_order(A,1); target.set_production_order(B,1)
	var stack=Stacks.create(world.ground_resources,Resources.LOG,3,Coordinates.to_sim(Vector3(1,0,10)))
	world.warehouse_data.resources.add(Resources.STONE,1)
	for actor in f.actors: check(world._request_work(actor),"Concurrent suppliers reserve required ground units")
	check(stack.reserved_total()==3 and target.resources.get_reserved_in(Resources.LOG)==3 and target.supply.needs.size()==2,"A LOG2 kit and B LOG1 kit own exactly three separate units of one stack")
	target.set_recipe_mode(A,Mode.OFF)
	check(stack.reserved_total()==1 and target.resources.get_reserved_in(Resources.LOG)==1 and world.logistics.get_job(f.actors[1].data.id).is_active(),"Cancelling A keeps B's ground-stack reservation intact")
	world.free()
	# A prepared START and a SUPPLY rotate the same priority cursor.
	f=setup_supply_world(); world=f.world; target=f.target
	target.resources.add(Resources.LOG,1); target.resources.add(Resources.STONE,1)
	world.warehouse_data.resources.add(Resources.LOG,2)
	target.set_production_order(A,1); target.set_production_order(B,1)
	check(world._request_work(f.actors[0]),"Round-robin accepts A supply")
	check(world._request_work(f.actors[1]) and f.actors[1].recipe_work.batch.recipe_id==B,"Next peer recipe receives START, sharing SUPPLY's cursor")
	check(int(target._recipe_cursors[Mode.ORDER])==2,"Successful B START advances the same ORDER pointer")
	world.free()
	# Fixed external inbound covers a shortage without a second self-haul.
	f=setup_supply_world(); world=f.world; target=f.target
	target.resources.add(Resources.LOG,1); target.resources.add(Resources.STONE,1)
	target.resources.reserve_in(Resources.LOG,1)
	world.warehouse_data.resources.add(Resources.LOG,5)
	check(f.actors[0].self_logistics.task().is_empty() and target.supply.needs.is_empty(),"An unrelated confirmed inbound already covers the next complete kit")
	world.free()
	# Capacity limits the sum of batches and useful future kits, even for UNLIMITED.
	f=setup_supply_world(); world=f.world; target=f.target
	target.resources.add(Resources.STONE,2)
	target.definition.production_recipes[2].inputs={Resources.STONE:1}
	target.set_recipe_mode(B,Mode.UNLIMITED); target.set_recipe_mode(C,Mode.UNLIMITED)
	world.warehouse_data.resources.add(Resources.LOG,4)
	check(world._request_work(f.actors[0]),"One kit in transit uses one planning allowance")
	check(world._request_work(f.actors[1]) and world._request_work(f.actors[2]),"Other two places still accept useful local STARTs")
	var lookup_calls: Array=[0]
	var unavailable=func(_resource): lookup_calls[0]+=1; return null
	check(target.supply.needs.size()+target.production_batches.size()==3 and target.select_production_work("extra",unavailable).is_empty() and not target.supply.allows(B) and not target.supply.allows(C) and lookup_calls[0]<=2,"Full planning horizon permits remaining units of its existing kit, never another future kit")
	world.free()

func run() -> void:
	priorities_and_physical()
	shared_inputs_and_modes()
	cancellation_and_failures()
	limits_and_selection()
	ground_capacity_and_pointer()
	# Optional external diagnostic artifact; ordinary regression needs no local output path.
	var output_path := OS.get_environment("VILLAGE_SUPPLY_MEASUREMENTS")
	if not output_path.is_empty():
		var file=FileAccess.open(output_path,FileAccess.WRITE)
		check(file!=null,"Requested diagnostic artifact is writable")
		if file!=null:
			file.store_string(JSON.stringify(measures,"\t"))
			file.close()
	print("Recipe supply: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
