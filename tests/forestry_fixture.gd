extends RefCounted
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
static func hut(scene: Node, id: StringName = &"test_hut", position: Vector3 = Vector3(-20,0,-8)):
	var building = Instance.new(id,Definition.for_type(BuildingType.Type.LUMBERJACK_HUT),Coordinates.to_sim(position))
	scene.buildings.append(building)
	scene._show_building(building)
	return building
static func clear_drops(scene: Node) -> void:
	for drop in scene.ground_resources.drops.duplicate():
		scene.ground_resources.drops.erase(drop)
		scene.ground_resources.removed.emit(drop)
