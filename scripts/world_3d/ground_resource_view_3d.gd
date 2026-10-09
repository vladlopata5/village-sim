extends Node3D
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Resources = preload("res://scripts/resource_type.gd")
var ground_resource: RefCounted
func setup(drop: RefCounted) -> void:
	ground_resource = drop
	position = Coordinates.to_world(drop.world_position)
	var visual := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if drop.resource_type == Resources.Type.LOG:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.12
		cylinder.bottom_radius = 0.12
		cylinder.height = 0.65
		visual.mesh = cylinder
		visual.rotation.z = PI / 2.0
		visual.position.y = 0.12
		material.albedo_color = Color(0.42,0.24,0.1)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.25,0.2,0.25)
		visual.mesh = box
		visual.position.y = 0.1
		material.albedo_color = Color(0.8,0.65,0.2)
	visual.material_override = material
	add_child(visual)
