extends "res://tests/test_resident_food_sources.gd"
## P2 keeps notification timing; only the shared derived total is cached.
class CountedFood extends "res://scripts/food_availability.gd":
	var scans := 0
	func _count() -> int:
		scans += 1
		return super._count()

func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	world.food_availability = CountedFood.new()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes = 420
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
		actor.data.hunger = 80
	return world

func run() -> void:
	var world = fixture()
	empty(world)
	await process_frame
	var shared = world.food_availability
	for actor in world.resident_runtimes:
		check(actor.needs.food_availability == shared,"Canonical residents share one preliminary stock calculation")
	var box = world.warehouse_data.resources
	var scans: int = shared.scans
	box.add(R.FOOD,3)
	check(shared.scans == scans+1,"One food event scans sources once for whole population")
	var sum := 0
	for i in range(100): sum += shared.total()
	check(sum==300,"Repeated shared total is accurate")
	check(shared.scans==scans+1,"Repeated reads never rescan unchanged sources")
	for actor in world.resident_runtimes:
		check(actor.needs._available_food_amount==3,"Immediate add reaches each resident synchronously")
	var epochs: Array = []
	var wakes := [0]
	for actor in world.resident_runtimes:
		epochs.append(actor.needs._food_epoch)
		actor.needs.food_available.connect(func(): wakes[0] += 1)
	box.availability_changed.emit(R.FOOD,box.get_available_amount(R.FOOD))
	check(wakes[0]==0,"Duplicate notification does not invent a food increase")
	for index in range(world.resident_runtimes.size()):
		check(world.resident_runtimes[index].needs._food_epoch==epochs[index],"Unchanged stock does not invalidate individual food epoch")
	scans=shared.scans
	box.availability_changed.emit(R.LOG,box.get_available_amount(R.LOG))
	check(shared.scans==scans,"Unrelated direct container event does not rescan food")
	box.reserve_out(R.FOOD,2)
	check(shared.total()==1,"Outgoing reservations are excluded immediately")
	box.take_reserved(R.FOOD,1)
	check(shared.total()==1 and box.get_amount(R.FOOD)==2,"Physical reserved pickup preserves free count")
	box.release_out(R.FOOD,1)
	check(shared.total()==2,"Release makes stock available immediately")
	var recurse := func(resource,amount):
		if resource==R.FOOD and amount==3:box.reserve_out(R.FOOD,1)
	box.availability_changed.connect(recurse)
	box.add(R.FOOD,1)
	check(shared.total()==2 and box.get_reserved_out(R.FOOD)==1,"Nested reservation invalidates an outer notification snapshot")
	for actor in world.resident_runtimes:
		check(actor.needs._available_food_amount==2,"No resident retains stale outer-event total")
	box.availability_changed.disconnect(recurse)
	box.release_out(R.FOOD,1)
	box.try_take(R.FOOD,box.get_available_amount(R.FOOD))
	# Queue a real aggregate source event before the subsequent FOOD mutations.
	world.ground_resources.create_drop(R.LOG,1,Vector2(1000,500))
	box.add(R.FOOD,1);box.reserve_out(R.FOOD,1);box.release_out(R.FOOD,1);box.try_take(R.FOOD,1)
	check(shared.total()==0,"Several same-frame availability transitions preserve final empty state")
	box.add(R.FOOD,2)
	await process_frame
	await process_frame
	check(shared.total()==2,"Latest change survives already queued aggregate notification")
	scans=shared.scans
	shared.register_building(world.warehouse_data)
	shared.bind_sources(world.logistics.sources)
	check(shared.scans==scans,"Repeated registration/binding does not invalidate or duplicate hooks")
	var hooks:=0
	for connection in box.availability_changed.get_connections():
		if connection.callable.get_object()==shared:hooks+=1
	check(hooks==1,"Only one shared FOOD subscriber per container")
	# A shared global hint never grants identical personal ground access.
	empty(world)
	var a=world.resident_runtimes[0]
	var b=world.resident_runtimes[1]
	a.view.global_position=Vector3(-20,0,20)
	b.view.global_position=Vector3(20,0,20)
	var drop=world.ground_resources.create_drop(R.FOOD,1,C.to_sim(a.view.global_position)+Vector2(100,0))
	await process_frame
	await process_frame
	check(shared.total()==1,"Ground FOOD refresh shares one total")
	check(a.needs.has_food_action() and not b.needs.has_food_action(),"Boundary ground meal is personal despite equal global hint")
	check(a.needs.try_eat(8000) and not b.needs.try_eat(8000),"Cached hint cannot allocate a reserved portion twice")
	check(drop.amount==1 and not drop.reservation_owner_id.is_empty(),"Food reserved before movement, never remotely consumed")
	a.commands.move_to(Vector2(-400,400))
	a.commands.cancel_current()
	drop.world_position=C.to_sim(b.view.global_position)
	await process_frame
	await process_frame
	check(not a.needs.has_food_action() and b.needs.has_food_action(),"Moved FOOD invalidates personal negative and positive probes")
	check(b.needs.try_eat(8000),"Freed moved ground portion can be reserved by eligible resident")
	var owned=drop.reservation_owner_id
	b.view.global_position+=Vector3(10,0,0)
	check(b.needs._food_target_valid() and drop.reservation_owner_id==owned,"Accepted ground action survives movement beyond search circle")
	b.commands.move_to(Vector2(0,500))
	check(drop.reservation_owner_id.is_empty(),"Normal interruption still releases owned food")
	# Removing a source disconnects the observer; removing a resident removes its hooks.
	var storage=building(world,T.STORAGE,Vector3(-10,0,5))
	storage.resources.add(R.FOOD,2)
	check(shared.total()==3,"New functioning container registers in shared summary")
	world.buildings.erase(storage)
	world.logistics.remove_building(storage.id)
	world.building_uses.unregister(storage.id)
	world.world_locations.unregister(storage.id)
	await process_frame
	check(shared.total()==1,"Removed source is excluded")
	hooks=0
	for connection in storage.resources.availability_changed.get_connections():
		if connection.callable.get_object()==shared:hooks+=1
	check(hooks==0,"Removed source loses shared observer")
	var removed_needs_id: int = b.needs.get_instance_id()
	b.free()
	hooks=0
	for connection in box.availability_changed.get_connections():
		if connection.callable.get_object_id()==removed_needs_id: hooks+=1
	check(hooks==0,"Freed resident releases subscription")
	shared.invalidate()
	scans=shared.scans
	shared.total();shared.total()
	check(shared.scans==scans+1,"Repeated dirty invalidation coalesces lazy reads")
	var registry=shared
	world.free()
	check(registry._subscriptions.is_empty() and registry._sources==null,"World disposal disconnects shared source observers")
	print("P2 food updates: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
