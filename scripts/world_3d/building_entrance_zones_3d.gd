extends RefCounted
## Placement-only spatial index. Entrance zones never occupy navigation/road cells.
const Grid = preload("res://scripts/build_grid.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var _records: Dictionary = {}
var _index: Dictionary = {}
func _cells(area: Rect2) -> Array:
	var result: Array = []
	var low := (area.position-Grid.WORLD_BOUNDS.position)/Grid.CELL_SIZE
	var high := (area.end-Grid.WORLD_BOUNDS.position)/Grid.CELL_SIZE
	for z in range(floori(low.y),ceili(high.y)):
		for x in range(floori(low.x),ceili(high.x)): result.append(Vector2i(x,z))
	return result
func register(building: RefCounted) -> void:
	var footprint := Geometry.footprint(building)
	var zone := Layouts.entrance_zone(building.definition,Coordinates.to_world(building.position),building.quarter_turns)
	_records[building.id]={"footprint":footprint,"zone":zone}
	for cell in _cells(footprint)+_cells(zone):
		if not _index.has(cell): _index[cell]={}
		_index[cell][building.id]=true
func release(id: StringName) -> void:
	var record: Dictionary = _records.get(id,{})
	if record.is_empty(): return
	_records.erase(id)
	for cell in _cells(record.footprint)+_cells(record.zone):
		if _index.has(cell):
			_index[cell].erase(id)
			if _index[cell].is_empty(): _index.erase(cell)
func validation_reason(footprint: Rect2, zone: Rect2) -> String:
	if not Grid.WORLD_BOUNDS.encloses(zone): return "Вход за пределами карты"
	var nearby: Dictionary = {}
	for cell in _cells(footprint)+_cells(zone): nearby.merge(_index.get(cell,{}))
	for id in nearby:
		var record: Dictionary = _records[id]
		if footprint.intersects(record.zone) or zone.intersects(record.footprint) or zone.intersects(record.zone): return "Перекрыт вход здания"
	return ""
