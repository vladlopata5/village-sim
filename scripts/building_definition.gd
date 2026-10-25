extends RefCounted
## Shared type description, not a building on the map.
const Balance = preload("res://scripts/balance_config.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
# Prototype construction balance belongs to type definitions, not execution.
const BuildingType = preload("res://scripts/building_type.gd")
const Recipe = preload("res://scripts/production_recipe.gd")
const CONSTRUCTION_BALANCE = {
	BuildingType.Type.GAZEBO: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:2},"minutes":120,"builders":2},
	BuildingType.Type.FLOWERBED: {"requirements":{ResourceType.Type.PLANK:1,ResourceType.Type.STONE:1},"minutes":30,"builders":2},
	BuildingType.Type.CLAY_HUT: {"requirements":{ResourceType.Type.LOG:8,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.STONEMASON_WORKSHOP: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.POTTERY_WORKSHOP: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.WELL: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.STONE:4},"minutes":120,"builders":2},
	BuildingType.Type.WINDMILL: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.FARM: {"requirements":{ResourceType.Type.LOG:6,ResourceType.Type.PLANK:8,ResourceType.Type.STONE:4},"minutes":240,"builders":2},
	BuildingType.Type.WEAVER_WORKSHOP: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.TAILOR_WORKSHOP: {"requirements":{ResourceType.Type.LOG:6,ResourceType.Type.PLANK:8,ResourceType.Type.STONE:4},"minutes":240,"builders":2},
	BuildingType.Type.SHEPHERD_HUT: {"requirements":{ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6},"minutes":180,"builders":2},
	BuildingType.Type.TOWN_CENTER: {"requirements":{},"minutes":240,"builders":2},
	BuildingType.Type.QUARRY: {"requirements": {ResourceType.Type.LOG:8,ResourceType.Type.STONE:4},"minutes":180,"builders":2},
	BuildingType.Type.SAWMILL: {"requirements": {ResourceType.Type.LOG:6,ResourceType.Type.STONE:6},"minutes":240,"builders":2},
	BuildingType.Type.LUMBERJACK_HUT: {"requirements": {ResourceType.Type.LOG:10},"minutes":180,"builders":2},
	BuildingType.Type.FOOD: {"requirements": {ResourceType.Type.LOG:6}, "minutes": 240, "builders": 2},
	BuildingType.Type.STORAGE: {"requirements": {ResourceType.Type.LOG:2,ResourceType.Type.STONE:4,ResourceType.Type.PLANK:6}, "minutes": 240, "builders": 2},
	BuildingType.Type.GATHERER_HUT: {"requirements": {ResourceType.Type.LOG:6}, "minutes": 180, "builders": 2},
	BuildingType.Type.HOME: {"requirements": {ResourceType.Type.LOG:8,ResourceType.Type.STONE:2}, "minutes": 180, "builders": 2},
}
# Explicit 3D physical area in build cells; size remains the shared logical footprint in simulation coordinates.
const FOOTPRINT_CELLS = {
	BuildingType.Type.GAZEBO: Vector2i(6,6),
	BuildingType.Type.FLOWERBED: Vector2i(2,2),
	BuildingType.Type.CLAY_HUT: Vector2i(12,8),
	BuildingType.Type.STONEMASON_WORKSHOP: Vector2i(12,8),
	BuildingType.Type.POTTERY_WORKSHOP: Vector2i(12,8),
	BuildingType.Type.WELL: Vector2i(6,4),
	BuildingType.Type.WINDMILL: Vector2i(12,8),
	BuildingType.Type.FARM: Vector2i(12,8),
	BuildingType.Type.WEAVER_WORKSHOP: Vector2i(12,8),
	BuildingType.Type.TAILOR_WORKSHOP: Vector2i(12,8),
	BuildingType.Type.SHEPHERD_HUT: Vector2i(12,8),
	BuildingType.Type.QUARRY: Vector2i(12,8),
	BuildingType.Type.TOWN_CENTER: Vector2i(16,12),
	BuildingType.Type.SAWMILL: Vector2i(12,8),
	BuildingType.Type.LUMBERJACK_HUT: Vector2i(8,6),
	BuildingType.Type.HOME: Vector2i(6, 4),
	BuildingType.Type.STORAGE: Vector2i(12, 8),
	BuildingType.Type.FOOD: Vector2i(12, 8),
	BuildingType.Type.GATHERER_HUT: Vector2i(12, 8),
}
# External haul policy is independent from ResourceContainer storage/direct deposits.
const LOGISTICS_FLOW = {
	BuildingType.Type.CLAY_HUT: {ResourceType.Type.CLAY:{"import":false,"export":true}},
	BuildingType.Type.STONEMASON_WORKSHOP: {ResourceType.Type.STONE:{"import":true,"export":false},ResourceType.Type.STONE_BRICK:{"import":false,"export":true}},
	BuildingType.Type.POTTERY_WORKSHOP: {ResourceType.Type.CLAY:{"import":true,"export":false},ResourceType.Type.BRICK:{"import":false,"export":true},ResourceType.Type.LOG:{"import":true,"export":false}},
	BuildingType.Type.WINDMILL: {ResourceType.Type.WHEAT:{"import":true,"export":false},ResourceType.Type.FLOUR:{"import":false,"export":true}},
	BuildingType.Type.FARM: {ResourceType.Type.WHEAT:{"import":true,"export":true},ResourceType.Type.SHEAF:{"import":true,"export":false},ResourceType.Type.STRAW:{"import":false,"export":true}},
	BuildingType.Type.WEAVER_WORKSHOP: {ResourceType.Type.WOOL:{"import":true,"export":false},ResourceType.Type.WOOL_CLOTH:{"import":false,"export":true}},
	BuildingType.Type.TAILOR_WORKSHOP: {ResourceType.Type.WOOL_CLOTH:{"import":true,"export":false},ResourceType.Type.WOOL_CLOTHING:{"import":false,"export":true}},
	BuildingType.Type.SHEPHERD_HUT: {ResourceType.Type.WOOL:{"import":false,"export":true}},
	BuildingType.Type.QUARRY: {ResourceType.Type.STONE:{"import":false,"export":true}},
	BuildingType.Type.TOWN_CENTER: {
		ResourceType.Type.FOOD: {"import":true,"export":true},
		ResourceType.Type.LOG: {"import":true,"export":true},
		ResourceType.Type.PLANK: {"import":true,"export":true},
		ResourceType.Type.STONE: {"import":true,"export":true},
		ResourceType.Type.MUSHROOM: {"import":true,"export":true},
		ResourceType.Type.FRIED_MUSHROOM: {"import":true,"export":true},
		ResourceType.Type.WOOL: {"import":true,"export":true},
		ResourceType.Type.WOOL_CLOTH: {"import":true,"export":true},
		ResourceType.Type.WOOL_CLOTHING: {"import":true,"export":true},
		ResourceType.Type.WHEAT: {"import":true,"export":true},
		ResourceType.Type.SHEAF: {"import":true,"export":true},
		ResourceType.Type.STRAW: {"import":true,"export":true},
		ResourceType.Type.FLOUR: {"import":true,"export":true},
		ResourceType.Type.BREAD: {"import":true,"export":true},
		ResourceType.Type.CLAY: {"import":true,"export":true},
		ResourceType.Type.BRICK: {"import":true,"export":true},
		ResourceType.Type.STONE_BRICK: {"import":true,"export":true},
	},
	BuildingType.Type.SAWMILL: {
		ResourceType.Type.LOG: {"import":true,"export":false},
		ResourceType.Type.PLANK: {"import":false,"export":true},
	},
	BuildingType.Type.STORAGE: {
		ResourceType.Type.FOOD: {"import":true,"export":true},
		ResourceType.Type.LOG: {"import":true,"export":true},
		ResourceType.Type.PLANK: {"import":true,"export":true},
		ResourceType.Type.STONE: {"import":true,"export":true},
		ResourceType.Type.MUSHROOM: {"import":true,"export":true},
		ResourceType.Type.FRIED_MUSHROOM: {"import":true,"export":true},
		ResourceType.Type.WOOL: {"import":true,"export":true},
		ResourceType.Type.WOOL_CLOTH: {"import":true,"export":true},
		ResourceType.Type.WOOL_CLOTHING: {"import":true,"export":true},
		ResourceType.Type.WHEAT: {"import":true,"export":true},
		ResourceType.Type.SHEAF: {"import":true,"export":true},
		ResourceType.Type.STRAW: {"import":true,"export":true},
		ResourceType.Type.FLOUR: {"import":true,"export":true},
		ResourceType.Type.BREAD: {"import":true,"export":true},
		ResourceType.Type.CLAY: {"import":true,"export":true},
		ResourceType.Type.BRICK: {"import":true,"export":true},
		ResourceType.Type.STONE_BRICK: {"import":true,"export":true},
	},
	BuildingType.Type.FOOD: {ResourceType.Type.WATER:{"import":true,"export":false},ResourceType.Type.LOG:{"import":true,"export":false},ResourceType.Type.FLOUR:{"import":true,"export":false},ResourceType.Type.BREAD:{"import":false,"export":true},ResourceType.Type.FOOD:{"import":true,"export":false}, ResourceType.Type.MUSHROOM:{"import":true,"export":false}, ResourceType.Type.FRIED_MUSHROOM:{"import":false,"export":true}},
	BuildingType.Type.GATHERER_HUT: {ResourceType.Type.MUSHROOM:{"import":false,"export":true}},
	BuildingType.Type.LUMBERJACK_HUT: {ResourceType.Type.LOG:{"import":false,"export":true}},
}
const Stage = preload("res://scripts/construction_stage.gd")
const CONSTRUCTION_STAGES = {
	BuildingType.Type.GAZEBO: [
		[&"step_1","Основание",{ResourceType.Type.STONE:2},30,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},40,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},50,&"complete"],
	],
	BuildingType.Type.FLOWERBED: [
		[&"step_1","Основание",{ResourceType.Type.STONE:1},10,&"base"],
		[&"step_2","Завершение",{ResourceType.Type.PLANK:1},20,&"complete"],
	],
	BuildingType.Type.FOOD: [
		[&"step_1","Основание",{ResourceType.Type.LOG:2},60,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:2},100,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:2},80,&"complete"],
	],
	BuildingType.Type.STORAGE: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},60,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:2},100,&"frame"],
		[&"step_3","Стены и завершение",{ResourceType.Type.PLANK:6},80,&"complete"],
	],
	BuildingType.Type.GATHERER_HUT: [
		[&"step_1","Основание",{ResourceType.Type.LOG:2},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:2},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:2},60,&"complete"],
	],
	BuildingType.Type.HOME: [
		[&"step_1","Основание",{ResourceType.Type.STONE:2},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:4},60,&"complete"],
	],
	BuildingType.Type.LUMBERJACK_HUT: [
		[&"step_1","Основание",{ResourceType.Type.LOG:3},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:3},60,&"complete"],
	],
	BuildingType.Type.SAWMILL: [
		[&"step_1","Основание",{ResourceType.Type.STONE:6},60,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:3},100,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:3},80,&"complete"],
	],
	BuildingType.Type.TOWN_CENTER: [
		[&"step_1","Восстановление конструкции",{},240,&"complete"],
	],
	BuildingType.Type.QUARRY: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:4},60,&"complete"],
	],
	BuildingType.Type.CLAY_HUT: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.LOG:4},60,&"complete"],
	],
	BuildingType.Type.SHEPHERD_HUT: [
		[&"step_1","Основание",{ResourceType.Type.LOG:2},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:2},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},60,&"complete"],
	],
	BuildingType.Type.WEAVER_WORKSHOP: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},60,&"complete"],
	],
	BuildingType.Type.STONEMASON_WORKSHOP: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},60,&"complete"],
	],
	BuildingType.Type.POTTERY_WORKSHOP: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},60,&"complete"],
	],
	BuildingType.Type.TAILOR_WORKSHOP: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},60,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:6},100,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:8},80,&"complete"],
	],
	BuildingType.Type.FARM: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},60,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:6},100,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:8},80,&"complete"],
	],
	BuildingType.Type.WINDMILL: [
		[&"step_1","Основание",{ResourceType.Type.STONE:4},45,&"base"],
		[&"step_2","Каркас",{ResourceType.Type.LOG:4},75,&"frame"],
		[&"step_3","Завершение",{ResourceType.Type.PLANK:6},60,&"complete"],
	],
	BuildingType.Type.WELL: [
		[&"step_1","Каменное основание",{ResourceType.Type.STONE:4},60,&"base"],
		[&"step_2","Навес и завершение",{ResourceType.Type.LOG:4},60,&"complete"],
	],
}
var construction_stages: Array[Stage] = []
var upgrades: Array = []
var development_level := 1
const Profession = preload("res://scripts/resident_profession.gd")
var initial_stock_targets: Dictionary = {} # Generic minimum inputs, separate from recipe kits.
var animal_capacity := 0
var planned_wool_capacity := 0 # Integration point for S3; no fake resource/recipe.
var worker_profession: int = Profession.Type.NONE
var internal_resources: Array = []
var consumable_definitions: Dictionary = {}
var resource_capacities: Dictionary = {} # Optional concrete production buffers, independent of warehouse quotas.
var production_recipes: Array[Recipe] = []
var production_recipe: Recipe: # Read-only compatibility for the unchanged single-recipe UI/supply.
	get: return production_recipes[0] if not production_recipes.is_empty() else null
