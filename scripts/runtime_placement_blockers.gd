extends RefCounted
## Live world-position providers and circular X/Z bounds; no grid/navigation ownership.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var _circles: Dictionary = {}
var _static_cells: Dictionary={}
var _static_geometry: RefCounted
var _static_dirty:=true
func register_circle(id: StringName, position_provider: Callable, radius: float, blocks_roads: bool = false, land_static: bool = false) -> bool:
	# Registration opts into blocking placement. One stable ID per world entity.
	if id.is_empty() or _circles.has(id) or not position_provider.is_valid() or not is_finite(radius) or radius <= 0.0: return false
	if land_static:_static_dirty=true
	_circles[id] = {"position":position_provider, "radius":radius,"blocks_roads":blocks_roads,"land_static":land_static}
	return true
func unregister(id: StringName) -> void:
	if _circles.has(id) and _circles[id].land_static:_static_dirty=true
	_circles.erase(id)
func _intersects(center: Vector2, radius: float, footprint: Rect2) -> bool:
	return center.distance_squared_to(center.clamp(footprint.position,footprint.end))<=radius*radius
# Explicit land_static providers (trees/rocks) unregister/re-register on geometry changes.
# blocks_roads retains its independent live-provider contract. No scene/physics scan.
func static_cell_occupied(cell: Vector2i, geometry: RefCounted) -> bool:
	if _static_dirty or _static_geometry!=geometry:
		_static_geometry=geometry;_static_cells.clear();_static_dirty=false
		for circle in _circles.values():
			if not circle.land_static or not circle.position.is_valid():continue
			var point: Variant=circle.position.call()
			if not point is Vector3 or not point.is_finite():continue
			var center:=Coordinates.world_plane(point)
			var radius: float=circle.radius
			var low: Vector2i=geometry.world_to_cell(Coordinates.from_plane(center-Vector2.ONE*radius))-Vector2i.ONE
			var high: Vector2i=geometry.world_to_cell(Coordinates.from_plane(center+Vector2.ONE*radius))+Vector2i.ONE
			for y in range(maxi(0,low.y),mini(geometry.grid_size().y-1,high.y)+1):
				for x in range(maxi(0,low.x),mini(geometry.grid_size().x-1,high.x)+1):
					var candidate:=Vector2i(x,y)
					var box:=Rect2(Coordinates.world_plane(geometry.cell_to_world(candidate))-Vector2.ONE*geometry.CELL_SIZE/2.0,Vector2.ONE*geometry.CELL_SIZE)
					if _intersects(center,radius,box):_static_cells[candidate]=true
	return _static_cells.has(cell)
func has_blocker(id: StringName) -> bool: return _circles.has(id)
func first_overlap(footprint: Rect2, roads_only: bool = false) -> StringName:
	if not footprint.has_area(): return &""
	var ids: Array = _circles.keys()
	ids.sort_custom(func(a, b): return String(a) < String(b)) # Explicit lexical order for StringName IDs.
	for id in ids:
		var circle: Dictionary = _circles[id]
		if roads_only and not circle.blocks_roads: continue
		var provider: Callable = circle.position
		if not provider.is_valid():
			unregister(id) # Safe stale-provider cleanup, even without a lifecycle notification.
			continue
		var point: Variant = provider.call()
		if not point is Vector3 or not point.is_finite(): continue
		var center := Coordinates.world_plane(point)
		if _intersects(center,circle.radius,footprint): return id
	return &""
