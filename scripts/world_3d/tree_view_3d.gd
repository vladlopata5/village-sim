extends Node3D
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var tree_data: RefCounted
func setup(tree: RefCounted) -> void:
	tree_data = tree
	position = Coordinates.to_world(tree.position)
	var trunk := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = tree.physical_radius * 0.6
	cylinder.bottom_radius = tree.physical_radius
	cylinder.height = 2.0
	trunk.mesh = cylinder
	trunk.position.y = 1.0
	trunk.material_override = material(Color(0.35,0.21,0.1))
	add_child(trunk)
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	crown.mesh = sphere
	crown.position.y = 2.25
	crown.material_override = material(Color(0.16,0.38,0.12))
	add_child(crown)
	tree.changed.connect(_refresh_growth)
	_refresh_growth()
func get_world_position() -> Vector3: return global_position
func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	return result

func _refresh_growth() -> void:
	scale = Vector3.ONE * (0.3 if tree_data.state == tree_data.State.SAPLING else 1.0)
