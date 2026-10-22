extends StaticBody3D
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var rock_data: RefCounted
func setup(data: RefCounted) -> void:
	rock_data = data
	position = Coordinates.to_world(data.position)
	collision_layer = 8
	collision_mask = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("9f603b") if data.resource_type==preload("res://scripts/resource_type.gd").Type.CLAY else Color(0.42,0.44,0.46)
	material.roughness = 1.0
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = data.physical_radius
	mesh.height = data.physical_radius*1.35
	mesh.radial_segments = 7
	mesh.rings = 4
	visual.mesh = mesh
	visual.position.y = mesh.height*0.5
	visual.rotation.y = float(String(data.id).hash()%360)*PI/180.0
	visual.material_override = material
	add_child(visual)
	if data.resource_type==preload("res://scripts/resource_type.gd").Type.CLAY:
		visual.scale.y=0.55
		visual.position.y=mesh.height*0.275
		for offset in [Vector3(-.3,.3,.1),Vector3(.3,.25,-.2)]:
			var lump:=MeshInstance3D.new()
			lump.mesh=mesh;lump.material_override=material
			lump.scale=Vector3(.45,.45,.45);lump.position=offset
			add_child(lump)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = data.physical_radius
	shape.height = mesh.height
	collider.shape = shape
	collider.position.y = mesh.height*0.5
	add_child(collider)
