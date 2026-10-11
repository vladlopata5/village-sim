extends Node3D
## Presentation-only preview. Domain registration happens only at confirmation.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Area = preload("res://scripts/work_area.gd")
var resident_id := ""
var preview: Area
var locked := false
var outline := MeshInstance3D.new()
func _ready() -> void:
	add_child(outline)
	hide()
func start(id: String, radius: float) -> void:
	resident_id = id
	preview = Area.new(&"preview",Vector2.ZERO,Coordinates.length_to_sim(radius))
	locked = false
	show()
func active() -> bool: return not resident_id.is_empty()
func cancel() -> void:
	resident_id = ""
	preview = null
	locked = false
	hide()
func update_world(point: Vector3) -> void:
	if not active() or locked: return
	var center := Coordinates.to_sim(point)
	if outline.mesh != null and preview.center == center: return
	preview.update(center,preview.radius)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var radius := Coordinates.length_to_world(preview.radius)
	for i in range(65):
		var angle := TAU * i / 64.0
		mesh.surface_add_vertex(Vector3(cos(angle)*radius,0.08,sin(angle)*radius))
	mesh.surface_end()
	outline.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3,0.9,1)
	outline.material_override = material
	position = Coordinates.to_world(preview.center)
