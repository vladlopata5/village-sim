extends MultiMeshInstance3D
## Presentation adapter keyed by data visual_id, with no construction decisions.
var visual_id: StringName = &""
func present(key: StringName, size: Vector2, height: float) -> void:
	if key==visual_id:return
	visual_id=key
	var boxes: Array=[]
	boxes.append([Vector3(0,0.08,0),Vector3(size.x,0.16,size.y)])
	if key in [&"base",&"frame",&"shell"]:
		boxes.append([Vector3(0,0.24,0),Vector3(size.x*.94,.18,size.y*.94)])
	if key in [&"frame",&"shell"]:
		for x in [-1,1]:
			for z in [-1,1]:boxes.append([Vector3(x*size.x*.42,height*.5,z*size.y*.42),Vector3(.18,height,.18)])
		boxes.append([Vector3(0,height,0),Vector3(size.x*.9,.18,size.y*.9)])
	if key==&"shell":boxes.append([Vector3(0,height*.45,0),Vector3(size.x*.85,height*.8,size.y*.85)])
	var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.mesh=BoxMesh.new();batch.mesh.size=Vector3.ONE;batch.instance_count=boxes.size()
	for i in boxes.size():batch.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(boxes[i][1]),boxes[i][0]))
	multimesh=batch
	var tint:=StandardMaterial3D.new();tint.albedo_color=Color("8b7357") if key==&"frame" else Color("978b78")
	material_override=tint
