extends RefCounted
## Temporary presentation only; no actions, collision or simulation data.
const Types=preload("res://scripts/building_type.gd").Type
static func box(parent: Node3D,size: Vector3,point: Vector3,color: String) -> MeshInstance3D:
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=point
	var material:=StandardMaterial3D.new();material.albedo_color=Color(color);node.material_override=material
	parent.add_child(node);return node
static func create(type: int) -> Node3D:
	var root:=Node3D.new()
	if type==Types.GAZEBO:
		box(root,Vector3(3,.08,3),Vector3(0,.04,0),"a7916d")
		for x in [-1.28,1.28]:
			for z in [-1.28,1.28]:box(root,Vector3(.12,2.25,.12),Vector3(x,1.125,z),"796146")
		var roof:=box(root,Vector3(3,.18,3),Vector3(0,2.4,0),"71897a")
		# A light roof keeps four visitors visible from the current overhead camera.
		roof.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		roof.material_override.albedo_color.a=.3
	else:
		box(root,Vector3(.85,.12,.85),Vector3(0,.06,0),"604b36")
		for x in [-.45,.45]:box(root,Vector3(.1,.22,1),Vector3(x,.11,0),"b29b78")
		for z in [-.45,.45]:box(root,Vector3(.8,.22,.1),Vector3(0,.11,z),"b29b78")
		for index in 5:
			var x: float=(index%3-1)*.25;var z: float=(floori(float(index)/3)-.5)*.3
			box(root,Vector3(.025,.18,.025),Vector3(x,.21,z),"54874e")
			box(root,Vector3(.14,.07,.14),Vector3(x,.32,z),["d87ba0","e9d277","9c83cf"][index%3])
	return root