var logistics_flow: Dictionary
var visitor_capacity := 0
var worker_capacity := 0 # Zero keeps existing unlimited workplace semantics.
var porter_capacity := 0 # Zero forbids logistics staffing; independent from worker slots.
var ground_search_radius := -1.0 # Simulation units; negative means shared default, zero is a point.
var work_radius := 0.0 # WORLD units, unrelated to visual footprint.
var target_tree_count := 0
var local_resource_capacity := 0
var footprint_cells: Vector2i
var id: StringName
var type: BuildingType.Type
var display_name: String
var size: Vector2
var construction_requirements: Dictionary
var construction_work_required: int
var max_builders: int
var housing_capacity: int
var is_storage := false
var fallback_housing_capacity := 0
var player_buildable := true
func _init(type_id: StringName, category: BuildingType.Type, label: String, footprint_size: Vector2, requirements: Dictionary = {}, work_minutes: int = 0, builder_limit: int = 0, resident_capacity: int = 0) -> void:
	id = type_id
	type = category
	porter_capacity = 0 if category in [BuildingType.Type.HOME,BuildingType.Type.WELL,BuildingType.Type.GAZEBO,BuildingType.Type.FLOWERBED] else (2 if category in [BuildingType.Type.STORAGE,BuildingType.Type.TOWN_CENTER] else 1)
	logistics_flow = LOGISTICS_FLOW.get(category,{}).duplicate(true)
	footprint_cells = FOOTPRINT_CELLS[category]
	display_name = label
	size = footprint_size
	construction_requirements = requirements.duplicate()
	construction_work_required = maxi(work_minutes, 0)
	if construction_work_required>0:construction_stages.append(Stage.new(&"build","Строительство",requirements,construction_work_required,&"complete"))
	max_builders = maxi(builder_limit, 0)
	housing_capacity = maxi(resident_capacity, 0)
