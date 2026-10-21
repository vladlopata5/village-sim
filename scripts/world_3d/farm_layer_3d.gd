extends Node3D
## Three shared batches, no per-cell Nodes, collision or navigation geometry.
const Fields=preload("res://scripts/farm_fields.gd")
const DIRT_COLOR:=Color("805f40")
const PLOWED_COLOR:=Color("4d3827")
const FURROW_COLOR:=Color("342317")
const CROP_COLORS: Array[Color]=[Color("9e8846"),Color("437f2c"),Color("52902e"),Color("769c38"),Color("a1aa47"),Color("d7b434"),Color("edc746")]
const CROP_HEIGHTS: Array[float]=[0.035,0.10,0.17,0.24,0.32,0.40,0.48]
var fields: RefCounted
var batches: Dictionary={}
var _dirty: Dictionary={}
func _material() -> StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.vertex_color_use_as_albedo=true;result.vertex_color_is_srgb=true
	return result
func _furrows() -> Mesh:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strip:=PlaneMesh.new();strip.size=Vector2(0.025,0.5)
	for x in [-0.14,0.0,0.14]:tool.append_from(strip,0,Transform3D(Basis.IDENTITY,Vector3(x,0,0)))
	return tool.commit()
func _wheat() -> Mesh:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk:=BoxMesh.new();stalk.size=Vector3(0.018,1,0.018)
	var ear:=BoxMesh.new();ear.size=Vector3(0.065,0.20,0.04)
	for point in [Vector3(-0.12,0,-0.1),Vector3(0.12,0,-0.1),Vector3(0,0,0.12)]:
		tool.append_from(stalk,0,Transform3D(Basis.IDENTITY,point+Vector3.UP*0.5))
		tool.append_from(ear,0,Transform3D(Basis.IDENTITY,point+Vector3.UP))
	return tool.commit()
func setup(model: RefCounted) -> void:
	fields=model
	var soil:=PlaneMesh.new();soil.size=Vector2.ONE*fields.geometry.CELL_SIZE
	for entry in [[&"soil",soil],[&"furrows",_furrows()],[&"crop",_wheat()]]:
		var view:=MultiMeshInstance3D.new();view.name=String(entry[0]);add_child(view)
		view.multimesh=MultiMesh.new();view.multimesh.transform_format=MultiMesh.TRANSFORM_3D;view.multimesh.use_colors=true
		view.material_override=_material();view.multimesh.mesh=entry[1]
		view.multimesh.instance_count=fields.geometry.grid_size().x*fields.geometry.grid_size().y;view.multimesh.visible_instance_count=0
		batches[entry[0]]={"view":view,"cells":[],"slots":{}}
	fields.changed.connect(_queue)
	_queue(fields.dirt_cells());flush()
func _queue(cells: Array) -> void:
	var empty:=_dirty.is_empty()
	for cell in cells:_dirty[cell]=true
	if empty and not _dirty.is_empty():flush.call_deferred()
func _write(kind: StringName, cell: Vector2i, slot: int) -> void:
	var point: Vector3=fields.geometry.cell_to_world(cell)
	var crop_basis:=Basis.IDENTITY
	var color:=DIRT_COLOR
	if kind==&"soil":
		point.y=0.007;color=PLOWED_COLOR if fields.state(cell)!=Fields.State.BARE else DIRT_COLOR
	elif kind==&"furrows":point.y=0.009;color=FURROW_COLOR
	else:
		var stage:=mini(fields.maturity(cell),6)
		point.y=0.012;crop_basis=crop_basis.scaled(Vector3(1,CROP_HEIGHTS[stage],1));color=CROP_COLORS[stage]
	var mm: MultiMesh=batches[kind].view.multimesh
	mm.set_instance_transform(slot,Transform3D(crop_basis,point));mm.set_instance_color(slot,color)
func _set_cell(kind: StringName, cell: Vector2i, visible_cell: bool) -> void:
	var batch: Dictionary=batches[kind]
	if visible_cell:
		if not batch.slots.has(cell):batch.slots[cell]=batch.cells.size();batch.cells.append(cell)
		_write(kind,cell,batch.slots[cell])
	elif batch.slots.has(cell):
		var slot: int=batch.slots[cell];var last: Vector2i=batch.cells.back()
		batch.cells.pop_back();batch.slots.erase(cell)
		if slot<batch.cells.size():batch.cells[slot]=last;batch.slots[last]=slot;_write(kind,last,slot)
	batch.view.multimesh.visible_instance_count=batch.cells.size()
func flush() -> void:
	for cell in _dirty:
		_set_cell(&"soil",cell,fields.terrain(cell)==Fields.Terrain.DIRT)
		_set_cell(&"furrows",cell,fields.state(cell)!=Fields.State.BARE)
		_set_cell(&"crop",cell,fields.state(cell)==Fields.State.SOWN)
	_dirty.clear()
