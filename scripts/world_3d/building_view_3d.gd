extends StaticBody3D
## One visual for the existing BuildingInstance lifecycle; no resources/production logic.
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var building_data: RefCounted
var indicator: MeshInstance3D
var material: StandardMaterial3D
var caption: Label3D
func setup(data: RefCounted) -> void:
	building_data = data
	collision_layer = 4
	collision_mask = 0
	var height: float = Geometry.building_height(data)
	var box := BoxMesh.new()
	var size := Geometry.building_size(data)
	box.size = Vector3(size.x, height, size.y)
	material = StandardMaterial3D.new()
	box.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = box
	visual.position.y = height / 2.0
	add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height / 2.0
	add_child(collider)
	indicator = MeshInstance3D.new()
	var outline := BoxMesh.new()
	outline.size = box.size + Vector3(0.2, -height + 0.04, 0.2)
	var selected := StandardMaterial3D.new()
	selected.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selected.albedo_color = Color("69e5ff")
	outline.material = selected
	indicator.mesh = outline
	indicator.position.y = 0.02
	indicator.visible = false
	add_child(indicator)
	caption = Label3D.new()
	caption.pixel_size = 0.018
	caption.position.y = height + 0.36
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(caption)
	data.construction_changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var colors := [Color("bd976b"), Color("829ba7"), Color("9aaa70"), Color("c2aa91")]
	material.albedo_color = colors[building_data.type] if building_data.is_built() else Color("8b7357")
	caption.text = building_data.display_name + ("" if building_data.is_built() else " — строится")
func set_selected(value: bool) -> void: indicator.visible = value
