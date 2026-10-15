extends SceneTree
const B = preload("res://scripts/building_instance.gd")
const Def = preload("res://scripts/building_definition.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
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
func building(world: Node, type: int, point: Vector3, built: bool = true):
	var result = B.new(StringName("food_test_%d" % world.buildings.size()),Def.for_type(type),C.to_sim(point),B.State.BUILT if built else B.State.UNDER_CONSTRUCTION)
	world.buildings.append(result)
	world._show_building(result)
	return result
func empty(world: Node) -> void:
	for place in world.buildings: place.resources.try_take(R.FOOD,place.resources.get_available_amount(R.FOOD))
func walk(actor: Node) -> void:
	for step in range(12000):
		if actor.needs._meal_active or actor.view._waiting or not actor.view.movement.is_moving(): break
		actor.view._physics_process(0.05)
func meal(world: Node, actor: Node) -> void:
	walk(actor)
	check(actor.needs._meal_active and actor.data.activity == Activity.EATING,"Real physical arrival begins paid eating")
	check(actor.data.hunger == 80,"No remote/arrival instant satiety")
	world.game_time.debug_skip_minutes(actor.needs._minutes_left)
	check(actor.data.hunger == 20 and not actor.needs._meal_active and actor.needs._active_intent == null,"Committed meal duration reduces hunger by sixty once and completes")
	check(actor.view._marker == null and not actor.view._waiting,"Meal completion releases portal slot/wait")
func capture(label: String, actor: Node) -> void:
	if not "--rendered" in OS.get_cmdline_user_args(): return
	var camera := root.get_camera_3d()
	var forward := -camera.global_basis.z
	var center := camera.global_position + forward*(-camera.global_position.y/forward.y)
	var focus: Vector3 = actor.view.global_position
	camera.global_position += Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.set_zoom_distance(18 / (2 * tan(deg_to_rad(camera.fov / 2))))
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/resident-food-sources/" + label + ".png") == OK,"Rendered food capture")
func run() -> void:
	var world = fixture()
	var actor = world.resident_runtimes[1]
	var kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	kitchen.resources.add(R.FOOD,3)
	var storage = building(world,T.STORAGE,Vector3(-8,0,16))
	storage.resources.add(R.FOOD,3)
	var drop = world.ground_resources.create_drop(R.FOOD,3,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.has_food_action() and actor.needs.try_eat(8000),"Normal need selects food")
	check(actor.needs._food_building == kitchen,"Farther Kitchen outranks nearer Town Center/Storage/Ground")
	check(kitchen.resources.get_amount(R.FOOD) == 3 and kitchen.resources.get_reserved_out(R.FOOD) == 1,"Trip reserves, never remotely consumes")
	walk(actor)
	check(world.building_uses.occupied_by(kitchen.id,actor.data.id,2),"Kitchen still uses VISITOR")
	world.resident_selection.select(actor.data)
	await capture("kitchen_eating",actor)
	meal(world,actor)
	check(kitchen.resources.get_amount(R.FOOD) == 2 and storage.resources.get_amount(R.FOOD) == 3 and drop.amount == 3,"Only selected Kitchen portion consumed")
	world.free()
	# Stable tier-two registry selection and a reserved Kitchen's fallback.
	world = fixture()
	actor = world.resident_runtimes[1]
	kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	kitchen.resources.add(R.FOOD,1)
	kitchen.resources.reserve_out(R.FOOD,1)
	storage = building(world,T.STORAGE,Vector3(-10,0,16))
	storage.resources.add(R.FOOD,3)
	check(actor.needs.try_eat(8000) and actor.needs._food_building == world.warehouse_data,"Reserved Kitchen unavailable; first registry Other Building is stable")
	actor.commands.move_to(Vector2(0,500))
	actor.commands.cancel_current()
	check(actor.needs.try_eat(8000) and actor.needs._food_building == world.warehouse_data,"Unchanged tier-two choice reproducible after release")
	actor.commands.move_to(Vector2(0,500))
	kitchen.resources.release_out(R.FOOD,1)
	world.free()
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000) and actor.needs._food_source.kind == Source.Kind.GROUND,"Empty Kitchen skipped even while its object exists")
	meal(world,actor)
	check(kitchen.resources.get_amount(R.FOOD) == 0,"Empty Kitchen never creates free food")
	world.free()
	# Other buildings preserve registry ordering and share real COURIER access.
	for type in [T.TOWN_CENTER,T.STORAGE,T.GATHERER_HUT]:
		world = fixture()
		actor = world.resident_runtimes[1]
		empty(world)
		var target = world.warehouse_data if type == T.TOWN_CENTER else building(world,type,Vector3(-10,0,16))
		target.resources.add(R.FOOD,1)
		check(actor.needs.try_eat(8000) and actor.needs._food_building == target,"Other compatible BUILT food container selected")
		check(actor.intents.current_intent.slot_purpose == 1,"Other building uses existing COURIER")
		walk(actor)
		check(target.resources.get_amount(R.FOOD) == 0 and not world.building_uses.occupied_by(target.id,actor.data.id,1) and actor.view._marker==null,"Pickup then portal exit releases courier before outside eating")
		world.resident_selection.select(actor.data)
		await capture("building_%d_eating" % type,actor)
		meal(world,actor)
		world.free()
	# Exclusive Ground claims, partial quantities, interruption and meal merge.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	var second = world.resident_runtimes[2]
	second.view.global_position=actor.view.global_position+Vector3(0,0,1) # Both eligible for the same local portion.
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000) and not second.needs.try_eat(8000),"Two hungry residents cannot reserve one Ground portion")
	check(drop.amount == 1 and drop.reservation_owner_id == StringName("meal:" + actor.data.id),"Existing exclusive claim, no resource copy")
	actor.commands.move_to(Vector2(0,500))
	check(drop.amount == 1 and drop.reservation_owner_id.is_empty(),"PlayerCommand before arrival releases claim without loss")
	actor.commands.cancel_current()
	check(second.needs.try_eat(8000),"Released Ground is reusable")
	walk(second)
	check(world.ground_resources.get_by_id(drop.id) == null and second.data.inventory.amount == 0,"Actual consumption removes last Ground without cargo/HaulJob")
	var active = second.intents.current_intent
	check(second.needs.try_eat(10000,200) and second.intents.current_intent == active and second.needs._minutes_left == 10,"Critical hunger merges already-paid Ground meal after source removal")
	world.resident_selection.select(second.data)
	await capture("ground_eating",second)
	meal(world,second)
	check(world.logistics.get_job(second.data.id) == null,"Personal eating creates no haul")
	world.free()
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	drop = world.ground_resources.create_drop(R.FOOD,4,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000),"Multi-unit Ground FOOD supported")
	meal(world,actor)
	check(drop.amount == 3 and drop.reservation_owner_id.is_empty() and world.ground_resources.get_by_id(drop.id) == drop,"One portion consumed, same remaining Ground ID released")
	world.free()
	# Container competition and cancellation ownership.
	world = fixture()
	empty(world)
	world.warehouse_data.resources.add(R.FOOD,1)
	actor = world.resident_runtimes[1]
	second = world.resident_runtimes[2]
	check(actor.needs.try_eat(8000) and not second.needs.try_eat(8000),"One building FOOD promises one meal only")
	actor.commands.move_to(Vector2(0,500))
	check(world.warehouse_data.resources.get_amount(R.FOOD) == 1 and world.warehouse_data.resources.get_reserved_out(R.FOOD) == 0,"Container interruption releases only own promise")
	check(second.needs.try_eat(8000),"Second resident claims released building portion")
	meal(world,second)
	world.free()
	# Occupied courier is a wait, never a premature Ground fallback.
	world = fixture()
	actor = world.resident_runtimes[1]
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	var marker = world.building_uses.acquire(world.warehouse_data.id,1,"courier_test",Vector3.ZERO)
	check(actor.needs.try_eat(8000) and actor.needs._food_building == world.warehouse_data,"Busy courier does not downgrade building tier")
	walk(actor)
	check(actor.view._waiting and not actor.needs._meal_active and world.warehouse_data.resources.get_amount(R.FOOD) == 20,"Wait retains FOOD promise, no remote consumption")
	world.building_uses.release(world.warehouse_data.id,marker,"courier_test")
	await process_frame
	check(actor.needs._meal_active,"Slot release wakes through unchanged executor")
	meal(world,actor)
	check(drop.amount == 1,"Ground alternative untouched")
	world.free()
	# Reachability before reservation, topology invalidation and source loss.
	world = fixture()
	actor = world.resident_runtimes[1]
	kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	var other = building(world,T.FOOD,Vector3(-8,0,16))
	kitchen.resources.add(R.FOOD,1)
	other.resources.add(R.FOOD,1)
	var entrance: Vector3 = world.building_uses.entrance(kitchen.id)
	world.navigation.add_blocker(&"food_blocked",Rect2(C.world_plane(entrance)-Vector2.ONE,Vector2.ONE*2))
	check(actor.needs.try_eat(8000) and actor.needs._food_building == other,"Unreachable first Kitchen skipped for reachable second")
	check(kitchen.resources.get_reserved_out(R.FOOD) == 0,"No reservation for unreachable Kitchen")
	world.free()
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000),"Source loss scenario begins")
	world.ground_resources.remove_drop(drop)
	await process_frame
	check(actor.needs._active_intent == null and drop.reservation_owner_id.is_empty(),"Removed Ground clears owned action/claim")
	world.warehouse_data.resources.add(R.FOOD,1)
	check(actor.needs.try_eat(8000) and actor.needs._food_building == world.warehouse_data,"Next food decision finds alternative building")
	meal(world,actor)
	world.free()
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	var unfinished = building(world,T.STORAGE,Vector3(-8,0,16),false)
	unfinished.resources.set_capacity(R.FOOD,5)
	unfinished.resources.add(R.FOOD,5)
	check(not actor.needs.has_food_action() and not actor.needs.try_eat(8000),"Unfinished stocked building not a food source")
	var probes: int = actor.needs.food_probe_count
	for iteration in range(50): check(not actor.needs.has_food_action(),"Repeated empty availability remains false")
	check(actor.needs.food_probe_count == probes,"Unchanged negative food probe does not repeat searches")
	world.free()
	# Real Porter ownership competes with personal Ground consumption.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	var porter = world.resident_runtimes[0]
	porter.view.global_position=actor.view.global_position+Vector3(0,0,1) # Both search circles include the contested portion.
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	var job = world.logistics.claim_best_job(porter.data.id)
	check(job != null and drop.reservation_owner_id == job.id,"Normal Porter claim owns last Ground FOOD")
	check(not actor.needs.try_eat(8000) and drop.amount == 1,"Hungry resident cannot steal Porter claim")
	world.logistics.cancel_job(job)
	await process_frame
	check(actor.needs.try_eat(8000),"Released Porter claim permits personal meal")
	check(world.logistics.claim_best_job(porter.data.id) == null,"Porter cannot claim personal reserved Ground FOOD")
	meal(world,actor)
	check(world.warehouse_data.resources.get_reserved_in(R.FOOD) == 0,"Cancelled competition leaves no inbound promise")
	world.free()
	# A walkable target inside a disconnected region is rejected before any claim.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	actor.view.global_position=Vector3(-8,0,11) # Circle includes the enclosed source, but no path crosses its walls.
	drop = world.ground_resources.create_drop(R.FOOD,1,C.to_sim(Vector3(-8,0,14)))
	var walls := [Rect2(-10,12,0.5,4),Rect2(-6.5,12,0.5,4),Rect2(-10,12,4,0.5),Rect2(-10,15.5,4,0.5)]
	for index in walls.size(): world.navigation.add_blocker(StringName("food_wall_%d" % index),walls[index])
	check(world.navigation.is_world_walkable(C.to_world(drop.world_position)),"Food point itself walkable inside disconnected ring")
	check(not actor.needs.has_food_action() and not actor.needs.try_eat(8000) and drop.reservation_owner_id.is_empty(),"Disconnected FOOD offers no false action/claim")
	for index in walls.size(): world.navigation.remove_blocker(StringName("food_wall_%d" % index))
	check(actor.needs.has_food_action() and actor.needs.try_eat(8000),"Topology change invalidates unavailable probe")
	meal(world,actor)
	world.free()
	# A navigation edit during a committed trip uses normal movement failure cleanup.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	actor.view.global_position=Vector3(-8,0,11)
	drop = world.ground_resources.create_drop(R.FOOD,1,C.to_sim(Vector3(-8,0,14)))
	check(actor.needs.try_eat(8000),"Navigation edit starts with a real Ground claim")
	actor.view._physics_process(0.05)
	world.navigation.add_blocker(&"food_mid_trip",Rect2(-9,13,2,2))
	actor.view._physics_process(0.05)
	check(actor.needs._active_intent == null and drop.reservation_owner_id.is_empty() and drop.amount == 1,"Blocked committed target releases claim without eating")
	check(actor.data.hunger == 80 and not actor.needs._meal_active,"Movement failure gives no free satiety")
	world.warehouse_data.resources.add(R.FOOD,1)
	check(actor.needs.try_eat(8000) and actor.needs._food_building == world.warehouse_data,"Movement failure permits a fresh reachable tier-two source")
	meal(world,actor)
	world.free()
	# Deleted BUILT source: captured reservation released, next source remains usable.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	storage = building(world,T.STORAGE,Vector3(-10,0,16))
	storage.resources.add(R.FOOD,1)
	check(actor.needs.try_eat(8000),"Building disappearance scenario reserves FOOD")
	world.buildings.erase(storage)
	world.logistics.remove_building(storage.id)
	world.building_uses.unregister(storage.id)
	world.world_locations.unregister(storage.id)
	check(actor.needs._active_intent == null and storage.resources.get_reserved_out(R.FOOD) == 0 and storage.resources.get_amount(R.FOOD) == 1,"Removed source cleans reservation without consuming")
	world.warehouse_data.resources.add(R.FOOD,1)
	check(actor.needs.try_eat(8000),"Alternative source available after removal")
	meal(world,actor)
	world.free()
	# Reentrant critical signal during Ground consumption keeps the same paid action.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	drop = world.ground_resources.create_drop(R.FOOD,1,actor.view.get_drop_sim_position()+Vector2(25,0))
	check(actor.needs.try_eat(8000),"Reentrant Ground scenario begins")
	var current = actor.intents.current_intent
	actor.decision._deciding = false
	var hunger_signal := func():
		if drop.amount == 0: actor.data.hunger = 100
	drop.availability_changed.connect(hunger_signal)
	walk(actor)
	check(actor.needs._meal_active and actor.intents.current_intent == current and actor.needs._minutes_left == 10 and actor.intents.forced_priority == 200,"Reentrant critical transition does not duplicate timer/consumption")
	check(world.ground_resources.get_by_id(drop.id) == null,"One reentrant Ground consumption only")
	actor.decision._deciding = true
	world.game_time.debug_skip_minutes(10)
	check(actor.data.hunger == 40,"Reentrant critical meal retains original recovery rate")
	drop.availability_changed.disconnect(hunger_signal)
	world.free()
	# Dispatcher queue cannot delay critical hunger.
	world = fixture()
	porter = world.resident_runtimes[0]
	porter.schedule._phase = "День"
	porter.data.hunger = 0
	porter.decision._deciding = false
	porter.decision.request_decision("food_regression")
	check(world.decision_dispatcher.pending_count() == 1,"Ordinary Porter decision actually queued")
	porter.data.hunger = 100
	check(porter.intents.current_intent.reason_id == &"eat" and porter.intents.forced_priority == 200 and world.decision_dispatcher.pending_count() == 0,"Critical hunger synchronously eats and invalidates queued work")
	porter.decision._deciding = true
	walk(porter)
	check(porter.needs._meal_active and world.warehouse_data.resources.get_amount(R.FOOD) == 19,"Critical Porter uses actual Town Center FOOD")
	world.game_time.debug_skip_minutes(10)
	check(porter.data.hunger == 40 and porter.intents.forced_priority == 0,"Critical meal finishes without queue-driven interference")
	world.free()
	# New critical meal must not repeatedly choose a known-full VISITOR pool.
	world = fixture()
	actor = world.resident_runtimes[1]
	kitchen = building(world,T.FOOD,Vector3(-18,0,5))
	kitchen.resources.add(R.FOOD,2)
	for index in range(4): world.building_uses.acquire(kitchen.id,2,"visitor_hold_%d" % index,Vector3.ZERO)
	actor.decision._deciding = false
	actor.data.hunger = 100
	check(actor.needs._food_building == world.warehouse_data and actor.intents.forced_priority == 200,"Critical new meal skips full Kitchen, uses compatible Other Building")
	var critical_intent = actor.intents.current_intent
	var attempts: int = actor.needs.food_search_count
	for frame in range(5): await process_frame
	check(actor.intents.current_intent == critical_intent and actor.needs.food_search_count == attempts,"Full Kitchen does not cause immediate replan loop")
	actor.decision._deciding = true
	walk(actor)
	check(actor.needs._meal_active,"Fallback critical meal enters real courier")
	world.game_time.debug_skip_minutes(10)
	check(actor.data.hunger == 40 and kitchen.resources.get_amount(R.FOOD) == 2,"Critical fallback consumes only Other Building portion")
	world.free()
	# Synchronous source removal during reserve must roll back before movement starts.
	world = fixture()
	empty(world)
	actor = world.resident_runtimes[1]
	storage = building(world,T.STORAGE,Vector3(-10,0,16))
	storage.resources.add(R.FOOD,1)
	var remove_on_reserve := func(resource, _amount):
		if resource == R.FOOD and storage.resources.get_reserved_out(R.FOOD) == 1 and storage in world.buildings:
			world.buildings.erase(storage)
			world.logistics.remove_building(storage.id)
			world.building_uses.unregister(storage.id)
			world.world_locations.unregister(storage.id)
	storage.resources.availability_changed.connect(remove_on_reserve)
	check(not actor.needs.try_eat(8000) and actor.needs._active_intent == null,"Removed reservation source never starts movement/meal")
	check(storage.resources.get_reserved_out(R.FOOD) == 0 and storage.resources.get_amount(R.FOOD) == 1 and actor.data.hunger == 80,"Reentrant rollback preserves FOOD and satiety")
	storage.resources.availability_changed.disconnect(remove_on_reserve)
	world.free()
	print("Resident food sources: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
