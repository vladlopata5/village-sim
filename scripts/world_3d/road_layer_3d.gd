extends MultiMeshInstance3D
## One preallocated batch; only changed cells touch the instance buffer.
const DIRT_COLOR := Color("9b7750")
var roads: RefCounted
var base_color: Callable
var _slots: Dictionary = {}
var _cells: Array[Vector2i] = []
var _dirty: Dictionary = {}
func setup(model: RefCounted) -> void:
	roads = model
	var tile := PlaneMesh.new()
	tile.size = Vector2.ONE * roads.CELL_SIZE
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	tile.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = tile
	multimesh.instance_count = roads.geometry.grid_size().x * roads.geometry.grid_size().y
	multimesh.visible_instance_count = 0
	roads.changed.connect(_refresh) # Compatibility: manual strokes may refresh their set.
	roads.levels_changed.connect(_queue_cells)
	_refresh()
func color_for(cell: Vector2i) -> Color:
	if roads.contains(cell): return DIRT_COLOR
	var ground: Color = base_color.call(cell) if base_color.is_valid() else Color(0.28,0.43,0.27)
	return ground.lerp(DIRT_COLOR,float(roads.trample_level(cell))/15.0)
func refresh_base_colors() -> void:
	# Reuse visible instances, preserve every level/slot and the independent dirt color.
	for cell in _cells:
		multimesh.set_instance_color(_slots[cell],color_for(cell))
func _refresh() -> void:
	for cell in _cells: _dirty[cell] = true
	for cell in roads.cells(): _dirty[cell] = true
	for cell in roads.trampled_cells(): _dirty[cell] = true
	flush_updates()
func _queue_cells(cells: Array[Vector2i]) -> void:
	var was_empty := _dirty.is_empty()
	for cell in cells: _dirty[cell] = true
	if was_empty: flush_updates.call_deferred()
func flush_updates() -> void:
	for cell in _dirty:
		if roads.contains(cell) or roads.trample_level(cell) > 0:
			if not _slots.has(cell):
				_slots[cell] = _cells.size()
				_cells.append(cell)
				_write_transform(_slots[cell],cell)
			multimesh.set_instance_color(_slots[cell],color_for(cell))
		elif _slots.has(cell):
			var slot: int = _slots[cell]
			var last: Vector2i = _cells.back()
			_cells.pop_back()
			_slots.erase(cell)
			if slot < _cells.size():
				_cells[slot] = last
				_slots[last] = slot
				_write_transform(slot,last)
				multimesh.set_instance_color(slot,color_for(last))
	_dirty.clear()
	multimesh.visible_instance_count = _cells.size()
func _write_transform(slot: int, cell: Vector2i) -> void:
	var point: Vector3 = roads.geometry.cell_to_world(cell)+Vector3.UP*0.015
	multimesh.set_instance_transform(slot,Transform3D(Basis.IDENTITY,point))
