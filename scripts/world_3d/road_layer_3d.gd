extends MultiMeshInstance3D
## Event-driven batch presentation only; RoadGrid owns state.
var roads: RefCounted
func setup(model: RefCounted) -> void:
	roads=model
	var tile := PlaneMesh.new()
	tile.size=Vector2.ONE*roads.CELL_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("9b7750")
	tile.material=material
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=tile
	roads.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var cells: Array[Vector2i]=roads.cells()
	multimesh.instance_count=cells.size()
	for index in range(cells.size()):
		var point: Vector3=roads.geometry.cell_to_world(cells[index])+Vector3.UP*0.015
		multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,point))
