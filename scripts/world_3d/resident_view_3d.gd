extends StaticBody3D
## Presentation only. Its parent world executor owns position; domain owns gameplay data.
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var resident_data: RefCounted
var water_cargo: Node3D
var indicator: MeshInstance3D
var model: Node3D
var name_label: Label3D
func setup(data: RefCounted) -> void:
	resident_data = data
	water_cargo=preload("res://scripts/world_3d/water_bucket_visual_3d.gd").create()
	water_cargo.position=Vector3(0.52,0.7,0)
	add_child(water_cargo)
	data.inventory.changed.connect(_refresh_water_cargo)
	_refresh_water_cargo()
	collision_layer = 2
	collision_mask = 0
	model=preload("res://scripts/world_3d/resident_model_3d.gd").new()
	model.name="ResidentModel"
	add_child(model)
	model.setup()
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
	name_label=Label3D.new()
	name_label.text = data.resident_name
	name_label.pixel_size = 0.018
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(name_label)
	model.dimensions_changed.connect(_position_name)
	_position_name()
func set_selected(value: bool) -> void: indicator.visible = value

func _refresh_water_cargo() -> void:
	water_cargo.visible=resident_data.inventory.amount==1 and resident_data.inventory.resource_type==preload("res://scripts/resource_type.gd").Type.WATER

func _position_name() -> void:
	name_label.position.y=maxf(1.96,model.height()+0.52)
func face_movement(direction: Vector3) -> void: model.face_movement(direction)
