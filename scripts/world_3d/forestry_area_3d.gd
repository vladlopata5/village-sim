extends RefCounted
## Spatial queries and temporary planting claims; no permanent hut ownership of trees/drops.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Balance = preload("res://scripts/balance_config.gd")
const TreeData = preload("res://scripts/tree_data.gd")
var _world: WeakRef
var claims: Dictionary = {}
func setup(world: Node) -> void: _world = weakref(world)
func inside(hut: RefCounted, position: Vector2) -> bool:
	return Coordinates.length_to_world(hut.position.distance_to(position)) <= hut.definition.work_radius
func tree_count(hut: RefCounted) -> int:
	return _world.get_ref().trees.filter(func(tree): return tree.state != TreeData.State.DEPLETED and inside(hut,tree.position)).size()
func spot_valid(hut: RefCounted, position: Vector2, worker_id: String = "") -> bool:
	var world: Node = _world.get_ref()
	var point := Coordinates.to_world(position)
	if not inside(hut,position) or not world.navigation.is_world_walkable(point): return false
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
		if not world.navigation.is_world_walkable(point+direction*Balance.SAPLING_PHYSICAL_RADIUS): return false
	for tree in world.trees:
		if tree.state != TreeData.State.DEPLETED and Coordinates.length_to_world(tree.position.distance_to(position)) < Balance.TREE_MINIMUM_SPACING: return false
	for owner_id in claims:
		if owner_id != worker_id and Coordinates.length_to_world(claims[owner_id].distance_to(position)) < Balance.TREE_MINIMUM_SPACING: return false
	var center := Coordinates.world_plane(point)
	var rect := Rect2(center-Vector2.ONE*Balance.SAPLING_PHYSICAL_RADIUS,Vector2.ONE*Balance.SAPLING_PHYSICAL_RADIUS*2)
	return world.runtime_placement_blockers.first_overlap(rect).is_empty()
func planting_target(hut: RefCounted, from_position: Vector2) -> Dictionary:
	var world: Node = _world.get_ref()
	var samples: Array[Vector2] = []
	# Deterministic samples, ordered by travel proximity before bounded access queries.
	for ring in range(1,8):
		for index in range(16):
			var offset := Vector2.from_angle(index*TAU/16.0)*(ring*Balance.TREE_MINIMUM_SPACING)
			var position: Vector2 = hut.position+offset*Coordinates.SIM_UNITS_PER_WORLD_UNIT
			if spot_valid(hut,position): samples.append(position)
	samples.sort_custom(func(a,b): return a.distance_squared_to(from_position) < b.distance_squared_to(from_position))
	for position in samples:
		var temporary = TreeData.new(&"planting_candidate",position)
		temporary.physical_radius = Balance.SAPLING_PHYSICAL_RADIUS
		var access: Variant = world.tree_locations.resolve(temporary,from_position)
		if access is Vector2: return {"kind":&"PLANT","point":access,"spot":position}
	return {}
func claim(worker_id: String, hut: RefCounted, position: Vector2) -> bool:
	if claims.has(worker_id) or not spot_valid(hut,position): return false
	claims[worker_id] = position
	return true
func release(worker_id: String) -> void: claims.erase(worker_id)
func complete(worker_id: String, hut: RefCounted) -> bool:
	if not claims.has(worker_id): return false
	var position: Vector2 = claims[worker_id]
	var valid := spot_valid(hut,position,worker_id)
	claims.erase(worker_id)
	if valid: _world.get_ref().spawn_sapling(position)
	return valid
