extends Node3D
## Read-only land tint and small stable visual instances, independent of harvesting.
var land: RefCounted
var patches := MultiMeshInstance3D.new()
var _piles: Dictionary={}
var _stem: CylinderMesh
var _cap: SphereMesh
const OFFSETS := [Vector3(-0.11,0,-0.11),Vector3(0.11,0,0.11),Vector3(-0.11,0,0.11),Vector3(0.11,0,-0.11)]
func setup(model: RefCounted) -> void:
	land=model;add_child(patches)
	var tile:=PlaneMesh.new();tile.size=Vector2.ONE*land.geometry.CELL_SIZE
	var tint:=StandardMaterial3D.new();tint.albedo_color=Color(0.225,0.37,0.215)
	tile.material=tint
	patches.multimesh=MultiMesh.new();patches.multimesh.transform_format=MultiMesh.TRANSFORM_3D;patches.multimesh.mesh=tile
	var cells: Array=land.cells();patches.multimesh.instance_count=cells.size()
	for index in cells.size():patches.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,land.geometry.cell_to_world(cells[index])+Vector3.UP*0.004))
	_stem=CylinderMesh.new();_stem.top_radius=0.025;_stem.bottom_radius=0.03;_stem.height=0.10;_stem.radial_segments=8
	var cream:=StandardMaterial3D.new();cream.albedo_color=Color("e5d8b8");_stem.material=cream
	_cap=SphereMesh.new();_cap.radius=0.09;_cap.height=0.085;_cap.radial_segments=12;_cap.rings=6
	var brown:=StandardMaterial3D.new();brown.albedo_color=Color("b17b47");_cap.material=brown
	land.mushrooms_changed.connect(_update)
	for cell in land.mushroom_cells():_update(cell,land.amount(cell))
func _instances(mesh: Mesh, height: float) -> MultiMeshInstance3D:
	var view:=MultiMeshInstance3D.new();view.multimesh=MultiMesh.new()
	view.multimesh.transform_format=MultiMesh.TRANSFORM_3D;view.multimesh.mesh=mesh
	view.multimesh.instance_count=OFFSETS.size()
	for index in OFFSETS.size():
		var scale_value:=1.0-float(index)*0.04
		view.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_value),OFFSETS[index]+Vector3.UP*height*scale_value))
	return view
func _update(cell: Vector2i, _amount: int) -> void:
	var count: int=land.amount(cell) # Reentrant quantity notifications cannot restore stale visuals.
	if count==0:
		if _piles.has(cell):
			var old: Node3D=_piles[cell];_piles.erase(cell);old.hide();old.queue_free()
		return
	if not _piles.has(cell):
		var pile:=Node3D.new();add_child(pile);pile.position=land.geometry.cell_to_world(cell)
		pile.add_child(_instances(_stem,0.05));pile.add_child(_instances(_cap,0.115))
		_piles[cell]=pile
	for mesh_view in _piles[cell].get_children():mesh_view.multimesh.visible_instance_count=count
func displayed_amount(cell: Vector2i) -> int:
	return _piles[cell].get_child(0).multimesh.visible_instance_count if _piles.has(cell) else 0
