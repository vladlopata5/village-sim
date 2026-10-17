extends Node3D
## Presentation-only preview. Domain registration happens only at confirmation.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Area = preload("res://scripts/work_area.gd")
const Balance = preload("res://scripts/balance_config.gd")
var resident_id := ""
var edited_area: Area
var edited_revision := -1
var preview: Area
var locked := false
var outline := MeshInstance3D.new()
func _ready() -> void:
	add_child(outline)
	hide()
func start(id: String, radius: float) -> void:
	edited_area = null
	edited_revision = -1
	resident_id = id
	preview = Area.new(&"preview",Vector2.ZERO,Coordinates.length_to_sim(radius))
	locked = false
	show()
func start_edit(area: Area) -> void:
	start("",Coordinates.length_to_world(area.radius))
	edited_area = area
	edited_revision = area.revision
	preview.update(area.center,area.radius)
	locked = true # Radius-only edit keeps the current center; a map click can replace it.
	_draw()
func set_radius_world(value: float) -> bool:
	if not active() or not is_finite(value) or value <= 0 or value > Balance.MAX_WORK_AREA_RADIUS: return false
	if not preview.update(preview.center,Coordinates.length_to_sim(value)): return false
	_draw()
	return true
func active() -> bool: return preview != null
func cancel() -> void:
	edited_area = null
	edited_revision = -1
	resident_id = ""
	preview = null
	locked = false
	hide()
func update_world(point: Vector3) -> void:
	if not active() or locked: return
	var center := Coordinates.to_sim(point)
	if preview.center == center and position == Coordinates.to_world(center) and outline.mesh != null: return
	preview.update(center,preview.radius)
	_draw()
func _draw() -> void:
	var radius := Coordinates.length_to_world(preview.radius)
	if outline.mesh == null or not is_equal_approx(outline.mesh.get_aabb().size.x,2*radius):
		outline.mesh = preload("res://scripts/world_3d/building_view_3d.gd").make_work_area_mesh(radius)
	outline.position.y = 0.04
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.3,0.9,1)
	outline.material_override = material
	position = Coordinates.to_world(preview.center)
