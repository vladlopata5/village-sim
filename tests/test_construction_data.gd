extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd")
const Resources = preload("res://scripts/resource_type.gd")
const Storage = preload("res://scripts/resource_container.gd")
const FOOD = Resources.Type.FOOD
const WOOD = Resources.Type.WOOD
var checks := 0
var failures := 0
var changes := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _on_change() -> void: changes += 1
func _run() -> void:
	check(FOOD == 0 and WOOD != FOOD and Resources.display_name(WOOD) == "Древесина", "WOOD appended with readable name, FOOD identity preserved")
	var warehouse := Storage.new(&"warehouse_test")
	warehouse.set_capacity(FOOD, 20)
	check(warehouse.add(FOOD, 5) and warehouse.reserve_out(FOOD, 1) and warehouse.take_reserved(FOOD, 1), "Existing FOOD storage and reservations still work")
	check(warehouse.get_capacity(WOOD) == 0 and not warehouse.add(WOOD, 1), "WOOD gets no implicit capacity or stock")
	warehouse.set_capacity(WOOD, 20)
	check(warehouse.add(WOOD, 15) and warehouse.reserve_out(WOOD, 2) and warehouse.take_reserved(WOOD, 2), "Generic container supports explicit WOOD stock/reservations")
	for category in [Types.Type.HOME, Types.Type.STORAGE, Types.Type.FOOD, Types.Type.GATHERER_HUT]:
		var definition = Definition.for_type(category)
		var small: bool = category in [Types.Type.HOME, Types.Type.GATHERER_HUT]
		check(definition.construction_requirements == {WOOD: 10 if small else 15}, "Each definition has correct WOOD requirement")
		check(definition.construction_work_required == (180 if small else 240) and definition.max_builders == 2, "Each definition has prototype work-minutes and two builder slots")
	var home = Instance.new(&"site_home", Definition.for_type(Types.Type.HOME), Vector2(100, 200), Instance.State.UNDER_CONSTRUCTION)
	var other = Instance.new(&"site_other", home.definition, Vector2.ZERO, Instance.State.UNDER_CONSTRUCTION)
	home.construction_changed.connect(_on_change)
	check(home.construction_delivered == {WOOD: 0} and home.construction_progress == 0 and home.active_builder_ids.is_empty(), "New construction starts with zero actual delivery/work/owners")
	check(home.get_required_amount(WOOD) == 10 and home.get_missing_amount(WOOD) == 10 and not home.are_construction_materials_complete(), "Missing and materials-complete use actual local delivery")
	check(home.get_delivered_amount(WOOD) == 0 and warehouse.get_amount(WOOD) == 13, "Warehouse stock and reservation do not count as delivered")
	check(not home.add_delivered_material(FOOD, 1) and not home.add_delivered_material(WOOD, -1) and not home.add_delivered_material(WOOD, 11), "Unexpected/negative/excess material arrivals rejected atomically")
	check(home.add_delivered_material(WOOD, 4) and changes == 1 and home.get_missing_amount(WOOD) == 6, "Explicit actual arrival updates delivery, missing and signal")
	check(other.get_delivered_amount(WOOD) == 0 and warehouse.get_amount(WOOD) == 13, "Instances own separate construction stock, helper does not transfer warehouse stock")
	var copy: Dictionary = home.construction_delivered
	copy[WOOD] = 99
	check(home.get_delivered_amount(WOOD) == 4, "Delivered accessor cannot bypass local mutation API")
	check(not home.can_complete_construction() and not home.complete_construction(), "Missing materials and work prevent completion")
	home.construction_progress = -10
	check(home.construction_progress == 0, "Negative progress clamped")
	check(home.add_construction_work(90) and is_equal_approx(home.get_construction_progress_ratio(), 0.5), "Actual work-minutes produce correct progress ratio")
	home.construction_progress = 999
	check(home.construction_progress == 180 and not home.can_complete_construction(), "Progress capped at required; full work alone insufficient")
	home.state = Instance.State.BUILT
	check(not home.is_built(), "Direct state write cannot bypass completion conditions")
	check(home.add_delivered_material(WOOD, 6) and home.are_construction_materials_complete(), "Complete material set recognized")
	check(home.can_complete_construction() and not home.is_built(), "Materials plus work enable explicit completion, do not auto-complete")
	check(other.add_delivered_material(WOOD, 10) and not other.can_complete_construction(), "Full materials without work insufficient")
	check(home.has_free_builder_slot() and home.claim_builder_slot("a"), "Builder can claim available slot")
	check(not home.claim_builder_slot("a") and home.active_builder_ids.size() == 1, "Duplicate owner never takes second slot")
	check(home.claim_builder_slot("b") and not home.has_free_builder_slot() and not home.claim_builder_slot("c"), "Cannot exceed definition builder limit")
	var owners: Array[String] = home.active_builder_ids
	owners.clear()
	check(home.active_builder_ids.size() == 2, "Owner accessor cannot bypass slot API")
	check(home.release_builder_slot("a") and home.has_free_builder_slot() and not home.release_builder_slot("missing"), "Release frees exactly owned slot")
	check(not home.claim_builder_slot(""), "Empty resident ID cannot own slot")
	var original_resources: RefCounted = home.resources
	home.production_progress = 12
	check(home.complete_construction() and home.is_built() and home.id == &"site_home" and home.resources == original_resources and home.production_progress == 12, "Completion retains identity, output storage and unrelated production data")
	check(home.active_builder_ids.is_empty() and not home.claim_builder_slot("a") and not home.complete_construction(), "Finished site releases owners and rejects further claims/completion")
	home.state = Instance.State.UNDER_CONSTRUCTION
	home.construction_progress = 0
	check(home.is_built() and home.construction_progress == 180 and not home.add_delivered_material(WOOD, 1), "Built instance cannot revert or continue construction writes")
	var scene = Setup.make_scene(self)
	for initial in scene.buildings:
		check(initial.is_built() and initial.construction_progress == 0 and initial.get_delivered_amount(WOOD) == 0 and initial.active_builder_ids.is_empty(), "Starting BUILT buildings need no retroactive construction")
	var card = scene.get_node("HUD/BuildingCard")
	for category in [Types.Type.HOME, Types.Type.STORAGE, Types.Type.FOOD, Types.Type.GATHERER_HUT]:
		scene.placement.select(Definition.for_type(category))
		scene.placement.update_position(Vector2(-1000 - int(category) * 200, 100))
		var placed_site = scene.placement.confirm()
		check(placed_site != null and not placed_site.is_built() and placed_site.construction_delivered == {WOOD: 0} and placed_site.construction_progress == 0 and placed_site.active_builder_ids.is_empty(), "Placement initializes each construction type correctly")
		check(placed_site.resources.get_capacity(WOOD) == 0 and placed_site.resources.get_capacity(FOOD) == 0, "Placement does not create working storage or WOOD logistics")
	var site = scene.buildings.back()
	scene.resident_selection.select_building(site)
	check(card.construction_section.visible and "Древесина: 0 / 10" in card.construction_materials.text, "Selected construction card displays real requirements")
	check(card.construction_work.text == "Прогресс: 0 / 180 мин\n0%" and card.construction_builders.text == "Строители: 0 / 2", "Card shows actual work/proportion/slots")
	site.add_delivered_material(WOOD, 4)
	site.add_construction_work(90)
	site.claim_builder_slot("test_builder")
	check("Древесина: 4 / 10" in card.construction_materials.text and "90 / 180 мин\n50%" in card.construction_work.text and "1 / 2" in card.construction_builders.text, "Local signals update all construction fields immediately without frames")
	var before: int = site.construction_progress
	scene.game_time.debug_skip_minutes(60)
	check(site.construction_progress == before and site.get_delivered_amount(WOOD) == 4, "GameTime does not simulate builder work or material delivery")
	site.add_delivered_material(WOOD, 6)
	site.add_construction_work(90)
	site.complete_construction()
	check(not card.construction_section.visible and card.state_label.text == "Состояние: Построено", "Completion signal hides construction section on BUILT card")
	check(not scene.world_locations.get_view(site.id).get_node("Caption").text.ends_with("строится"), "Existing visual updates after lifecycle completion")
	scene.resident_selection.select_building(scene.kitchen_data)
	check(not card.construction_section.visible, "Starting BUILT card never shows fake construction requirements")
	scene.free()
	print("Construction data: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
