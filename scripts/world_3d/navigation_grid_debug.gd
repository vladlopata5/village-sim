extends Node3D
## Optional debug meshes only: no collider, occupancy or gameplay control.
var navigation: RefCounted
var movement: Node
var _blocked := MeshInstance3D.new()
var _raw := MeshInstance3D.new()
var _smooth := MeshInstance3D.new()
var _enabled := false
func setup(grid: RefCounted) -> void:
	navigation = grid
	add_child(_blocked)
	add_child(_raw)
	add_child(_smooth)
	navigation.changed.connect(_on_grid_changed)
	visible = false
func set_enabled(value: bool) -> void:
	_enabled = value
	visible = value
	if value:
		_draw_blockers()
		_draw_paths()
func bind_movement(next: Node) -> void:
	if is_instance_valid(movement) and movement.path_changed.is_connected(_on_path_changed): movement.path_changed.disconnect(_on_path_changed)
	movement = next
	if is_instance_valid(movement): movement.path_changed.connect(_on_path_changed)
	if _enabled: _draw_paths()
func _on_grid_changed(_revision: int) -> void:
	if _enabled: _draw_blockers()
func _on_path_changed(points: PackedVector3Array) -> void:
	if not _enabled: return
	_lines(_raw,movement.raw_path,Color("ffd45c"),0.045)
	_lines(_smooth,points,Color("60e9ff"),0.075)
func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material
func _draw_blockers() -> void:
	var mesh := ImmediateMesh.new()
	var cells: Array = navigation.blocked_cells()
	if not cells.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,_material(Color("a25945")))
		for cell in cells:
			var center: Vector3 = navigation.cell_to_world(cell,0.025)
			var half: float = navigation.CELL_SIZE/2.0
			var a := center+Vector3(-half,0,-half)
			var b := center+Vector3(half,0,-half)
			var c := center+Vector3(half,0,half)
			var d := center+Vector3(-half,0,half)
			for point in [a,c,b,a,d,c]: mesh.surface_add_vertex(point)
		mesh.surface_end()
	_blocked.mesh = mesh
func _draw_paths() -> void:
	if is_instance_valid(movement): _on_path_changed(movement.current_path())
	else:
		_raw.mesh = null
		_smooth.mesh = null
func _lines(view: MeshInstance3D, points: PackedVector3Array, color: Color, lift: float) -> void:
	var mesh := ImmediateMesh.new()
	if points.size()>1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES,_material(color))
		for i in range(points.size()-1):
			mesh.surface_add_vertex(points[i]+Vector3.UP*lift)
			mesh.surface_add_vertex(points[i+1]+Vector3.UP*lift)
		mesh.surface_end()
	view.mesh = mesh