static func for_type(category: BuildingType.Type, label: String = ""):
	var ids := [&"kitchen", &"warehouse", &"gatherer_hut", &"home", &"lumberjack_hut", &"sawmill", &"town_center", &"quarry", &"shepherd_hut", &"weaver_workshop", &"tailor_workshop", &"farm", &"windmill", &"well", &"clay_hut", &"pottery_workshop", &"stonemason_workshop", &"gazebo", &"flowerbed"]
	var labels := ["Кухня", "Склад", "Хижина собирателя", "Дом", "Хижина лесоруба", "Лесопилка", "Городской центр", "Каменоломня", "Хижина пастуха", "Мастерская ткача", "Швейная мастерская", "Ферма", "Мельница", "Колодец", "Хижина глинокопа", "Гончарная мастерская", "Каменотёсная мастерская", "Беседка", "Клумба"]
	var footprint_size := Vector2(64, 48) if category == BuildingType.Type.HOME else Vector2(144, 96)
	var construction: Dictionary = CONSTRUCTION_BALANCE.get(category,{"requirements":{},"minutes":0,"builders":0})
	var result = load("res://scripts/building_definition.gd").new(ids[category], category, labels[category] if label.is_empty() else label, footprint_size, construction.requirements, construction.minutes, construction.builders, Balance.HOUSE_RESIDENT_CAPACITY if category == BuildingType.Type.HOME else 0)

	result.construction_stages.clear()
	for row in CONSTRUCTION_STAGES[category]:result.construction_stages.append(Stage.new(row[0],row[1],row[2],row[3],row[4]))
	assert(result.validate_construction_stages(),"Construction stages must preserve type balance")
	result.worker_profession = {BuildingType.Type.FOOD:Profession.Type.COOK, BuildingType.Type.QUARRY:Profession.Type.MINER, BuildingType.Type.GATHERER_HUT:Profession.Type.GATHERER, BuildingType.Type.SAWMILL:Profession.Type.SAWYER, BuildingType.Type.LUMBERJACK_HUT:Profession.Type.LUMBERJACK}.get(category,Profession.Type.NONE)
	if category == BuildingType.Type.LUMBERJACK_HUT: result.internal_resources = [ResourceType.Type.LOG]
	if category == BuildingType.Type.GATHERER_HUT: result.worker_capacity = Balance.GATHERER_WORKER_CAPACITY
	if category == BuildingType.Type.GATHERER_HUT:
		result.resource_capacities = {ResourceType.Type.MUSHROOM:Balance.GATHERER_OUTPUT_CAPACITY}
		result.internal_resources = [ResourceType.Type.MUSHROOM]
		result.work_radius = Balance.LUMBERJACK_WORK_RADIUS
	if category == BuildingType.Type.GAZEBO:result.visitor_capacity=4
	if category == BuildingType.Type.FOOD:
		result.visitor_capacity = 4
		result.worker_capacity = Balance.KITCHEN_WORKER_CAPACITY
		result.resource_capacities = {ResourceType.Type.BREAD:Balance.KITCHEN_BREAD_CAPACITY, ResourceType.Type.FLOUR:Balance.KITCHEN_FLOUR_CAPACITY, ResourceType.Type.FOOD:Balance.KITCHEN_FOOD_CAPACITY, ResourceType.Type.MUSHROOM:Balance.KITCHEN_MUSHROOM_CAPACITY, ResourceType.Type.FRIED_MUSHROOM:Balance.KITCHEN_FRIED_MUSHROOM_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.MUSHROOM:1},{ResourceType.Type.FRIED_MUSHROOM:2},Balance.KITCHEN_WORK_MINUTES,&"fried_mushroom"))
		result.production_recipes[-1].consumables={&"fuel":1}
		result.production_recipes.append(Recipe.new({ResourceType.Type.FLOUR:1},{ResourceType.Type.BREAD:2},Balance.KITCHEN_WORK_MINUTES,&"bake_bread"))
		result.production_recipes[-1].consumables={&"fuel":1,&"water":1}
		result.consumable_definitions={&"fuel":{"label":"Топливо","capacity":Balance.KITCHEN_FUEL_CAPACITY,"materials":{ResourceType.Type.LOG:Balance.KITCHEN_LOG_FUEL}}}
	if category == BuildingType.Type.FOOD:
		result.consumable_definitions[&"water"]={"label":"Вода","capacity":Balance.KITCHEN_WATER_CAPACITY,"materials":{ResourceType.Type.WATER:Balance.WATER_CARGO_UNITS}}
	if category == BuildingType.Type.WELL:result.porter_capacity=0
	result.is_storage = category in [BuildingType.Type.STORAGE,BuildingType.Type.TOWN_CENTER]
	if category == BuildingType.Type.TOWN_CENTER:
		result.fallback_housing_capacity = Balance.TOWN_CENTER_FALLBACK_CAPACITY
		result.player_buildable = false
		result.size = Vector2(200,150)
	if category == BuildingType.Type.LUMBERJACK_HUT:
		result.worker_capacity = Balance.LUMBERJACK_WORKER_CAPACITY
		result.work_radius = Balance.LUMBERJACK_WORK_RADIUS
		result.target_tree_count = Balance.LUMBERJACK_TARGET_TREE_COUNT
		result.local_resource_capacity = Balance.LUMBERJACK_LOG_CAPACITY
	if category == BuildingType.Type.QUARRY:
		result.worker_capacity = Balance.QUARRY_WORKER_CAPACITY
		result.work_radius = Balance.QUARRY_WORK_RADIUS
		result.local_resource_capacity = Balance.QUARRY_STONE_CAPACITY
		result.internal_resources = [ResourceType.Type.STONE]
	if category == BuildingType.Type.CLAY_HUT:
		result.worker_profession = Profession.Type.CLAY_DIGGER
		result.worker_capacity = Balance.CLAY_HUT_WORKER_CAPACITY
		result.work_radius = Balance.CLAY_HUT_WORK_RADIUS
		result.local_resource_capacity = Balance.CLAY_HUT_CAPACITY
		result.internal_resources = [ResourceType.Type.CLAY]
	if category == BuildingType.Type.STONEMASON_WORKSHOP:
		result.worker_profession = Profession.Type.STONEMASON
		result.worker_capacity = 1
		result.resource_capacities = {ResourceType.Type.STONE:Balance.STONEMASON_INPUT_CAPACITY,ResourceType.Type.STONE_BRICK:Balance.STONEMASON_OUTPUT_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.STONE:1},{ResourceType.Type.STONE_BRICK:1},Balance.STONEMASON_WORK_MINUTES,&"cut_stone_brick"))
	if category == BuildingType.Type.POTTERY_WORKSHOP:
		result.worker_profession = Profession.Type.POTTER
		result.worker_capacity = 1
		result.resource_capacities = {ResourceType.Type.CLAY:Balance.POTTERY_INPUT_CAPACITY,ResourceType.Type.BRICK:Balance.POTTERY_OUTPUT_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.CLAY:1},{ResourceType.Type.BRICK:1},Balance.POTTERY_WORK_MINUTES,&"fire_brick"))
		result.production_recipes[-1].consumables = {&"fuel":1}
		result.consumable_definitions = {&"fuel":{"label":"Топливо","capacity":Balance.POTTERY_FUEL_CAPACITY,"materials":{ResourceType.Type.LOG:Balance.POTTERY_LOG_FUEL}}}
	if category == BuildingType.Type.SHEPHERD_HUT:
		result.worker_profession = Profession.Type.SHEPHERD
		result.worker_capacity = 1
		result.work_radius = Balance.LUMBERJACK_WORK_RADIUS
		result.animal_capacity = Balance.SHEPHERD_ANIMAL_CAPACITY
		result.planned_wool_capacity = Balance.SHEPHERD_WOOL_CAPACITY
		result.resource_capacities = {ResourceType.Type.WOOL:Balance.SHEPHERD_WOOL_CAPACITY}
		result.internal_resources = [ResourceType.Type.WOOL]
	if category == BuildingType.Type.WEAVER_WORKSHOP:
		result.worker_profession = Profession.Type.WEAVER
		result.worker_capacity = 1
		result.resource_capacities = {ResourceType.Type.WOOL:Balance.WEAVER_INPUT_CAPACITY,ResourceType.Type.WOOL_CLOTH:Balance.WEAVER_OUTPUT_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.WOOL:1},{ResourceType.Type.WOOL_CLOTH:1},Balance.WEAVER_WORK_MINUTES,&"wool_cloth"))
	if category == BuildingType.Type.TAILOR_WORKSHOP:
		result.worker_profession = Profession.Type.TAILOR
		result.worker_capacity = 1
		result.resource_capacities = {ResourceType.Type.WOOL_CLOTH:Balance.TAILOR_INPUT_CAPACITY,ResourceType.Type.WOOL_CLOTHING:Balance.TAILOR_OUTPUT_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.WOOL_CLOTH:3},{ResourceType.Type.WOOL_CLOTHING:1},Balance.TAILOR_WORK_MINUTES,&"wool_clothing"))
	if category == BuildingType.Type.WINDMILL:
		result.worker_profession = Profession.Type.MILLER
		result.worker_capacity = 1
		result.resource_capacities = {ResourceType.Type.WHEAT:Balance.MILL_INPUT_CAPACITY,ResourceType.Type.FLOUR:Balance.MILL_OUTPUT_CAPACITY}
		result.production_recipes.append(Recipe.new({ResourceType.Type.WHEAT:2},{ResourceType.Type.FLOUR:1},Balance.MILL_WORK_MINUTES,&"mill_flour"))
	if category == BuildingType.Type.FARM:
		result.worker_profession = Profession.Type.FARMER
		result.worker_capacity = 1
		result.work_radius = Balance.FARM_WORK_RADIUS
		result.resource_capacities = {ResourceType.Type.SHEAF:Balance.FARM_BUFFER_CAPACITY,ResourceType.Type.WHEAT:Balance.FARM_BUFFER_CAPACITY,ResourceType.Type.STRAW:Balance.FARM_BUFFER_CAPACITY}
		result.internal_resources = [ResourceType.Type.SHEAF,ResourceType.Type.WHEAT]
		result.initial_stock_targets = {ResourceType.Type.WHEAT:Balance.FARM_WHEAT_TARGET}
		result.production_recipes.append(Recipe.new({ResourceType.Type.SHEAF:1},{ResourceType.Type.WHEAT:1},Balance.FARM_THRESH_MINUTES,&"thresh_wheat"))
		result.production_recipes[-1].optional_outputs = {ResourceType.Type.STRAW:1}
	if category == BuildingType.Type.SAWMILL:
		result.worker_capacity = Balance.SAWMILL_WORKER_CAPACITY
		result.production_recipes.append(Recipe.new({ResourceType.Type.LOG:1},{ResourceType.Type.PLANK:1},Balance.SAWMILL_WORK_MINUTES,&"sawmill_plank"))
	if category in [BuildingType.Type.FOOD,BuildingType.Type.LUMBERJACK_HUT]:
		var upgrade=preload("res://scripts/building_upgrade.gd").new()
		upgrade.construction_requirements={ResourceType.Type.LOG:4,ResourceType.Type.PLANK:6,ResourceType.Type.STONE:2}
		upgrade.construction_stages.assign([
			Stage.new(&"prepare","Подготовка",{ResourceType.Type.STONE:2},40,&"base"),
			Stage.new(&"structure","Конструкция",{ResourceType.Type.LOG:4},60,&"frame"),
			Stage.new(&"finish","Завершение",{ResourceType.Type.PLANK:6},80,&"complete")])
		upgrade.worker_capacity=result.worker_capacity+(1 if category==BuildingType.Type.LUMBERJACK_HUT else 0)
		upgrade.recipes=result.production_recipes.duplicate()
		if category==BuildingType.Type.LUMBERJACK_HUT:
			upgrade.capacities={ResourceType.Type.LOG:result.local_resource_capacity+10}
			upgrade.local_resource_capacity=result.local_resource_capacity+10
			upgrade.description="Лесорубы: %d → %d\nБрёвна: %d → %d\nНосильщик и рабочая область без изменений"%[result.worker_capacity,upgrade.worker_capacity,result.local_resource_capacity,upgrade.local_resource_capacity]
		else:
			upgrade.capacities={ResourceType.Type.MUSHROOM:20,ResourceType.Type.FLOUR:20,ResourceType.Type.FRIED_MUSHROOM:20,ResourceType.Type.BREAD:20}
			upgrade.description="Грибы, мука, жареные грибы и хлеб: 10 → 20\nТопливо и вода: 20 → 20\nПовар и носильщик: 1 → 1"
		assert(upgrade.is_valid())
		result.upgrades.append(upgrade)
	if category==BuildingType.Type.HOME:
		var upgrade=preload("res://scripts/building_upgrade.gd").new()
		upgrade.household_count=Balance.HOME_LEVEL_2_HOUSEHOLDS
		upgrade.worker_capacity=0
		upgrade.construction_requirements={ResourceType.Type.LOG:4,ResourceType.Type.BRICK:4,ResourceType.Type.PLANK:6}
		upgrade.construction_stages.assign([
			Stage.new(&"frame","Дополнительный каркас",{ResourceType.Type.LOG:4},60,&"frame"),
			Stage.new(&"masonry","Кирпичные работы",{ResourceType.Type.BRICK:4},60,&"shell"),
			Stage.new(&"finish","Завершение",{ResourceType.Type.PLANK:6},60,&"complete")])
		upgrade.description="Хозяйства: 1 → 2\nЖилые места: 4 → 8\nПрежние жильцы продолжают жить в доме. Новые назначения закрыты до окончания работ."
		assert(upgrade.is_valid())
		result.upgrades.append(upgrade)
	return result

