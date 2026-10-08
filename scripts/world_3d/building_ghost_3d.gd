extends Node3D
## Preview only: no collider, entity, resource container or navigation registration.
const Grid = preload("res://scripts/build_grid.gd")
var placement: RefCounted
var box_view := MeshInstance3D.new()
var cells_view := MeshInstance3D.new()
var caption := Label3D.new()
var material := StandardMaterial3D.new()
var _size := Vector2i.ZERO
func setup(model: RefCounted) -> void:
	placement = model
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true # Invalid overlap preview must remain visible through the existing building.
	add_child(box_view)
	add_child(cells_view)
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.no_depth_test = true
	caption.pixel_size = 0.018
	caption.position.y = 1.2
	add_child(caption)
	refresh()
func refresh() -> void:
	visible = placement.is_active() and placement.has_ground_position
	if not visible: return
	position = placement.world_position
	var size: Vector2i = placement.grid.rotated_size(placement.selected_definition.footprint_cells, placement.quarter_turns)
	if size != _size:
		_size = size
		var box := BoxMesh.new()
		box.size = Vector3(size.x * Grid.CELL_SIZE, 0.6, size.y * Grid.CELL_SIZE)
		box.material = material
		box_view.mesh = box
		box_view.position.y = 0.3
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
		var width := size.x * Grid.CELL_SIZE
		var depth := size.y * Grid.CELL_SIZE
		for x in range(size.x + 1):
			lines.surface_add_vertex(Vector3(x * Grid.CELL_SIZE - width/2,0.04,-depth/2))
			lines.surface_add_vertex(Vector3(x * Grid.CELL_SIZE - width/2,0.04,depth/2))
		for z in range(size.y + 1):
			lines.surface_add_vertex(Vector3(-width/2,0.04,z * Grid.CELL_SIZE - depth/2))
			lines.surface_add_vertex(Vector3(width/2,0.04,z * Grid.CELL_SIZE - depth/2))
		lines.surface_end()
		cells_view.mesh = lines
	var valid: bool = placement.can_place()
	material.albedo_color = Color(0.2,0.9,0.45,0.5) if valid else Color(1,0.2,0.2,0.5)
	caption.text = "%s · %d°
%s" % [placement.selected_definition.display_name, placement.quarter_turns * 90, "ЛКМ поставить · R повернуть · Esc/ПКМ отменить" if valid else placement.validation_reason()]
