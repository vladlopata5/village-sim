extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Logistics = preload("res://scripts/logistics_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const ControlAPI = preload("res://scripts/player_control.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func click(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
func _run() -> void:
	var world=preload("res://tests/canonical_ui_fixture.gd").make(self)
	await physics_frame
	await physics_frame
	var definition=Definition.for_type(Types.Type.HOME)
	world._select_building_definition(definition)
	var point=Vector2(-600,350)
	var screen_point=preload("res://tests/canonical_ui_fixture.gd").screen(world,point)
	var motion=InputEventMouseMotion.new()
	motion.position=screen_point
	root.push_input(motion,true)
	await process_frame
	await process_frame
	check(world.placement.is_active() and world.building_ghost.visible,"Real canonical placement/ghost")
	check(world.placement.can_place(),"Projected cursor snaps to valid grid cell")
	var count: int=world.buildings.size()
	preload("res://tests/canonical_ui_fixture.gd").click(self,screen_point)
	await physics_frame
	await physics_frame
	check(world.buildings.size()==count+1 and world.placement.is_active(),"One click one site; canonical repeats")
	world._cancel_building_placement()
	check(not world.placement.is_active() and not world.building_ghost.visible,"Cancel removes ghost")
	world.free()
	var scene=Setup.make_scene(self)
	var actor=scene.resident_runtimes[0]
	scene.placement.select(definition)
	scene.placement.update_position(Vector2(600,400))
	var placed=scene.placement.confirm()
	check(placed!=null and not scene.placement.is_active(),"Base domain confirm stays one-shot")
	scene.placement.select(Definition.for_type(Types.Type.STORAGE))
	scene.placement.update_position(Vector2(1000,400))
	var second=scene.placement.confirm()
	# State guards must work even if a caller configures storage on a construction instance.
	var kitchen := Instance.new(&"not_built_kitchen", Definition.for_type(Types.Type.FOOD), Vector2.ZERO, Instance.State.UNDER_CONSTRUCTION)
	kitchen.resources.set_capacity(FOOD, 20)
	kitchen.resources.add(FOOD, 3)
	scene.buildings.append(kitchen)
	check(actor.needs.get_food_target(kitchen.id) == null, "Unbuilt kitchen excluded from EAT target lookup")
	check(scene.interactions.get_interactions([actor.data.id], placed.id).is_empty(), "Construction instance has no normal interactions")
	scene.interactions.register_building(kitchen, func(): return Vector2.ZERO)
	check(scene.interactions.get_interactions([actor.data.id], kitchen.id).is_empty(), "Interaction registration itself rejects construction instances")
	var logistics = Logistics.new()
	logistics.setup(scene.warehouse_data, kitchen, null)
	logistics.recalculate()
	check(logistics.jobs.is_empty() and kitchen.resources.get_reserved_in(FOOD) == 0, "Unbuilt destination cannot receive logistics job or reservation")
	logistics.setup(second, scene.kitchen_data, null)
	second.resources.set_capacity(FOOD, 20)
	second.resources.add(FOOD, 3)
	logistics.recalculate()
	check(logistics.jobs.is_empty() and second.resources.get_reserved_out(FOOD) == 0, "Unbuilt source cannot generate logistics job")
	var control = ControlAPI.new()
	control.setup(scene.residents, [second])
	check(not control.assign_workplace(actor.data.id, second.id) and control.assign_profession(actor.data.id, Profession.Type.PORTER) and actor.data.work_location_id.is_empty() and not logistics.has_available_job(actor.data.id), "Construction storage cannot accept employment; Porter profession can remain unassigned")
	var hut := Instance.new(scene.gatherer_hut_data.id, scene.gatherer_hut_data.definition, scene.gatherer_hut_data.position, Instance.State.UNDER_CONSTRUCTION)
	hut.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.MUSHROOM, 5)
	scene.production.building = hut
	var gatherer = scene.resident_runtimes[2]
	gatherer.data.profession = Profession.Type.GATHERER
	gatherer.data.work_location_id = hut.id
	gatherer.data.activity = Activity.Type.WORKING
	gatherer.view.global_position = hut.position
	hut.production_progress = 12
	scene.production._on_minute(400)
	check(not scene.production.can_work(gatherer.data) and hut.production_progress == 12 and hut.resources.get_amount(preload("res://scripts/resource_type.gd").Type.MUSHROOM) == 0, "Construction hut neither offers work nor produces even with WORKING resident")
	for resource in hut.definition.construction_requirements:
		hut.add_delivered_material(resource, hut.get_required_amount(resource))
	hut.add_construction_work(hut.definition.construction_work_required)
	hut.complete_construction()
	scene.production._on_minute(401)
	check(hut.production_progress == 13, "Same instance resumes ordinary production when BUILT")

	var collision_registry: Array = [Instance.new(&"building_0001", Definition.for_type(Types.Type.HOME), Vector2(1000, 0))]
	var isolated_placement=preload("res://scripts/building_placement.gd").new()
	isolated_placement.setup(collision_registry)
	isolated_placement.select(definition)
	var collision_free=isolated_placement.confirm()
	check(collision_free.id==&"building_0002" and collision_registry.size()==2,"Stable allocator skips registered IDs")
	scene.free()
	print("Building placement: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