func upgraded_configuration(upgrade: RefCounted):
	# Definitions may be shared by isolated fixtures; never mutate another instance.
	var result=load("res://scripts/building_definition.gd").new(id,type,display_name,size)
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name!=&"production_recipe":
			var value: Variant=get(property.name)
			result.set(property.name,value.duplicate() if value is Array or value is Dictionary else value)
	result.development_level=upgrade.to_level
	result.worker_capacity=upgrade.worker_capacity
	if upgrade.household_count>0:result.housing_capacity=upgrade.housing_capacity
	if upgrade.local_resource_capacity>0:result.local_resource_capacity=upgrade.local_resource_capacity
	for resource in upgrade.capacities:result.resource_capacities[resource]=upgrade.capacities[resource]
	result.production_recipes.assign(upgrade.recipes)
	return result

func get_ground_search_radius() -> float:
	return ground_search_radius if is_finite(ground_search_radius) and ground_search_radius >= 0.0 else Balance.DEFAULT_BUILDING_GROUND_SEARCH_RADIUS

func allows_external_import(resource: int) -> bool:
	return logistics_flow.get(resource,{}).get("import",false)
func allows_external_export(resource: int) -> bool:
	return logistics_flow.get(resource,{}).get("export",false)

func allows_internal_import(resource: int) -> bool:
	return resource in internal_resources

func get_production_recipe(recipe_id: StringName) -> Recipe:
	if recipe_id.is_empty(): return null
	var found: Recipe = null
	for recipe in production_recipes:
		if recipe.id==recipe_id:
			if found!=null: return null # Duplicate IDs cannot identify a recipe safely.
			found=recipe
	return found

func validate_construction_stages() -> bool:
	if construction_work_required<=0:return construction_stages.is_empty() and construction_requirements.is_empty()
	if construction_stages.is_empty():return false
	var totals: Dictionary={};var ids: Dictionary={};var minutes:=0
	for stage in construction_stages:
		if stage==null or not stage.is_valid() or ids.has(stage.id):return false
		ids[stage.id]=true;minutes+=stage.work_minutes
		for resource in stage.materials:totals[resource]=int(totals.get(resource,0))+stage.materials[resource]
	return totals==construction_requirements and minutes==construction_work_required
