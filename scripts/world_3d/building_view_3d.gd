extends StaticBody3D
## One visual for the existing BuildingInstance lifecycle; no resources/production logic.
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var building_data: RefCounted
var indicator: MeshInstance3D
var material: StandardMaterial3D
var work_area: MeshInstance3D
var layout: Node3D
var inside_count := 0
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
	if data.definition.work_radius > 0:
		_create_work_area(data.definition.work_radius)
	layout = preload("res://scripts/world_3d/building_layouts_3d.gd").create(data.definition)
	layout.rotation.y = data.quarter_turns*PI/2.0
	add_child(layout)
	_create_layout_visuals()
	data.construction_changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var colors := [Color("bd976b"), Color("829ba7"), Color("9aaa70"), Color("c2aa91"),Color("88735d"),Color("a28559"),Color("547ea8")]
	material.albedo_color = colors[building_data.type] if building_data.is_built() else Color("8b7357")
	set_inside_count(inside_count)
	caption.text = building_data.display_name + ("" if building_data.is_built() else " — строится")
func set_selected(value: bool) -> void: indicator.visible = value

func _create_work_area(radius: float) -> void:
	work_area = MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var color := StandardMaterial3D.new()
	color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	color.albedo_color = Color("80c994")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,color)
	for index in range(64):
		for angle in [index*TAU/64.0,(index+1)*TAU/64.0]:
			mesh.surface_add_vertex(Vector3(cos(angle)*radius,0.04,sin(angle)*radius))
	mesh.surface_end()
	work_area.mesh = mesh
	work_area.visible = false
	add_child(work_area)
func set_work_area_debug(enabled: bool) -> void:
	if work_area != null: work_area.visible = enabled

func set_inside_count(count: int) -> void:
	inside_count = count
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if count>0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	var color := material.albedo_color
	color.a = 0.22 if count>0 else 1.0
	material.albedo_color = color
func _create_layout_visuals() -> void:
	var layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
	var colors := [Color("7fe889"),Color("ffe178"),Color("ec89e1"),Color("82b7ff"),Color("ff9f5c")]
	for marker in layouts.markers(layout,preload("res://scripts/world_3d/building_slot_3d.gd")):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.24,0.12,0.24)
		var tint := StandardMaterial3D.new()
		tint.albedo_color = colors[marker.purpose]
		mesh.material = tint
		var cube := MeshInstance3D.new()
		cube.mesh = mesh
		cube.position.y = 0.06
		marker.add_child(cube)
	for marker in layouts.markers(layout,preload("res://scripts/world_3d/building_entrance_3d.gd")):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(marker.zone_size.x,0.08,marker.zone_size.y)
		var tint := StandardMaterial3D.new()
		tint.albedo_color = Color("c8c4aa")
		mesh.material = tint
		var platform := MeshInstance3D.new()
		platform.mesh = mesh
		platform.position.y = 0.04
		marker.add_child(platform)
