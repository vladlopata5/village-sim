extends SceneTree
const Logistics = preload("res://scripts/logistics_controller.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
const Building = preload("res://scripts/building_data.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Job = preload("res://scripts/haul_job.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func building(id: StringName, type: int, capacity: int):
	var data = Building.new(id, String(id), type)
	data.resources.set_capacity(FOOD, capacity)
	return data
func make_scene():
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.wander.target_provider = Callable()
		for need in runtime.data.needs.values():
			need.value = 0
			need.base_weight = 0
	for job in scene.logistics.jobs.duplicate(): scene.logistics.cancel_job(job)
	scene.warehouse_data.resources.try_take(FOOD, 10)
	return scene
func _run():
	var kitchen = building(&"communal_kitchen_01", BT.FOOD, 5)
	var hut = building(&"gatherer_hut_01", BT.GATHERER_HUT, 5)
	var warehouse = building(&"warehouse_01", BT.STORAGE, 20)
	kitchen.resources.add(FOOD, 1)
	check(is_equal_approx(Priority.import_priority(kitchen.resources, FOOD), 8800), "Kitchen 1/5 import = 8800")
	kitchen.resources.add(FOOD, 3)
	check(is_equal_approx(Priority.import_priority(kitchen.resources, FOOD), 2200), "Kitchen 4/5 import = 2200, falling with fill")
	hut.resources.add(FOOD, 1)
	check(is_equal_approx(Priority.export_priority(hut.resources, FOOD), 2000), "Hut 1/5 export = 2000")
	hut.resources.add(FOOD, 3)
	check(is_equal_approx(Priority.export_priority(hut.resources, FOOD), 8000), "Hut 4/5 export = 8000, rising with fill")
	hut.resources.reserve_out(FOOD, 2)
	check(is_equal_approx(Priority.export_priority(hut.resources, FOOD), 4000), "Export uses amount minus reserved_out")
	hut.resources.release_out(FOOD, 2)
	kitchen.resources.reserve_in(FOOD, 1)
	check(is_zero_approx(Priority.import_priority(kitchen.resources, FOOD)), "Import uses amount plus reserved_in")
	kitchen.resources.release_in(FOOD, 1)
	hut.resources.add(FOOD, 1)
	check(Priority.export_priority(hut.resources, FOOD) > Priority.import_priority(kitchen.resources, FOOD), "Full hut outranks well-stocked kitchen")
	kitchen.resources.try_take(FOOD, 4)
	check(Priority.import_priority(kitchen.resources, FOOD) > Priority.export_priority(hut.resources, FOOD), "Empty kitchen can outrank full hut")
	# Both job promises affect the live priorities used during claim.
	warehouse.resources.add(FOOD, 10)
	var porter = Data.new("porter", "Porter", 30, Profession.PORTER)
	porter.work_location_id = warehouse.id
	var logistics = Logistics.new()
	logistics.setup(warehouse, kitchen, porter)
	logistics.add_production_source(hut)
	logistics.recalculate()
	check(logistics.jobs.size() == 2 and warehouse.resources.get_reserved_out(FOOD) == 1 and warehouse.resources.get_reserved_in(FOOD) == 1, "Two routes independently reserve warehouse out and in")
	var imported = logistics.claim_best_job(porter.id)
	check(imported.source_location_id == warehouse.id and is_equal_approx(imported.priority, 8800), "Porter claims more urgent empty-kitchen import")
	logistics.cancel_job(imported)
	kitchen.resources.add(FOOD, 4)
	logistics.recalculate()
	var exported = logistics.claim_best_job(porter.id)
	check(exported.source_location_id == hut.id and exported.destination_location_id == warehouse.id and is_equal_approx(exported.priority, 8000), "Full hut wins over filled kitchen after live recalculation")
	logistics.cancel_job(exported)
	check(hut.resources.get_reserved_out(FOOD) == 0 and warehouse.resources.get_reserved_in(FOOD) == 0 and warehouse.resources.get_reserved_out(FOOD) == 1 and kitchen.resources.get_reserved_in(FOOD) == 1, "Export cancellation releases its route's promises without touching import")
	for job in logistics.jobs.duplicate(): logistics.cancel_job(job)
	hut.resources.try_take(FOOD, 4)
	kitchen.resources.add(FOOD, 1)
	logistics.recalculate()
	check(logistics.jobs.size() == 1 and logistics.current_job.source_location_id == hut.id, "Hut 1/5 already creates export; full kitchen creates no import")
	# Full real chain with existing movement, factory data, and DecisionController.
	var scene = make_scene()
	var gatherer = scene.resident_runtimes[2]
	var carrier = scene.resident_runtimes[0]
	check(gatherer.data.profession == Profession.GATHERER and gatherer.data.work_location_id == scene.gatherer_hut_data.id, "Fedor assigned to gatherer hut")
	scene.resident_selection.select(gatherer.data)
	scene.get_node("HUD/ResidentCard")._refresh()
	check(scene.get_node("HUD/ResidentCard").profession_label.text == "Профессия: Собиратель", "Fedor's card reads gatherer profession")
	scene.game_time.debug_next_phase()
	check(gatherer.data.activity == Activity.MOVING and scene.gatherer_hut_data.production_progress == 0, "Walking to work is not production")
	gatherer.view._process(20)
	check(gatherer.data.activity == Activity.WORKING, "Physical arrival starts actual WORKING")
	carrier.decision._next_decision_at = scene.game_time.total_minutes + 60
	scene.game_time.debug_skip_minutes(30)
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 1 and scene.warehouse_data.resources.get_amount(FOOD) == 0 and scene.kitchen_data.resources.get_amount(FOOD) == 0, "Produced FOOD exists only in hut, never globally")
	check(scene.logistics.current_job.state == Job.State.RESERVED and scene.logistics.current_job.source_location_id == scene.gatherer_hut_data.id, "Production offers export without forcing porter movement")
	carrier.decision.request_decision("test_work_point")
	var export_job = scene.logistics.current_job
	check(export_job.source_location_id == scene.gatherer_hut_data.id and carrier.view.target_position == scene.world_locations.get_position(scene.gatherer_hut_data.id), "Porter claims hut-to-warehouse and walks to real source")
	carrier.view._process(20)
	check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 0 and carrier.data.inventory.amount == 1 and carrier.view.target_position == scene.world_locations.get_position(scene.warehouse_data.id), "FOOD moves from hut to inventory toward warehouse")
	var warehouse_received = [false]
	scene.warehouse_data.resources.changed.connect(func(_resource, amount):
		if amount == 1: warehouse_received[0] = true)
	var decisions: int = carrier.decision.decision_count
	carrier.view._process(20)
	check(export_job.state == Job.State.COMPLETED and warehouse_received[0], "Warehouse physically receives produced FOOD")
	check(carrier.decision.decision_count > decisions and scene.logistics.current_job.source_location_id == scene.warehouse_data.id, "After export a fresh decision chooses kitchen import")
	# At warehouse already: next pickup may complete synchronously, without teleporting cargo.
	if scene.logistics.current_job.state == Job.State.GOING_TO_SOURCE: carrier.view._process(20)
	carrier.view._process(20)
	check(scene.kitchen_data.resources.get_amount(FOOD) == 1 and scene.warehouse_data.resources.get_amount(FOOD) == 0 and scene.gatherer_hut_data.resources.get_amount(FOOD) == 0 and carrier.data.inventory.amount == 0, "Full chain conserves the one produced unit through hut, inventory, warehouse and kitchen")
	print("Production chain proof: Fedor WORKING -> hut FOOD 1 -> Stepan -> warehouse received FOOD 1 -> Stepan -> kitchen FOOD 1")
	scene.free()
	# Forced interruption of either export stage uses its own source/destination containers.
	for picked_up in [false, true]:
		scene = make_scene()
		carrier = scene.resident_runtimes[0]
		scene.gatherer_hut_data.resources.add(FOOD, 1)
		scene.game_time.debug_next_phase()
		export_job = scene.logistics.current_job
		if picked_up: carrier.view._process(20)
		carrier.data.hunger = 100
		check(export_job.state == Job.State.CANCELLED and scene.gatherer_hut_data.resources.get_reserved_out(FOOD) == 0 and scene.warehouse_data.resources.get_reserved_in(FOOD) == 0 and carrier.data.inventory.amount == 0, "Forced export cancellation clears exactly hut/warehouse reservations and inventory")
		check(scene.ground_resources.drops.size() == (1 if picked_up else 0) and scene.gatherer_hut_data.resources.get_amount(FOOD) == (0 if picked_up else 1), "Loaded export creates ground FOOD; unloaded FOOD stays in hut")
		scene.free()
	print("Production logistics checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
