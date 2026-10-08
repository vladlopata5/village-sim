extends RefCounted
## Migration bridge: one derived, deterministic access point; not a slot/entrance system.
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
const ACCESS_CLEARANCE: float = 18.0
var navigation_map: RID
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
	if _access.has(building.id): return _access[building.id]
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) == 0: return null
	var bounds: Rect2 = building.footprint()
	var center: Vector2 = building.position
	# Buildings currently have no orientation: fixed +Z, +X, -Z, -X side order.
	var candidates := [Vector2(center.x, bounds.end.y + ACCESS_CLEARANCE), Vector2(bounds.end.x + ACCESS_CLEARANCE, center.y), Vector2(center.x, bounds.position.y - ACCESS_CLEARANCE), Vector2(bounds.position.x - ACCESS_CLEARANCE, center.y)]
	for point in candidates:
		var world := Coordinates.to_world(point)
		if not NavigationServer3D.map_get_closest_point_owner(navigation_map, world).is_valid(): continue
		var projected := NavigationServer3D.map_get_closest_point(navigation_map, world)
		if projected.distance_to(world) <= 3.0:
			_access[building.id] = Coordinates.to_sim(projected)
			return _access[building.id]
	_access[building.id] = null
	return null
