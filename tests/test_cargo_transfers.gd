extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Inventory=preload("res://scripts/resident_inventory.gd")
const Drop=preload("res://scripts/cargo_drop_result.gd")
const R=preload("res://scripts/resource_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const S=preload("res://scripts/resource_source_ref.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const Job=preload("res://scripts/haul_job.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(4000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving():break
func start_haul(world: Node,actor: Node,dest: RefCounted) -> RefCounted:
	check(world.logistics.use_executor(actor.data,world.game_time,world.world_locations,actor.intents,actor.schedule),"Executor available")
	var ref=S.new(S.Kind.CONTAINER,world.warehouse_data.id)
	var job=world.logistics.claim_transport(actor.data.id,ref,dest,R.FOOD,func():return true)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Real owned haul starts")
	return job
func run() -> void:
	var inventory=Inventory.new()
	var state:={"units":1,"calls":0,"nested":true}
	var take=func():
		state.calls+=1
		state.nested=inventory.put(R.STONE,1)
		inventory.clear()
		state.units-=1
		return true
	check(inventory.receive(R.FOOD,1,take) and inventory.amount==1 and inventory.resource_type==R.FOOD and state.units==0 and not state.nested,"Pickup owns the inventory slot during source callbacks")
	check(not inventory.receive(R.FOOD,1,take) and state.calls==1,"Repeated pickup cannot consume source twice")
	var refused=func():return false
	check(not inventory.deliver(R.FOOD,1,refused) and inventory.amount==1,"Failed delivery retains cargo")
	var changed=func():
		inventory.clear()
		check(not inventory.put(R.STONE,1),"Changed observer cannot replace transferred cargo")
	inventory.changed.connect(changed)
	var sent:={"units":0}
	var accept=func():
		check(inventory.amount==1,"Inventory stays owned until destination confirms")
		check(not inventory.deliver(R.FOOD,1,refused),"Nested delivery is rejected")
		inventory.clear()
		sent.units+=1
		return true
	check(inventory.deliver(R.FOOD,1,accept) and inventory.amount==0 and sent.units==1,"Destination receives exactly one confirmed unit")
	check(not inventory.deliver(R.FOOD,1,accept) and sent.units==1,"Repeated delivery is inert")
	inventory.changed.disconnect(changed)
	check(not inventory.receive(R.FOOD,1,refused) and inventory.amount==0,"Failed pickup leaves empty inventory untouched")
	check(not inventory.receive(R.FOOD,2,take) and state.calls==1,"Invalid quantity never calls source")
	for bad in [Drop.Status.FAILED,true,null,99]:
		inventory.put(R.LOG,1)
		check(inventory.drop_cargo(func(_r,_q):return bad)==Drop.Status.FAILED and inventory.amount==1,"Missing/invalid outcome never licenses destruction")
		inventory.clear()
	inventory.put(R.LOG,1)
	var placed:={"units":0}
	var place=func(resource,quantity):
		check(resource==R.LOG and quantity==1 and inventory.amount==1,"Drop sees the original owned cargo before acknowledgement")
		check(inventory.drop_cargo(Callable())==Drop.Status.FAILED,"Nested drop is rejected")
		inventory.clear()
		placed.units+=1
		return Drop.Status.PLACED
	check(inventory.drop_cargo(place)==Drop.Status.PLACED and inventory.amount==0 and placed.units==1,"Acknowledged placement clears once")
	check(inventory.drop_cargo(place)==Drop.Status.FAILED and placed.units==1,"Repeated drop cannot manufacture another resource")
	inventory.put(R.LOG,1)
	var attempts:={"count":0}
	var exhaust=func(_r,_q):
		attempts.count+=1 # Test double for a completed, unsuccessful placement attempt.
		return Drop.Status.DISCARDED
	check(inventory.drop_cargo(exhaust)==Drop.Status.DISCARDED and inventory.amount==0 and attempts.count==1,"Explicit disposal outcome clears only after the attempt")
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.debug_set_time_of_day(7,0)
	world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	await physics_frame
	var result: Dictionary=world.debug_spawn.spawn_building(Vector3(20,0,-20),D.for_type(T.FOOD))
	check(result.ok,"Real destination fixture")
	var dest: RefCounted=result.objects[0]
	var actor=world.resident_runtimes[0]
	var handler: Callable=world.logistics.cargo_drop_handler
	var base_stock: int=world.warehouse_data.resources.get_amount(R.FOOD)
	var job=start_haul(world,actor,dest)
	var executor=world.logistics._executors[actor.data.id]
	check(executor.cancel("before") and not executor.cancel("again") and actor.data.inventory.amount==0,"Cancel before pickup releases without cargo")
	check(world.warehouse_data.resources.get_reserved_out(R.FOOD)==0 and dest.resources.get_reserved_in(R.FOOD)==0,"Both promises released before pickup")
	# Source callback requests cancellation while Inventory owns an in-flight unit.
	job=start_haul(world,actor,dest)
	var source_callback=func(resource,_quantity):
		if resource==R.FOOD:
			executor._complete_arrival(executor._haul_intent)
			executor._on_arrival(executor._haul_intent)
			executor.cancel("during pickup")
	world.warehouse_data.resources.changed.connect(source_callback)
	var drops_before: int=Stacks.total(world.ground_resources)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	world.warehouse_data.resources.changed.disconnect(source_callback)
	check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and Stacks.total(world.ground_resources)==drops_before+1,"Cancel during pickup drops exactly the obtained unit")
	check(world.warehouse_data.resources.get_amount(R.FOOD)==base_stock-1 and dest.resources.get_reserved_in(R.FOOD)==0,"Pickup cancellation consumes source once and releases inbound")
	# Drop handler failure is not normal no-space disposal; retain cargo in the existing inventory.
	job=start_haul(world,actor,dest)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	check(actor.data.inventory.amount==1,"Legacy source-to-inventory transfer")
	var calls:={"count":0}
	world.logistics.cargo_drop_handler=func(_r,_q,_id):
		calls.count+=1
		executor.cancel("nested drop")
		actor.data.inventory.clear()
		return Drop.Status.FAILED
	var release_observations: Array=[]
	var release_callback=func(_kind):
		actor.data.inventory.clear()
		release_observations.append(actor.data.inventory.amount)
	dest.resources.reservations_changed.connect(release_callback)
	drops_before=Stacks.total(world.ground_resources)
	check(executor.cancel("failed handler") and actor.data.inventory.amount==1 and executor.last_drop_result==Drop.Status.FAILED,"Failed cancel drop preserves inventory despite callbacks")
	check(not executor.cancel("repeat") and calls.count==1 and Stacks.total(world.ground_resources)==drops_before and dest.resources.get_reserved_in(R.FOOD)==0,"Repeat cleanup cannot retry or duplicate failed cargo; promises still released")
	dest.resources.reservations_changed.disconnect(release_callback)
	check(not release_observations.is_empty() and release_observations.all(func(value):return value==1),"Release callbacks cannot clear the protected cargo")
	world.logistics.cargo_drop_handler=handler
	check(actor.data.inventory.drop_cargo(world.logistics.drop_cargo.bind(actor.data.id))==Drop.Status.PLACED and actor.data.inventory.amount==0,"Explicit corrected operation can place retained cargo")
	# Existing policy cancels a haul if its source disappears even after pickup; cargo survives on ground.
	job=start_haul(world,actor,dest)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	drops_before=Stacks.total(world.ground_resources)
	world.logistics.remove_building(world.warehouse_data.id)
	check(job.state==Job.State.CANCELLED and actor.data.inventory.amount==0 and Stacks.total(world.ground_resources)==drops_before+1 and dest.resources.get_reserved_in(R.FOOD)==0,"Source loss after pickup preserves exactly the carried unit under existing cancellation policy")
	world.logistics.register_building(world.warehouse_data)
	# Destination callback cancels during a successful commit: no post-delivery second drop.
	job=start_haul(world,actor,dest)
	walk(actor)
	world.game_time.debug_skip_minutes(10)
	walk(actor)
	var before_delivery: int=dest.resources.get_amount(R.FOOD)
	drops_before=Stacks.total(world.ground_resources)
	var delivery_callback=func(resource,_amount):
		if resource==R.FOOD:
			executor._complete_arrival(executor._haul_intent)
			executor.cancel("during delivery")
	dest.resources.changed.connect(delivery_callback)
	world.game_time.debug_skip_minutes(10)
	dest.resources.changed.disconnect(delivery_callback)
	check(job.state==Job.State.COMPLETED and actor.data.inventory.amount==0 and dest.resources.get_amount(R.FOOD)==before_delivery+1 and Stacks.total(world.ground_resources)==drops_before,"Cancellation callback cannot duplicate a completed delivery")
	# Builder direct abort during source callbacks is deferred like forced interruption.
	check(world.warehouse_data.resources.add(R.PLANK,10),"Explicit boards for cargo-cancellation regression")
	var builder=world.resident_runtimes[1]
	check(world.player_control.assign_profession(builder.data.id,P.BUILDER),"Builder assignment")
	var definition=D.for_type(T.HOME)
	definition.construction_requirements={R.PLANK:2} # Existing one-material handling fixture.
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	world._select_building_definition(definition)
	world.placement.update_world_position(Vector3(-10,0,25))
	var site=world.placement.confirm()
	world._cancel_active_world_tool()
	check(site!=null and builder.builder.request_work(),"Real construction material trip")
	var material_type: int=builder.builder._resource
	var building_source: Variant=builder.builder.sources.resolve(builder.builder.source_ref)
	var held_container=building_source.resources
	var abort_callback=func(changed_resource,_amount):
		if changed_resource==material_type:
			builder.builder._complete_arrival(builder.builder._intent)
			builder.builder._on_arrival(builder.builder._intent)
			builder.builder.abort("source callback",false)
	held_container.changed.connect(abort_callback)
	drops_before=Stacks.total(world.ground_resources)
	walk(builder)
	world.game_time.debug_skip_minutes(10)
	held_container.changed.disconnect(abort_callback)
	check(builder.builder.phase==builder.builder.Phase.NONE and builder.data.inventory.amount==0 and Stacks.total(world.ground_resources)==drops_before+1,"Builder abort during pickup drops one unit without recursive cleanup")
	check(site.active_builder_ids.is_empty() and site.get_construction_reserved_in(material_type)==0,"Builder callback cancellation releases slot/inbound")
	check(builder.builder.request_work(),"Builder may receive another task")
	walk(builder)
	world.game_time.debug_skip_minutes(10)
	check(builder.data.inventory.amount==1,"Builder holds one material before drop failure")
	var builder_calls:={"count":0}
	var builder_handler: Callable=builder.builder.cargo_drop_handler
	builder.builder.cargo_drop_handler=func(_r,_q):
		builder_calls.count+=1
		builder.builder.abort("nested builder",false)
		builder.data.inventory.clear()
		return Drop.Status.FAILED
	builder.builder.abort("failed builder handler",false)
	builder.builder.abort("repeat builder",false)
	check(builder_calls.count==1 and builder.data.inventory.amount==1 and builder.builder.phase==builder.builder.Phase.NONE and site.active_builder_ids.is_empty(),"Builder API error retains cargo and repeated cleanup stays inert")
	check(site.get_construction_reserved_in(material_type)==0,"Failed builder drop still releases inbound")
	check(builder.data.inventory.drop_cargo(builder_handler)==Drop.Status.PLACED,"Explicit legacy placement resolves retained builder cargo")
	check(world.ground_resources.is_stack_mode(),"Canonical stack placement is enabled")
	world.free()
	print("Cargo transfers: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
