extends "res://tests/test_sawmill.gd"
const Catalog = preload("res://scripts/resource_catalog.gd")
const Categories = preload("res://scripts/resource_category.gd").Type
const Instance = preload("res://scripts/building_instance.gd")
const Batch = preload("res://scripts/production_batch.gd")
const Slots = preload("res://scripts/world_3d/building_slot_3d.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Job = preload("res://scripts/haul_job.gd")
const DropResult = preload("res://scripts/cargo_drop_result.gd")
var observer: Callable

func quiet_world() -> Node:
	var world=scene()
	for building in world.buildings:
		for resource in Resources.values(): building.resources.try_take(resource,building.resources.get_amount(resource))
	for actor in world.resident_runtimes:
		for need in actor.data.needs.values(): need.base_weight=0
	return world
func arrive(actor: Node) -> void:
	for step in range(3000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func idle(actor: Node) -> void:
	if actor.commands.active_command!=null: actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
func observe(world: Node, label: String) -> void:
	if observer.is_valid(): await observer.call(world,label)
func no_reservations(world: Node) -> void:
	check(world.logistics.jobs.is_empty(),"No unfinished haul remains")
	for building in world.buildings:
		for resource in Resources.values():
			check(building.resources.get_reserved_in(resource)==0 and building.resources.get_reserved_out(resource)==0,"No leaked concrete reservation")

func definitions_and_quotas() -> void:
	check(Resources.FOOD==0 and Resources.LOG==1 and Resources.PLANK==2 and Resources.STONE==3 and Resources.MUSHROOM==4 and Resources.FRIED_MUSHROOM==5,"New goods append stable IDs")
	check(Profession.MINER==6 and Profession.COOK==7 and preload("res://scripts/resident_profession.gd").display_name(Profession.COOK)=="Повар","Profession IDs and Cook label")
	check(not Catalog.is_ready_food(Resources.MUSHROOM) and Catalog.supports_quantity(Resources.MUSHROOM) and Catalog.get_category(Resources.MUSHROOM)==Categories.MUSHROOM,"Raw mushroom is a quantity ingredient in its own category")
	check(Catalog.is_ready_food(Resources.FRIED_MUSHROOM) and Catalog.is_ready_food(Resources.FOOD) and Catalog.get_food_quality(Resources.FRIED_MUSHROOM)==Catalog.FoodQuality.SIMPLE,"Both concrete ready foods have SIMPLE quality")
	check(Catalog.types_in_category(Categories.SIMPLE_FOOD)==[Resources.FOOD,Resources.FRIED_MUSHROOM] and Catalog.types_in_category(Categories.MUSHROOM)==[Resources.MUSHROOM],"Real multi-type ready-food category")
	for resource in [Resources.MUSHROOM,Resources.FRIED_MUSHROOM]: check(not Catalog.get_display_name(resource).is_empty(),"Catalog owns each new label")
	var kitchen=Instance.new(&"kitchen_test",Definitions.for_type(Types.FOOD))
	var hut=Instance.new(&"hut_test",Definitions.for_type(Types.GATHERER_HUT))
	check(hut.resources.get_capacity(Resources.MUSHROOM)==5 and not hut.resources.allows_resource(Resources.FOOD),"Unchanged five-unit extraction buffer, now mushrooms only")
	check(kitchen.definition.worker_profession==Profession.COOK and kitchen.production_capacity()==1 and kitchen.definition.visitor_capacity==4,"One cook plus four independent visitors")
	check(not kitchen.resources.is_warehouse() and kitchen.resources.get_capacity(Resources.MUSHROOM)==8 and kitchen.resources.get_capacity(Resources.FRIED_MUSHROOM)==20 and kitchen.resources.get_capacity(Resources.FOOD)==20,"Concrete production buffers remain separate from category quotas")
	var recipe=kitchen.definition.production_recipe
	check(recipe.id==&"fried_mushroom" and recipe.inputs=={Resources.MUSHROOM:1} and recipe.outputs=={Resources.FRIED_MUSHROOM:1} and recipe.work_required==30 and kitchen.get_recipe_mode(recipe.id)==Instance.ProductionMode.UNLIMITED,"Real ordinary recipe and default UNLIMITED")
	check(kitchen.definition.allows_external_import(Resources.MUSHROOM) and not kitchen.definition.allows_external_export(Resources.MUSHROOM) and not kitchen.definition.allows_external_import(Resources.FRIED_MUSHROOM) and kitchen.definition.allows_external_export(Resources.FRIED_MUSHROOM),"Raw enters, dish exports without a ready-dish return cycle")
	check(hut.definition.allows_external_export(Resources.MUSHROOM) and not hut.definition.allows_external_import(Resources.MUSHROOM),"Hut only exports mushrooms")
	var layout=Layouts.create(kitchen.definition)
	check(Layouts.validate(layout,kitchen.definition),"Real authored kitchen layout validates")
	var markers=Layouts.markers(layout,Slots)
	check(markers.filter(func(marker): return marker.purpose==Slots.Purpose.WORKER).size()==1 and markers.filter(func(marker): return marker.purpose==Slots.Purpose.VISITOR).size()==4,"One actual WORKER and four actual VISITOR markers")
	for a in markers:
		if a.purpose not in [Slots.Purpose.WORKER,Slots.Purpose.VISITOR,Slots.Purpose.COURIER]: continue
		for b in markers:
			if a!=b and b.purpose in [Slots.Purpose.WORKER,Slots.Purpose.VISITOR,Slots.Purpose.COURIER]: check(a.position.distance_to(b.position)>=0.8,"Occupied physical markers do not overlap resident diameters")
	layout.free()
	for type in [Types.STORAGE,Types.TOWN_CENTER]:
		var box=Instance.new(&"warehouse",Definitions.for_type(type)).resources
		var preset=Balance.STORAGE_CATEGORY_QUOTAS if type==Types.STORAGE else Balance.TOWN_CENTER_CATEGORY_QUOTAS
		check(box.configure_warehouse(100,preset) and box.get_category_quota(Categories.MUSHROOM)==0 and not box.reserve_in(Resources.MUSHROOM,1),"Default zero mushroom quota forbids warehouse import")
		check(box.get_category_quota(Categories.LOG)==(40 if type==Types.STORAGE else 10) and box.get_category_quota(Categories.STONE)==(20 if type==Types.STORAGE else 10),"Old log/stone quotas unchanged")
		check(box.get_category_quota(Categories.PLANK)==(25 if type==Types.STORAGE else 60) and box.get_category_quota(Categories.SIMPLE_FOOD)==(15 if type==Types.STORAGE else 20),"Old plank/ready-food quotas unchanged")
	var shared=preload("res://scripts/resource_container.gd").new(&"real_dishes")
	check(shared.configure_warehouse(100,Balance.STORAGE_CATEGORY_QUOTAS) and shared.add(Resources.FOOD,7) and shared.add(Resources.FRIED_MUSHROOM,5),"Real dishes share one fifteen-unit category quota")
	check(shared.get_category_amount(Categories.SIMPLE_FOOD)==12 and shared.reserve_in(Resources.FRIED_MUSHROOM,2) and shared.get_available_free_capacity(Resources.FOOD)==1 and shared.get_available_free_capacity(Resources.FRIED_MUSHROOM)==1,"Physical food plus inbound uses aggregate category room once")
	check(shared.reserve_out(Resources.FOOD,1) and shared.reserve_out(Resources.FRIED_MUSHROOM,1) and shared.take_reserved(Resources.FRIED_MUSHROOM,1) and shared.get_reserved_out(Resources.FOOD)==1 and shared.get_amount(Resources.FOOD)==7,"Concrete dish reserves never consume or release each other")
	check(kitchen.resources.add(Resources.MUSHROOM,1),"Production buffer accepts mushrooms independently of warehouse zero quota")
	check(kitchen.resources.add(Resources.FRIED_MUSHROOM,20) and not kitchen.can_start_production(recipe.id) and kitchen.resources.get_amount(Resources.MUSHROOM)==1,"Full cooked buffer blocks new batch without losing raw input")
	kitchen.resources.try_take(Resources.FRIED_MUSHROOM,1)
	var batch=kitchen.prepare_production_batch("cook")
	check(batch!=null and kitchen.resources.get_amount(Resources.MUSHROOM)==1 and batch.begin("cook") and kitchen.resources.get_amount(Resources.MUSHROOM)==0,"Normal batch preparation then actual beginning spends exactly one mushroom")
	batch.advance("cook",30)
	check(batch.finish("cook") and not batch.finish("cook") and kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==20,"Repeated finish never produces a second dish")
	kitchen.retire_production_batch(batch)

func real_chain() -> void:
	var world=quiet_world()
	var hut=world.gatherer_hut_data
	var kitchen=world.kitchen_data
	var gatherer=world.resident_runtimes[2]
	var cook=world.resident_runtimes[1]
	var visitor=world.resident_runtimes[0]
	var replacement=world.resident_runtimes[3]
	check(world._request_work(gatherer),"Gatherer starts original physical extraction cycle")
	arrive(gatherer)
	check(gatherer.data.activity==preload("res://scripts/resident_activity.gd").Type.WORKING and world.building_uses.occupied_by(hut.id,gatherer.data.id,Slots.Purpose.WORKER),"Real hut WORKER contributes actual work")
	world.game_time.debug_skip_minutes(30)
	check(hut.resources.get_amount(Resources.MUSHROOM)==1 and hut.resources.get_amount(Resources.FOOD)==0,"Thirty work minutes produce one raw mushroom, never FOOD")
	check(world.food_availability.total()==0,"Raw extraction does not increase ready-food availability")
	await observe(world,"gathered_mushroom")
	gatherer.commands.move_to(Vector2(0,500))
	check(world.player_control.assign_workplace(cook.data.id,kitchen.id) and cook.data.profession==Profession.COOK,"Existing workplace API assigns COOK")
	check(not world.player_control.assign_workplace(replacement.data.id,kitchen.id,Profession.COOK) and not world.player_control.can_assign_workplace(cook.data.id,hut.id,Profession.COOK),"Capacity and correct profession prevent invalid assignments")
	check(world.warehouse_data.resources.get_capacity(Resources.MUSHROOM)==0,"Chain requires no mushroom warehouse quota")
	var preview=cook.self_logistics.task()
	check(preview.kind==&"SUPPLY" and preview.resource==Resources.MUSHROOM and preview.source.id==hut.id,"Cook selects missing real ingredient directly from hut")
	check(world._request_work(cook),"Existing HaulExecutor accepts supply")
	var job=world.logistics.get_job(cook.data.id)
	check(job.amount==1 and kitchen.resources.get_reserved_in(Resources.MUSHROOM)==1 and hut.resources.get_reserved_out(Resources.MUSHROOM)==1 and kitchen.production_batches.is_empty(),"One actual incoming unit, no early production")
	check(cook.self_logistics.task().is_empty() and kitchen.supply.needs.size()==1,"Busy cook cannot order duplicate supply")
	arrive(cook)
	check(world.building_uses.occupied_by(hut.id,cook.data.id,Slots.Purpose.COURIER),"Cook reaches actual source COURIER")
	world.game_time.debug_skip_minutes(Balance.RESOURCE_LOADING_MINUTES)
	check(cook.data.inventory.resource_type==Resources.MUSHROOM and cook.data.inventory.amount==1 and hut.resources.get_amount(Resources.MUSHROOM)==0,"One mushroom moves physically from hut to inventory")
	await observe(world,"carrying_mushroom")
	arrive(cook)
	world.game_time.debug_skip_minutes(Balance.RESOURCE_UNLOADING_MINUTES)
	check(job.state==Job.State.COMPLETED and kitchen.resources.get_amount(Resources.MUSHROOM)==1 and cook.data.inventory.amount==0,"Real unloading adds the same mushroom to kitchen")
	check(world._request_work(cook) and kitchen.resources.get_amount(Resources.MUSHROOM)==1,"START reserves before movement, without spending")
	arrive(cook)
	var batch=cook.recipe_work.batch
	check(batch!=null and batch.recipe_id==&"fried_mushroom" and kitchen.resources.get_amount(Resources.MUSHROOM)==0 and kitchen.resources.get_reserved_in(Resources.FRIED_MUSHROOM)==1,"Authored WORKER arrival spends raw, reserves real output")
	await observe(world,"cooking")
	world.game_time.debug_skip_minutes(10)
	cook.commands.move_to(Vector2(0,500))
	check(batch.state==Batch.State.PAUSED and batch.progress==10 and kitchen.resources.get_reserved_in(Resources.FRIED_MUSHROOM)==1,"Interruption preserves paid WIP and output promise")
	check(world.player_control.assign_profession(cook.data.id,Profession.NONE) and world.player_control.assign_workplace(replacement.data.id,kitchen.id,Profession.COOK),"Another cook can take the vacant assignment")
	check(world._request_work(replacement),"Replacement chooses paid RESUME")
	arrive(replacement)
	check(replacement.recipe_work.batch==batch and batch.progress==10 and kitchen.resources.get_amount(Resources.MUSHROOM)==0,"Resume uses the same paid batch, no second ingredient")
	# Legacy ready FOOD remains edible while production uses another physical role.
	kitchen.resources.add(Resources.FOOD,1)
	visitor.data.hunger=80
	check(visitor.needs.try_eat(10000),"Visitor can eat while Cook owns WORKER")
	arrive(visitor)
	check(world.building_uses.occupied_by(kitchen.id,visitor.data.id,Slots.Purpose.VISITOR) and world.building_uses.occupied_by(kitchen.id,replacement.data.id,Slots.Purpose.WORKER) and visitor.view._marker!=replacement.view._marker,"VISITOR and WORKER coexist at distinct real markers")
	await observe(world,"cook_and_visitor")
	world.game_time.debug_skip_minutes(20)
	check(batch.state==Batch.State.COMPLETED and kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==1 and not batch.finish(replacement.data.id),"Kitchen releases exactly one real dish after 30 working minutes")
	world.game_time.debug_skip_minutes(10)
	check(visitor.data.hunger==20 and kitchen.resources.get_amount(Resources.FOOD)==0,"Old FOOD restores hunger unchanged")
	check(world.food_availability.total()==1,"Real cooked dish enters shared ready-food total")
	visitor.data.hunger=80
	check(visitor.needs.try_eat(10000) and visitor.needs._meal_selection.concrete_type==Resources.FRIED_MUSHROOM,"Normal F4 selection chooses actual FRIED_MUSHROOM")
	arrive(visitor)
	check(kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==0 and kitchen.resources.get_reserved_out(Resources.FRIED_MUSHROOM)==0,"Pickup consumes exactly the promised concrete dish")
	await observe(world,"eating_fried_mushroom")
	world.game_time.debug_skip_minutes(30)
	check(visitor.data.hunger==20 and kitchen.production_batches.is_empty() and kitchen.supply.needs.is_empty(),"New dish restores hunger just like FOOD; all production obligations finished")
	no_reservations(world)
	check(hut.resources.get_amount(Resources.MUSHROOM)==0 and kitchen.resources.get_amount(Resources.MUSHROOM)==0 and kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==0,"One mined ingredient became one consumed dish, no duplicate stock")
	await observe(world,"completed")
	world.free()

func supply_and_food_edges() -> void:
	var world=quiet_world()
	var kitchen=world.kitchen_data; var hut=world.gatherer_hut_data
	var cook=world.resident_runtimes[1]
	hut.resources.add(Resources.MUSHROOM,2)
	check(world.player_control.assign_workplace(cook.data.id,kitchen.id),"Assign cook for cancellation regression")
	var previous=world.logistics.sources
	var probe=preload("res://tests/test_recipe_supply.gd").ProbeSources.new()
	probe.buildings=previous.buildings; probe.locations=previous.locations
	probe.work_object_current=previous.work_object_current
	probe.route_available=probe.track_route.bind(previous.route_available)
	previous.changed.disconnect(world.logistics._on_state_changed)
	previous.ground.availability_changed.disconnect(previous._queue_changed)
	probe.bind_ground(previous.ground)
	probe.changed.connect(world.logistics._on_state_changed)
	world.logistics.sources=probe
	for index in range(100): check(cook.self_logistics.has_work(),"Supply preview remains available")
	check(probe.searches==1 and probe.routes==2 and world.logistics.jobs.is_empty() and kitchen.supply.needs.is_empty(),"One positive source search, no jobs/needs from repeated same-frame reads")
	check(world._request_work(cook) and probe.searches==1 and probe.routes==6,"Claim reuses proposal, preserving original Logistics route validations")
	cook.commands.move_to(Vector2(0,500))
	check(hut.resources.get_reserved_out(Resources.MUSHROOM)==0 and kitchen.resources.get_reserved_in(Resources.MUSHROOM)==0 and kitchen.supply.needs.is_empty(),"Cancel before pickup releases own real reservations")
	idle(cook)
	check(world._request_work(cook),"New ordinary decision can supply after cancellation")
	arrive(cook); world.game_time.debug_skip_minutes(10)
	world.logistics.cargo_drop_handler=func(_r,_a,_id): return DropResult.Status.FAILED
	kitchen.set_recipe_mode(&"fried_mushroom",Instance.ProductionMode.OFF)
	check(cook.data.inventory.resource_type==Resources.MUSHROOM and cook.data.inventory.amount==1 and hut.resources.get_amount(Resources.MUSHROOM)==1 and kitchen.supply.needs.is_empty(),"OFF/FAILED preserves carried mushroom without return or destruction")
	no_reservations(world)
	var visitor=world.resident_runtimes[0]
	visitor.data.hunger=80
	kitchen.resources.add(Resources.MUSHROOM,1)
	Stacks.create(world.ground_resources,Resources.MUSHROOM,1,visitor.view.get_sim_position())
	check(world.food_availability.total()==0 and not visitor.needs.try_eat(10000),"Raw mushrooms in hut, kitchen, cargo and ground cannot become a meal")
	kitchen.resources.add(Resources.FOOD,1); kitchen.resources.add(Resources.FRIED_MUSHROOM,1)
	check(visitor.needs.try_eat(10000) and visitor.needs._meal_selection.concrete_type==Resources.FOOD,"Existing lowest-ID tie-break still prefers FOOD when both exist")
	visitor.commands.move_to(Vector2(0,500))
	world.free()
	# A fresh clock/need accumulator isolates one ground meal from the prior loaded-cancel test.
	world=quiet_world()
	visitor=world.resident_runtimes[0]
	visitor.data.hunger=80
	Stacks.create(world.ground_resources,Resources.MUSHROOM,1,visitor.view.get_sim_position())
	var ready=Stacks.create(world.ground_resources,Resources.FRIED_MUSHROOM,2,visitor.view.get_sim_position()+Vector2(12.5,0))
	check(ready.capacity==10 and visitor.needs.try_eat(10000) and visitor.needs._meal_selection.concrete_type==Resources.FRIED_MUSHROOM,"Ready ground stack remains edible; raw neighboring stack does not qualify")
	arrive(visitor)
	check(ready.amount==1 and ready.reserved_total()==0 and visitor.needs._meal_active and visitor.needs._minutes_left==preload("res://scripts/resident_needs_controller.gd").OUTSIDE_MEAL_MINUTES,"Ground meal takes one concrete portion from a multi-unit stack")
	world.game_time.debug_skip_minutes(visitor.needs._minutes_left)
	check(visitor.data.hunger==20,"Ground fried mushroom uses the same outside-meal duration and satiety as FOOD")
	world.free()

func warehouse_card() -> void:
	var world=quiet_world()
	var store=Instance.new(&"mushroom_store",Definitions.for_type(Types.STORAGE),Coordinates.to_sim(Vector3(20,0,14)))
	world.buildings.append(store); world._show_building(store)
	world.resident_selection.select_building(store)
	var card=world.building_card_view()
	check(store.resources.is_warehouse() and card.storage_rows.has(Categories.MUSHROOM) and card.storage_rows[Categories.MUSHROOM].editor.text=="0","Existing warehouse card includes new zero category")
	card._submit_quota("20",Categories.PLANK)
	card._submit_quota("5",Categories.MUSHROOM)
	check(store.resources.get_category_quota(Categories.MUSHROOM)==5 and card.storage_rows[Categories.MUSHROOM].editor.text=="5" and card.get_node("%StorageError").text.is_empty(),"New category uses existing quota control and PlayerControl validation")
	check(store.resources.add(Resources.FOOD,7) and store.resources.add(Resources.FRIED_MUSHROOM,5),"Warehouse holds both real dishes")
	card.storage_rows[Categories.SIMPLE_FOOD].expand.button_pressed=true
	check(card.storage_rows[Categories.SIMPLE_FOOD].contents.text.contains("FOOD: 7") and card.storage_rows[Categories.SIMPLE_FOOD].contents.text.contains("Жареные грибы: 5"),"Expanded ready-food category displays concrete composition")
	world.resident_selection.select_building(world.kitchen_data)
	check(card.resources_label.text.contains("Грибы") and card.resources_label.text.contains("Жареные грибы") and card.staffing_buttons.has(Profession.COOK),"Kitchen card has raw/cooked buffers and normal Cook assignment")
	check(world.kitchen_data.resources.add(Resources.FRIED_MUSHROOM,1),"One ready dish available for ordinary export")
	var cook=world.resident_runtimes[1]
	check(world.player_control.assign_workplace(cook.data.id,world.kitchen_data.id) and world._request_work(cook),"Cook uses ordinary self-export when no recipe can start or supply")
	var exported=world.logistics.get_job(cook.data.id)
	check(exported!=null and exported.resource_type==Resources.FRIED_MUSHROOM and exported.source_location_id==world.kitchen_data.id and exported.destination_location_id==store.id,"Export keeps concrete dish and suitable warehouse receiver")
	walk(cook,&"haul_source"); walk(cook)
	check(exported.state==Job.State.COMPLETED and store.resources.get_amount(Resources.FRIED_MUSHROOM)==6 and world.kitchen_data.resources.get_amount(Resources.FRIED_MUSHROOM)==0 and cook.data.inventory.amount==0,"Real physical ready-dish export completes once")
	check(not world.logistics.allows_external_delivery(store,world.kitchen_data,Resources.FRIED_MUSHROOM),"Ready dishes cannot cycle back into the same production kitchen")
	world.resident_selection.select_building(world.gatherer_hut_data)
	check(card.resources_label.text.contains("Грибы") and not card.resources_label.text.contains("FOOD"),"Hut information shows its actual raw output")
	world.free()

func cook_shift() -> void:
	var world=quiet_world()
	world.game_time.total_minutes=1015
	var kitchen=world.kitchen_data; var cook=world.resident_runtimes[1]
	kitchen.resources.add(Resources.MUSHROOM,2)
	check(world.player_control.assign_workplace(cook.data.id,kitchen.id) and world._request_work(cook),"Cook accepts ordinary production before shift ends")
	arrive(cook)
	var batch=cook.recipe_work.batch
	world.game_time.debug_skip_minutes(30)
	check(batch.state==Batch.State.COMPLETED and kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==1 and kitchen.resources.get_amount(Resources.MUSHROOM)==1,"Accepted Cook batch finishes across the shift boundary")
	check(world.game_time.get_phase()!="День" and not world._request_work(cook) and kitchen.production_batches.is_empty(),"Cook cannot start new work outside the day phase")
	world.free()

func run() -> void:
	definitions_and_quotas()
	await real_chain()
	supply_and_food_edges()
	warehouse_card()
	cook_shift()
	print("Mushroom cooking: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
