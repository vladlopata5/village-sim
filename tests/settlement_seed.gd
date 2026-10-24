extends RefCounted
## Test-only prebuilt settlement seed; never a playable new-game setup.
static func buildings(world: Node) -> void:
	world.kitchen_data = preload("res://scripts/building_data.gd").new(&"communal_kitchen_01", "Общая кухня", preload("res://scripts/building_type.gd").Type.FOOD)
	world.kitchen_data.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.FOOD, preload("res://scripts/balance_config.gd").KITCHEN_FOOD_CAPACITY)
	world.buildings.append(world.kitchen_data)
	# Same ID links two distinct data objects: building meaning and world place.
	world.kitchen_data.position = Vector2(-275, 237.5)
	var view = world._create_building_presentation(world.kitchen_data)
	view.name = "CommunalKitchen"
	world._register_building_location(world.kitchen_data, view)
	world.warehouse_data = preload("res://scripts/building_data.gd").new(&"warehouse_01", "Склад", preload("res://scripts/building_type.gd").Type.STORAGE)
	world.warehouse_data.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.FOOD, 20)
	world.warehouse_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 10)
	world.warehouse_data.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.LOG, preload("res://scripts/balance_config.gd").WAREHOUSE_LOG_CAPACITY)
	world.warehouse_data.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.PLANK, preload("res://scripts/balance_config.gd").WAREHOUSE_PLANK_CAPACITY)
	world.warehouse_data.resources.set_capacity(preload("res://scripts/resource_type.gd").Type.STONE, preload("res://scripts/balance_config.gd").STORAGE_STONE_CAPACITY)
	# Historical reference stock stays fixed when current construction recipes change.
	world.warehouse_data.resources.add(preload("res://scripts/resource_type.gd").Type.PLANK, 35)
	world.buildings.append(world.warehouse_data)
	world.warehouse_data.position = Vector2(300, 237.5)
	view = world._create_building_presentation(world.warehouse_data)
	view.name = "Warehouse"
	world._register_building_location(world.warehouse_data, view)
	world.gatherer_hut_data = preload("res://scripts/building_data.gd").new(&"gatherer_hut_01", "Хижина собирателя", preload("res://scripts/building_type.gd").Type.GATHERER_HUT)
	world.buildings.append(world.gatherer_hut_data)
	world.gatherer_hut_data.position = Vector2(375, -237.5)
	view = world._create_building_presentation(world.gatherer_hut_data)
	view.name = "GathererHut"
	world._register_building_location(world.gatherer_hut_data, view)
static func home_id(index: int) -> StringName:
	return [&"home_stepan", &"home_anna", &"home_fedor", &"home_marina"][index]
static func home(world: Node, _data: RefCounted, index: int) -> void:
	var positions = [Vector2(-300,-125),Vector2(-100,-200),Vector2(100,-200),Vector2(300,-125)]
	var instance = preload("res://scripts/building_instance.gd")
	var definition = preload("res://scripts/building_definition.gd")
	var house = instance.new(home_id(index),definition.for_type(preload("res://scripts/building_type.gd").Type.HOME),positions[index],instance.State.BUILT)
	world.buildings.append(house)
	world._show_building(house)
