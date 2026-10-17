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
func active() -> bool: return preview != null
func cancel() -> void:
	resident_id = ""
	preview = null
	locked = false
	hide()
func update_world(point: Vector3) -> void:
	if not active() or locked: return
	var center := Coordinates.to_sim(point)
	if preview.center == center and position == Coordinates.to_world(center) and outline.mesh != null: return
	preview.update(center,preview.radius)
	var radius := Coordinates.length_to_world(preview.radius)
	if outline.mesh == null or not is_equal_approx(outline.mesh.get_aabb().size.x,2*radius):
		outline.mesh = preload("res://scripts/world_3d/building_view_3d.gd").make_work_area_mesh(radius)
	outline.position.y = 0.04
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3,0.9,1)
	outline.material_override = material
	position = Coordinates.to_world(preview.center)
