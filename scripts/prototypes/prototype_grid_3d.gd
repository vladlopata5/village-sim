extends MeshInstance3D
## Visual scale reference only. No collision, occupancy, snapping or build logic.
const CELL_SIZE: float = 1.0
const CELL_COUNT: int = 30
func _ready() -> void:
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.19, 0.30, 0.19)
	var half_extent := CELL_COUNT * CELL_SIZE / 2.0
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(CELL_COUNT + 1):
		var coordinate := -half_extent + index * CELL_SIZE
		lines.surface_add_vertex(Vector3(coordinate, 0, -half_extent))
		lines.surface_add_vertex(Vector3(coordinate, 0, half_extent))
		lines.surface_add_vertex(Vector3(-half_extent, 0, coordinate))
		lines.surface_add_vertex(Vector3(half_extent, 0, coordinate))
	lines.surface_end()
	mesh = lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
