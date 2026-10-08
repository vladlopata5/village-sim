extends RefCounted
## Migration bridge: one derived, deterministic access point; not a slot/entrance system.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var navigation: RefCounted
var _locations: Dictionary = {}
var _views: Dictionary = {}
var _access: Dictionary = {}
func register(location: RefCounted, view: Node) -> void:
	_locations[location.id] = location
	_views[location.id] = view
	_access.erase(location.id)
func get_location(id: StringName) -> RefCounted: return _locations.get(id)
func get_view(id: StringName) -> Node:
	var view = _views.get(id)
	return view if is_instance_valid(view) else null
func get_position(id: StringName) -> Variant:
	var view = get_view(id)
	return resolve_action_position(view.building_data) if view != null else null
func resolve_action_position(building: RefCounted) -> Variant:
	if navigation == null: return null
	var cached: Dictionary = _access.get(building.id,{})
	if cached.get("revision",-1) == navigation.revision: return cached.point
	var bounds := Geometry.footprint(building)
	var center := bounds.get_center()
	var distance: float = navigation.clearance + navigation.CELL_SIZE/2.0
	var origins := [Vector2(center.x,bounds.end.y),Vector2(bounds.end.x,center.y),Vector2(center.x,bounds.position.y),Vector2(bounds.position.x,center.y)]
	var directions := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
	# One point: fixed +Z,+X,-Z,-X order, up to two extra cells outward per side.
	for side in range(origins.size()):
		for offset in range(3):
			var candidate: Vector2 = origins[side]+directions[side]*(distance+offset*navigation.CELL_SIZE)
			var cell: Vector2i = navigation.world_to_cell(Coordinates.from_plane(candidate))
			var point: Vector3 = navigation.cell_to_world(cell)
			if navigation.is_world_walkable(point):
				var sim := Coordinates.to_sim(point)
				_access[building.id] = {"revision":navigation.revision,"point":sim}
				return sim
	_access[building.id] = {"revision":navigation.revision,"point":null}
	return null
