extends MeshInstance3D
## Prototype-only path preview, in world coordinates; no collision or input.
func show_path(points: PackedVector3Array) -> void:
	var lines := ImmediateMesh.new()
	mesh = lines
	if points.size() < 2: return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.1)
	lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for point in points: lines.surface_add_vertex(point + Vector3(0, 0.08, 0))
	lines.surface_end()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
