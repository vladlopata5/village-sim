extends StaticBody3D
## Presentation only. Its parent world executor owns position; domain owns gameplay data.
var resident_data: RefCounted
var indicator: MeshInstance3D
func setup(data: RefCounted) -> void:
	resident_data = data
	collision_layer = 2
	collision_mask = 0
	var capsule := CapsuleMesh.new()
	capsule.radius = 10.0
	capsule.height = 36.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("f2c66d")
	capsule.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = capsule
	visual.position.y = 18.0
	add_child(visual)
	var shape := CapsuleShape3D.new()
	shape.radius = 10.0
	shape.height = 36.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 18.0
	add_child(collider)
	indicator = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 16.0
	ring.outer_radius = 19.0
	var selected := StandardMaterial3D.new()
	selected.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selected.albedo_color = Color("69e5ff")
	ring.material = selected
	indicator.mesh = ring
	indicator.position.y = 1.0
	indicator.visible = false
	add_child(indicator)
	var label := Label3D.new()
	label.text = data.resident_name
	label.pixel_size = 0.45
	label.position.y = 49.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
func set_selected(value: bool) -> void: indicator.visible = value
