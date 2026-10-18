extends "res://tests/test_resident_food_sources.gd"
const Catalog = preload("res://scripts/resource_catalog.gd")
const Categories = preload("res://scripts/resource_category.gd").Type
const Intent = preload("res://scripts/resident_intent.gd")

# Only this world's metadata: existing LOG stands in for a second ready dish;
# PLANK is a raw ingredient. The global catalog and the real Needs are untouched.
class TestFoods extends "res://scripts/food_availability.gd":
	var scans := 0
	func is_ready_food(resource: int) -> bool: return resource in [R.FOOD,R.LOG]
	func _count() -> int:
		scans += 1
		return super._count()

func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	world.food_availability = TestFoods.new()
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

func competing_meals() -> void:
	var world = fixture()
	empty(world)
	var box = world.warehouse_data.resources
	box.add(R.FOOD,1)
	box.add(R.LOG,1)
	var a = world.resident_runtimes[0]
	var b = world.resident_runtimes[1]
	var c = world.resident_runtimes[2]
	check(a.needs.try_eat(8000) and a.needs._meal_selection.concrete_type==R.FOOD,"Stable lowest concrete ID is selected first")
	check(b.needs.try_eat(8000) and b.needs._meal_selection.concrete_type==R.LOG,"Second resident selects another ready type in same building")
	check(box.get_reserved_out(R.FOOD)==1 and box.get_reserved_out(R.LOG)==1,"Each resident reserves its own concrete unit")
	check(not c.needs.try_eat(10000,10000) and box.get_reserved_out(R.FOOD)==1 and box.get_reserved_out(R.LOG)==1,"Critical hunger cannot steal either promise")
	var paid_intent = b.needs._active_intent
	var outcomes: Array = []
	b.needs.eat_outcome.connect(func(intent,outcome,_id): outcomes.append([intent.meal_concrete_type,outcome]))
	var social_meals: Array = []
	b.needs.meal_begun.connect(func(id): social_meals.append(id))
	var routes: int = b.needs.food_route_checks
	box.try_take(R.PLANK,1)
	check(b.needs._food_target_valid() and b.needs._active_intent==paid_intent and b.needs.food_route_checks==routes,"Other stock changes do not replace a promised dish or run routes")
	meal(world,b)
	check(paid_intent.meal_concrete_type==R.LOG and outcomes==[[R.LOG,&"completed"]] and social_meals==[&""],"Concrete type survives completion; outside meal signal keeps old building-ID contract")
	check(box.get_amount(R.LOG)==0 and box.get_amount(R.FOOD)==1 and box.get_reserved_out(R.FOOD)==1,"Exact selected dish is consumed; other resident's promise stays")
	a.commands.move_to(Vector2(0,500))
	check(box.get_reserved_out(R.FOOD)==0 and box.get_reserved_out(R.LOG)==0,"Cancellation releases only matching type")
	check(Catalog.is_ready_food(R.FOOD) and not Catalog.is_ready_food(R.LOG) and not Catalog.is_ready_food(R.PLANK),"Fixture never mutates production metadata")
	world.free()

func invalidation() -> void:
	var world = fixture()
	empty(world)
	var a = world.resident_runtimes[0]
	var box = world.warehouse_data.resources
	var shared = world.food_availability
	box.add(R.FOOD,2)
	var before = a.needs._select_meal(false)
	check(before.concrete_type==R.FOOD and shared.total()==2,"Positive proposal identifies exact dish")
	# Exercise atomic stock replacement through the existing container transaction.
	box.reserve_out(R.FOOD,2)
	box.reserve_in(R.LOG,2)
	check(not a.needs.has_food_action(),"No free dish produces negative probe")
	check(box.transform_reserved({R.FOOD:2},{R.LOG:2}),"Both concrete ledgers change before callbacks")
	check(not a.needs._begin_meal(before,8000,0) and box.get_reserved_out(R.LOG)==0,"Stale FOOD proposal cannot silently claim another ready product")
	check(a.needs.try_eat(8000) and a.needs._meal_selection.concrete_type==R.LOG,"Fresh normal decision chooses newly available concrete type")
	a.commands.move_to(Vector2(0,500)); a.commands.cancel_current()
	# Same total at every notification: nested mutation is complete before shared scan.
	box.try_take(R.LOG,2)
	box.add(R.FOOD,2)
	before = a.needs._select_meal(false)
	var total_before: int = shared.total()
	var revision: int = shared.content_revision
	var nested := func(_type,_amount):
		box.add(R.LOG,2)
	# Run this callback before the shared observer, preserving all real stock APIs.
	box.availability_changed.disconnect(shared._resource_changed)
	box.availability_changed.disconnect(a.needs._on_food_availability_changed)
	box.availability_changed.connect(nested,CONNECT_ONE_SHOT)
	box.availability_changed.connect(shared._resource_changed)
	box.availability_changed.connect(a.needs._on_food_availability_changed)
	box.try_take(R.FOOD,2)
	check(shared.total()==total_before and shared.content_revision>revision,"Shared generation observes different composition at unchanged total")
	check(a.needs._select_meal(false).concrete_type==R.LOG and not a.needs._begin_meal(before,8000,0),"Cached FOOD is rejected and current composition is selectable")
	var scans: int = shared.scans
	var route_checks: int = a.needs.food_route_checks
	for index in range(100): shared.total(); a.needs.has_food_action()
	check(shared.scans==scans and a.needs.food_route_checks==route_checks,"Unchanged reads reuse one shared summary and current source probe")
	world.free()

