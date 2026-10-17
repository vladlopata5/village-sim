extends RefCounted
## Spatial queries and temporary planting claims; no permanent hut ownership of trees/drops.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Balance = preload("res://scripts/balance_config.gd")
const TreeData = preload("res://scripts/tree_data.gd")
const Area = preload("res://scripts/work_area.gd")
var _world: WeakRef
var claims: Dictionary = {}
var _claim_areas: Dictionary = {} # Geometry accepted at claim time, not a second assignment.
func setup(world: Node) -> void: _world = weakref(world)
func _area(hut: RefCounted) -> RefCounted:
	return _world.get_ref().player_control.get_building_work_area(hut.id)
func inside(hut: RefCounted, position: Vector2) -> bool:
	var area := _area(hut)
	return area != null and area.contains(position)
func tree_count(hut: RefCounted) -> int:
	var area := _area(hut)
	return _world.get_ref().trees.filter(func(tree): return area != null and tree.state != TreeData.State.DEPLETED and area.contains(tree.position)).size()
func spot_valid(hut: RefCounted, position: Vector2, worker_id: String = "") -> bool:
	return _spot_valid(_area(hut),position,worker_id)
func _spot_valid(area: RefCounted, position: Vector2, worker_id: String = "") -> bool:
	var world: Node = _world.get_ref()
	var point := Coordinates.to_world(position)
	if area == null or not area.contains(position) or not world.navigation.is_world_walkable(point): return false
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
	var area := _area(hut)
	if area == null: return {}
	# First valid, reachable sample in the existing deterministic ring order.
	for ring in range(1,8):
		for index in range(16):
			var offset := Vector2.from_angle(index*TAU/16.0)*(ring*Balance.TREE_MINIMUM_SPACING)
			var position: Vector2 = area.center+offset*Coordinates.SIM_UNITS_PER_WORLD_UNIT
			if not spot_valid(hut,position): continue
			var temporary = TreeData.new(&"planting_candidate",position)
			temporary.physical_radius = Balance.SAPLING_PHYSICAL_RADIUS
			var access: Variant = world.tree_locations.resolve(temporary,from_position)
			if access is Vector2: return {"kind":&"PLANT","point":access,"spot":position}
	return {}
func claim(worker_id: String, hut: RefCounted, position: Vector2) -> bool:
	if claims.has(worker_id) or not spot_valid(hut,position): return false
	claims[worker_id] = position
	var area := _area(hut)
	_claim_areas[worker_id] = Area.new(area.id,area.center,area.radius)
	return true
func release(worker_id: String) -> void:
	claims.erase(worker_id)
	_claim_areas.erase(worker_id)
func complete(worker_id: String, _hut: RefCounted) -> bool:
	if not claims.has(worker_id): return false
	var position: Vector2 = claims[worker_id]
	# The boundary is immutable for accepted work; obstacles/trees/other claims stay live.
	var valid := _spot_valid(_claim_areas.get(worker_id),position,worker_id)
	release(worker_id)
	if valid: _world.get_ref().spawn_sapling(position)
	return valid
