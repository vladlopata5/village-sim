extends StaticBody3D
## Presentation only. Its parent world executor owns position; domain owns gameplay data.
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var resident_data: RefCounted
var indicator: MeshInstance3D
func setup(data: RefCounted) -> void:
	resident_data = data
	collision_layer = 2
	collision_mask = 0
	var capsule := CapsuleMesh.new()
	capsule.radius = Geometry.RESIDENT_RADIUS
	capsule.height = Geometry.RESIDENT_HEIGHT
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f2c66d")
	capsule.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = capsule
	visual.position.y = Geometry.RESIDENT_HEIGHT / 2.0
	add_child(visual)
	var shape := CapsuleShape3D.new()
	shape.radius = Geometry.RESIDENT_RADIUS
	shape.height = Geometry.RESIDENT_HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = Geometry.RESIDENT_HEIGHT / 2.0
	add_child(collider)
	indicator = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.64
	ring.outer_radius = 0.76
	var selected := StandardMaterial3D.new()
	selected.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selected.albedo_color = Color("69e5ff")
	ring.material = selected
	indicator.mesh = ring
	indicator.position.y = 0.04
	indicator.visible = false
	add_child(indicator)
	var label := Label3D.new()
	label.text = data.resident_name
	label.pixel_size = 0.018
	label.position.y = 1.96
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
func set_selected(value: bool) -> void: indicator.visible = value
