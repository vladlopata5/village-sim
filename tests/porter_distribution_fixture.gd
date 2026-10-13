extends RefCounted
## Valid distributed staffing for integration tests; never expands gameplay capacity.
const Definition = preload("res://scripts/building_definition.gd")
const BT = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
static func assign(world: Node, actors: Array) -> bool:
	var workplaces: Array = []
	for index in ceili(actors.size()/2.0):
		var point := Vector3(-48+(index%5)*24,0,-27+floori(index/5.0)*27)
		var result: Dictionary = world.debug_spawn.spawn_building(point,Definition.for_type(BT.STORAGE))
		if not result.ok: return false
		workplaces.append(result.objects[0])
	for index in actors.size():
		if not world.player_control.assign_workplace(actors[index].data.id,workplaces[floori(index/2.0)].id,P.PORTER): return false
	return true
