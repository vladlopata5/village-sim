extends SceneTree
const Logistics = preload("res://scripts/logistics_controller.gd")
const Job = preload("res://scripts/haul_job.gd")
const Building = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Resources = preload("res://scripts/resource_type.gd")
const FOOD = Resources.Type.FOOD
class RejectIncoming extends "res://scripts/resource_container.gd":
	func reserve_in(_resource: Resources.Type, _amount: int) -> bool:
		return false
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var source = Building.new(&"warehouse_01", "Склад", BuildingType.Type.STORAGE)
	var destination = Building.new(&"communal_kitchen_01", "Общая кухня", BuildingType.Type.FOOD)
	source.resources.set_capacity(FOOD, 20)
	source.resources.add(FOOD, 10)
	destination.resources.set_capacity(FOOD, 5)
	var resident = Data.new("resident_001", "Степан", 30)
	resident.work_location_id = source.id
	var controller = Logistics.new()
	controller.setup(source, destination, resident)
	controller.recalculate()
	var job = controller.current_job
	check(job is RefCounted and not job is Node and job.state == Job.State.RESERVED, "Job exists as nonvisual data, waits for porter")
	check(job.source_location_id == source.id and job.destination_location_id == destination.id and job.resource_type == FOOD and job.amount == 1, "Job route and resource")
	check(job.assigned_resident_id.is_empty() and source.resources.get_reserved_out(FOOD) == 1 and destination.resources.get_reserved_in(FOOD) == 1, "Both promises belong to one job")
	resident.profession = Profession.Type.PORTER
	resident.work_location_id = &"other"
	controller.recalculate()
	check(job.state == Job.State.RESERVED, "Porter at another workplace not eligible")
	resident.work_location_id = source.id
	controller.recalculate()
	check(job.state == Job.State.ASSIGNED and job.assigned_resident_id == resident.id, "Warehouse porter assigned existing reservation")
	for _repeat in range(10):
		controller.recalculate()
	check(controller.current_job == job and source.resources.get_reserved_out(FOOD) == 1 and destination.resources.get_reserved_in(FOOD) == 1, "Repeated recalculation never duplicates active route")
	check(source.resources.get_amount(FOOD) == 10 and destination.resources.get_amount(FOOD) == 0, "Assignment never moves food")
	check(controller.cancel_job(job) and job.state == Job.State.CANCELLED and source.resources.get_reserved_out(FOOD) == 0 and destination.resources.get_reserved_in(FOOD) == 0, "Cancellation frees both owned reserves")
	check(not controller.cancel_job(job), "Repeated cancellation does not release someone else's reserves")
	controller.recalculate()
	check(controller.current_job.id != job.id and not controller.cancel_job(job), "New job has stable new ID; stale cancellation rejected")
	controller.cancel_job(controller.current_job)
	destination.resources.add(FOOD, 3)
	controller.recalculate()
	check(not controller.current_job.is_active(), "No job when target stock met")
	destination.resources.try_take(FOOD, 1)
	destination.resources.reserve_in(FOOD, 1)
	controller.recalculate()
	check(not controller.current_job.is_active(), "Incoming reserves count toward target")
	destination.resources.release_in(FOOD, 1)
	source.resources.reserve_out(FOOD, 10)
	controller.recalculate()
	check(not controller.current_job.is_active() and destination.resources.get_reserved_in(FOOD) == 0, "No available source stock means no destination promise")
	source.resources.release_out(FOOD, 10)
	destination.resources.set_capacity(FOOD, 2)
	controller.recalculate()
	check(not controller.current_job.is_active() and source.resources.get_reserved_out(FOOD) == 0, "Full destination means no source promise")
	# Force the second reservation to fail after preflight; preserve unrelated reserves.
	destination.resources = RejectIncoming.new(destination.id)
	destination.resources.set_capacity(FOOD, 5)
	source.resources.reserve_out(FOOD, 2)
	var rollback = Logistics.new()
	rollback.setup(source, destination, resident)
	rollback.recalculate()
	check(rollback.current_job == null and source.resources.get_reserved_out(FOOD) == 2 and destination.resources.get_reserved_in(FOOD) == 0, "Second reservation failure rolls back only this attempt, no job")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.resident_view.set_process(false)
	check(not scene.has_node("World/WorkPoint") and scene.world_locations.get_location(&"work_stepan") == null, "Obsolete work marker removed")
	check(scene.resident_data.work_location_id == &"warehouse_01" and scene.logistics.current_job.state == Job.State.ASSIGNED, "Stepan works at warehouse and has assigned job")
	var position: Vector2 = scene.resident_view.global_position
	var intent = scene.resident_intents.current_intent
	paused = true
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F12
		event.pressed = pressed
		root.push_input(event, true)
	check(scene.resident_view.global_position == position and scene.resident_intents.current_intent == intent and scene.warehouse_data.resources.get_amount(FOOD) == 10 and scene.kitchen_data.resources.get_amount(FOOD) == 0, "F12 on pause makes no movement, intent or transfer")
	check(scene.logistics_label.text.contains("зарезервировано на вывоз: 1") and scene.logistics_label.text.contains("зарезервировано под доставку: 1") and scene.logistics_label.text.contains("Степан: доставить 1 FOOD → Общая кухня"), "UI shows actual job and both reserves")
	paused = false
	scene.game_time.debug_next_phase()
	check(scene.resident_view.target_position == scene.world_locations.get_position(&"warehouse_01"), "07:00 delivery uses warehouse source")
	scene.resident_view._process(20.0)
	check(scene.resident_data.inventory.amount == 1 and scene.logistics.current_job.state == Job.State.GOING_TO_DESTINATION, "Arriving at warehouse picks up reserved cargo")
	scene.free()
	print("Logistics checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
