extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Logistics = preload("res://scripts/logistics_controller.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
const Building = preload("res://scripts/building_data.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Job = preload("res://scripts/haul_job.gd")
const MUSHROOM = preload("res://scripts/resource_type.gd").Type.MUSHROOM # Commodity under test is now the gathered ingredient.
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func building(id: StringName, type: int, capacity: int):
	var data = Building.new(id, String(id), type)
	data.resources.set_capacity(MUSHROOM, capacity)
	return data
func make_scene():
	var scene = preload("res://tests/domain_world.gd").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.need_dynamics.free() # Handling time must not introduce unrelated hunger interrupts.
		runtime.wander.target_provider = Callable()
		for need in runtime.data.needs.values():
			need.value = 0
			need.base_weight = 0
	for job in scene.logistics.jobs.duplicate(): scene.logistics.cancel_job(job)
	scene.warehouse_data.resources.try_take(preload("res://scripts/resource_type.gd").Type.FOOD, 10)
	scene.warehouse_data.resources.set_capacity(MUSHROOM,20) # Explicit raw storage for this two-leg logistics fixture.
	return scene
func _run():
	var kitchen = building(&"communal_kitchen_01", BT.FOOD, 5)
	var hut = building(&"gatherer_hut_01", BT.GATHERER_HUT, 5)
	var warehouse = building(&"warehouse_01", BT.STORAGE, 20)
	kitchen.resources.add(MUSHROOM, 1)
	check(is_equal_approx(Priority.import_priority(kitchen.resources, MUSHROOM), 8800), "Kitchen 1/5 import = 8800")
	kitchen.resources.add(MUSHROOM, 3)
	check(is_equal_approx(Priority.import_priority(kitchen.resources, MUSHROOM), 2200), "Kitchen 4/5 import = 2200, falling with fill")
	hut.resources.add(MUSHROOM, 1)
	check(is_equal_approx(Priority.export_priority(hut.resources, MUSHROOM), 2000), "Hut 1/5 export = 2000")
	hut.resources.add(MUSHROOM, 3)
	check(is_equal_approx(Priority.export_priority(hut.resources, MUSHROOM), 8000), "Hut 4/5 export = 8000, rising with fill")
	hut.resources.reserve_out(MUSHROOM, 2)
	check(is_equal_approx(Priority.export_priority(hut.resources, MUSHROOM), 4000), "Export uses amount minus reserved_out")
	hut.resources.release_out(MUSHROOM, 2)
	kitchen.resources.reserve_in(MUSHROOM, 1)
	check(is_zero_approx(Priority.import_priority(kitchen.resources, MUSHROOM)), "Import uses amount plus reserved_in")
	kitchen.resources.release_in(MUSHROOM, 1)
	hut.resources.add(MUSHROOM, 1)
	check(Priority.export_priority(hut.resources, MUSHROOM) > Priority.import_priority(kitchen.resources, MUSHROOM), "Full hut outranks well-stocked kitchen")
	kitchen.resources.try_take(MUSHROOM, 4)
	check(Priority.import_priority(kitchen.resources, MUSHROOM) > Priority.export_priority(hut.resources, MUSHROOM), "Empty kitchen can outrank full hut")
	# Both job promises affect the live priorities used during claim.
	warehouse.resources.add(MUSHROOM, 10)
	var porter = Data.new("porter", "Porter", 30, Profession.PORTER)
	porter.work_location_id = warehouse.id
	var logistics = Logistics.new()
	logistics.setup(warehouse, kitchen, porter)
	logistics.add_production_source(hut)
	logistics.position_provider = func(_id): return Vector2.ZERO
	logistics.recalculate()
	check(logistics.jobs.is_empty() and logistics.collect_candidates(porter.id).size() == 2 and warehouse.resources.get_reserved_out(MUSHROOM) == 0 and warehouse.resources.get_reserved_in(MUSHROOM) == 0, "Two routes independently reserve warehouse out and in")
	var imported = logistics.claim_best_job(porter.id)
	check(imported.source_location_id == warehouse.id and is_equal_approx(imported.priority, 11000), "Porter claims more urgent empty-kitchen import")
	logistics.cancel_job(imported)
	kitchen.resources.add(MUSHROOM, 4)
	logistics.recalculate()
	var exported = logistics.claim_best_job(porter.id)
	check(exported.source_location_id == hut.id and exported.destination_location_id == warehouse.id and is_equal_approx(exported.priority, 10000), "Full hut wins over filled kitchen after live recalculation")
	logistics.cancel_job(exported)
	check(hut.resources.get_reserved_out(MUSHROOM) == 0 and warehouse.resources.get_reserved_in(MUSHROOM) == 0 and warehouse.resources.get_reserved_out(MUSHROOM) == 0 and kitchen.resources.get_reserved_in(MUSHROOM) == 0, "Export cancellation releases its route's promises without touching import")
	for job in logistics.jobs.duplicate(): logistics.cancel_job(job)
	hut.resources.try_take(MUSHROOM, 4)
	kitchen.resources.add(MUSHROOM, 1)
	logistics.recalculate()
	check(logistics.jobs.is_empty() and logistics.collect_candidates(porter.id).size() == 1 and logistics.collect_candidates(porter.id)[0].source == hut, "Hut 1/5 already creates export; full kitchen creates no import")
	# Full real chain with existing movement, factory data, and DecisionController.
	var scene = make_scene()
	var gatherer = scene.resident_runtimes[2]
	var carrier = scene.resident_runtimes[0]
	check(gatherer.data.profession == Profession.GATHERER and gatherer.data.work_location_id == scene.gatherer_hut_data.id, "Fedor assigned to gatherer hut")
	scene.resident_selection.select(gatherer.data)
	scene.resident_card_view()._refresh()
	check(scene.resident_card_view().profession_label.text == "Профессия: Собиратель", "Fedor's card reads gatherer profession")
	scene.game_time.debug_next_phase()
	check(gatherer.data.activity == Activity.MOVING and scene.gatherer_hut_data.production_progress == 0, "Walking to work is not production")
	preload("res://tests/handling_test_step.gd").move_domain(gatherer,20)
	check(gatherer.data.activity == Activity.WORKING, "Physical arrival starts actual WORKING")
	carrier.decision._next_decision_at = scene.game_time.total_minutes + 60
	scene.game_time.debug_skip_minutes(30)
	check(scene.gatherer_hut_data.resources.get_amount(MUSHROOM) == 1 and scene.warehouse_data.resources.get_amount(MUSHROOM) == 0 and scene.kitchen_data.resources.get_amount(MUSHROOM) == 0, "Produced MUSHROOM exists only in hut, never globally")
	check(scene.logistics.jobs.is_empty() and scene.gatherer_hut_data.resources.get_reserved_out(MUSHROOM) == 0, "Production offers export without forcing porter movement")
	gatherer.intents.abort_current(gatherer.intents.current_intent) # Isolate the produced unit during forty handling minutes.
	gatherer.decision._deciding = true # Keep the isolated produced unit unchanged.
	carrier.decision.request_decision("test_work_point")
	var export_job = scene.logistics.current_job
	check(export_job.source_location_id == scene.gatherer_hut_data.id and carrier.view.target_position == scene.world_locations.get_position(scene.gatherer_hut_data.id), "Porter claims hut-to-warehouse and walks to real source")
	preload("res://tests/handling_test_step.gd").move_domain(carrier,20)
	check(scene.gatherer_hut_data.resources.get_amount(MUSHROOM) == 0 and carrier.data.inventory.amount == 1 and carrier.view.target_position == scene.world_locations.get_position(scene.warehouse_data.id), "MUSHROOM moves from hut to inventory toward warehouse")
	var warehouse_received = [false]
	scene.warehouse_data.resources.changed.connect(func(_resource, amount):
		if amount == 1: warehouse_received[0] = true)
	var decisions: int = carrier.decision.decision_count
	preload("res://tests/handling_test_step.gd").move_domain(carrier,20)
	check(export_job.state == Job.State.COMPLETED and warehouse_received[0], "Warehouse physically receives produced MUSHROOM")
	check(carrier.decision.decision_count > decisions and scene.logistics.current_job.source_location_id == scene.warehouse_data.id, "After export a fresh decision chooses kitchen import")
	# At warehouse already: next pickup may complete synchronously, without teleporting cargo.
	if scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE: preload("res://tests/handling_test_step.gd").move_domain(carrier,20)
	preload("res://tests/handling_test_step.gd").move_domain(carrier,20)
	check(scene.kitchen_data.resources.get_amount(MUSHROOM) == 1 and scene.warehouse_data.resources.get_amount(MUSHROOM) == 0 and scene.gatherer_hut_data.resources.get_amount(MUSHROOM) == 0 and carrier.data.inventory.amount == 0, "Full chain conserves the one produced unit through hut, inventory, warehouse and kitchen")
	print("Production chain proof: Fedor WORKING -> hut MUSHROOM 1 -> Stepan -> warehouse received MUSHROOM 1 -> Stepan -> kitchen MUSHROOM 1")
	scene.free()
	# Forced interruption of either export stage uses its own source/destination containers.
	for picked_up in [false, true]:
		scene = make_scene()
		carrier = scene.resident_runtimes[0]
		scene.gatherer_hut_data.resources.add(MUSHROOM, 1)
		scene.game_time.debug_next_phase()
		export_job = scene.logistics.current_job
		if picked_up: preload("res://tests/handling_test_step.gd").move_domain(carrier,20)
		carrier.data.hunger = 100
		check(export_job.state == Job.State.CANCELLED and scene.gatherer_hut_data.resources.get_reserved_out(MUSHROOM) == 0 and scene.warehouse_data.resources.get_reserved_in(MUSHROOM) == 0 and carrier.data.inventory.amount == 0, "Forced export cancellation clears exactly hut/warehouse reservations and inventory")
		check(Stacks.total(scene.ground_resources) == (1 if picked_up else 0) and scene.gatherer_hut_data.resources.get_amount(MUSHROOM) == (0 if picked_up else 1), "Loaded export creates ground MUSHROOM; unloaded MUSHROOM stays in hut")
		scene.free()
	print("Production logistics checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
