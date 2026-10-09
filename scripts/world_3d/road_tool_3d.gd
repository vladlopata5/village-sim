extends RefCounted
## Paint interaction and validation; world road state has no player ownership.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var roads: RefCounted
var build_grid: RefCounted
var runtime_blockers: RefCounted
var active := false
var _previous: Variant = null
var _erasing := false
func select() -> void:
	active=true
	end_stroke()
func cancel() -> void:
	active=false
	end_stroke()
func end_stroke() -> void: _previous=null
func can_paint(cell: Vector2i) -> bool:
	if not roads.in_bounds(cell) or not build_grid.occupant(cell).is_empty(): return false
	var center: Vector3 = roads.geometry.cell_to_world(cell)
	var footprint := Rect2(Coordinates.world_plane(center)-Vector2.ONE*roads.CELL_SIZE/2.0,Vector2.ONE*roads.CELL_SIZE)
	return runtime_blockers.first_overlap(footprint,true).is_empty()
# Supercover grid line, including both sides of diagonal corners. The 2x2 brush
# is anchored at the cursor cell, extending toward positive X/Z. No A->B routing.
func stroke_cells(first: Vector2i, last: Vector2i) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = [first]
	var point := first
	var difference := last-first
	var nx := absi(difference.x)
	var ny := absi(difference.y)
	var step := Vector2i(int(signi(difference.x)),int(signi(difference.y)))
	var ix := 0
	var iy := 0
	while ix<nx or iy<ny:
		var decision := (1+2*ix)*ny-(1+2*iy)*nx
		if decision==0:
			anchors.append(point+Vector2i(step.x,0))
			anchors.append(point+Vector2i(0,step.y))
			point+=step
			ix+=1
			iy+=1
		elif decision<0:
			point.x+=step.x
			ix+=1
		else:
			point.y+=step.y
			iy+=1
		anchors.append(point)
	var unique: Dictionary={}
	for anchor in anchors:
		for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]: unique[anchor+offset]=true
	var result: Array[Vector2i]=[]
	result.assign(unique.keys())
	return result
func paint(point: Vector3, erase: bool = false) -> bool:
	if not active or not point.is_finite():
		end_stroke()
		return false
	var cell: Vector2i = roads.geometry.world_to_cell(point)
	if not roads.in_bounds(cell):
		end_stroke()
		return false
	if erase!=_erasing: end_stroke()
	_erasing=erase
	var selected := stroke_cells(cell if _previous==null else _previous,cell)
	_previous=cell
	var allowed: Array[Vector2i]=[]
	for candidate in selected:
		if erase or can_paint(candidate): allowed.append(candidate)
	return roads.edit(allowed,erase)
