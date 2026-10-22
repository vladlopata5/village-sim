extends RefCounted
static func create() -> Node3D:
	var root:=Node3D.new()
	var stone:=StandardMaterial3D.new();stone.albedo_color=Color("879497")
	for height in [0.2,0.45,0.7]:
		var ring:=MeshInstance3D.new();var mesh:=TorusMesh.new()
		mesh.inner_radius=0.45;mesh.outer_radius=0.72;mesh.rings=12;mesh.ring_segments=6
		ring.mesh=mesh;ring.position.y=height;ring.material_override=stone;root.add_child(ring)
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color("886645")
	for x in [-0.85,0.85]:
		var post:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.14,1.5,0.14)
		post.mesh=box;post.position=Vector3(x,0.95,0);post.material_override=wood;root.add_child(post)
	var roof:=MeshInstance3D.new();var prism:=PrismMesh.new();prism.size=Vector3(2.1,0.5,1.5)
	roof.mesh=prism;roof.position.y=1.8;roof.material_override=wood;root.add_child(roof)
	return root
