extends RefCounted
## One finite cargo visual, independent from source and numerical stock.
static func create() -> Node3D:
	var result:=Node3D.new()
	var body:=MeshInstance3D.new()
	var cylinder:=CylinderMesh.new()
	cylinder.top_radius=0.14;cylinder.bottom_radius=0.10;cylinder.height=0.22;cylinder.radial_segments=8
	body.mesh=cylinder;body.position.y=0.11
	var material:=StandardMaterial3D.new();material.albedo_color=Color("967955")
	body.material_override=material;result.add_child(body)
	var water:=MeshInstance3D.new()
	var surface:=CylinderMesh.new();surface.top_radius=0.12;surface.bottom_radius=0.12;surface.height=0.01;surface.radial_segments=8
	water.mesh=surface;water.position.y=0.225
	var blue:=StandardMaterial3D.new();blue.albedo_color=Color("328bb1")
	water.material_override=blue;result.add_child(water)
	var handle:=MeshInstance3D.new()
	var ring:=TorusMesh.new();ring.inner_radius=0.14;ring.outer_radius=0.16;ring.rings=12;ring.ring_segments=6
	handle.mesh=ring;handle.rotation.x=PI/2;handle.position.y=0.22;handle.material_override=material
	result.add_child(handle);return result