func geometry_and_ground() -> void:
	var world = fixture()
	empty(world)
	var actor = world.resident_runtimes[0]
	var box = world.warehouse_data.resources
	check(world.food_availability.total()==0 and not actor.needs.has_food_action(),"Existing raw PLANK stock is not edible")
	box.add(R.FOOD,1); box.add(R.LOG,1)
	world.logistics.sources.route_available = func(_from,_to): return false
	var routes: int = actor.needs.food_route_checks
	check(not actor.needs.has_food_action() and actor.needs.food_route_checks==routes+1,"Two dishes in one unreachable building require one route probe")
	world.logistics.sources.route_available = Callable()
	world.food_availability.invalidate()
	box.set_category_quota(Categories.SIMPLE_FOOD,0)
	box.try_take(R.LOG,1)
	check(actor.needs.try_eat(8000) and box.get_reserved_out(R.FOOD)==1,"Zero import quota does not hide existing ready FOOD")
	meal(world,actor)
	actor.data.hunger = 80
	var drop = Stacks.create(world.ground_resources,R.LOG,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	await process_frame
	check(actor.needs.try_eat(8000) and actor.needs._food_source.kind==Source.Kind.GROUND,"Second ready type uses real ground SourceRef")
	var intent = actor.needs._active_intent
	walk(actor)
	check(actor.needs._meal_active and world.ground_resources.get_by_id(drop.id)==null and intent.meal_concrete_type==R.LOG,"Paid ground dish retains identity after last stack removal")
	world.game_time.debug_skip_minutes(3)
	actor.commands.move_to(Vector2(0,500))
	check(actor.data.hunger==62 and intent.meal_concrete_type==R.LOG and world.ground_resources.get_by_id(drop.id)==null,"Interruption preserves benefit and does not refund consumed dish")
	world.free()

func kitchen_and_reentrancy() -> void:
	var world = fixture()
	empty(world)
	var actor = world.resident_runtimes[0]
	var kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	kitchen.resources.set_allowed_resource_types([R.FOOD,R.LOG])
	kitchen.resources.set_capacity(R.LOG,2)
	kitchen.resources.add(R.LOG,2)
	var outcomes: Array = []
	actor.needs.meal_begun.connect(func(id): outcomes.append(id))
	check(actor.needs.try_eat(8000) and actor.needs._food_building==kitchen and actor.needs._meal_selection.concrete_type==R.LOG,"Kitchen tier applies to every ready concrete dish")
	walk(actor)
	check(actor.needs._minutes_left==30 and world.building_uses.occupied_by(kitchen.id,actor.data.id,2) and outcomes==[kitchen.id],"Second dish retains VISITOR and original meal signal")
	meal(world,actor)
	actor.data.hunger = 80
	var nested: Array = []
	kitchen.resources.availability_changed.connect(func(_type,_amount): nested.append(actor.needs.try_eat(8000)))
	check(actor.needs.try_eat(8000) and nested==[false] and kitchen.resources.get_reserved_out(R.LOG)==1,"Nested claim cannot create another reservation")
	var current = actor.needs._active_intent
	kitchen.resources.changed.connect(func(_type,_amount): actor.needs._on_arrival(current))
	meal(world,actor)
	check(kitchen.resources.get_amount(R.LOG)==0 and kitchen.resources.get_reserved_out(R.LOG)==0,"Nested arrival cannot consume a second unit")
	world.free()

func command_during_claim() -> void:
	var world = fixture()
	empty(world)
	var actor = world.resident_runtimes[0]
	var box = world.warehouse_data.resources
	box.add(R.FOOD,1)
	var commands: Array = []
	box.availability_changed.connect(func(_type,_amount):
		actor.commands.move_to(Vector2(0,500))
		commands.append(actor.intents.current_intent),CONNECT_ONE_SHOT)
	check(not actor.needs.try_eat(10000,10000) and actor.intents.player_controlled and actor.intents.current_intent==commands[0],"Player command inside claim is not replaced by a food intent")
	check(box.get_reserved_out(R.FOOD)==0 and box.get_amount(R.FOOD)==1 and actor.needs._meal_selection==null,"Interrupted claim rolls back the selected unit without consumption")
	world.free()

func critical_rest_during_claim() -> void:
	var world = fixture()
	empty(world)
	var actor = world.resident_runtimes[0]
	var box = world.warehouse_data.resources
	box.add(R.FOOD,1)
	var rest: Array = []
	box.availability_changed.connect(func(_type,_amount):
		actor.needs.try_rest(20000,20000)
		rest.append(actor.needs._active_intent),CONNECT_ONE_SHOT)
	check(not actor.needs.try_eat(10000,10000) and actor.needs._active_intent==rest[0] and actor.intents.current_intent==rest[0],"Higher critical sleep during reserve remains immediate and keeps its executor")
	check(box.get_reserved_out(R.FOOD)==0 and actor.needs._meal_selection==null,"Interrupted food claim releases only its reservation")
	world.free()

func run() -> void:
	competing_meals()
	invalidation()
	await geometry_and_ground()
	kitchen_and_reentrancy()
	command_during_claim()
	critical_rest_during_claim()
	print("Concrete meals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
