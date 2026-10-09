extends Node3D
## Optional debug meshes only: no collider, occupancy or gameplay control.
var navigation: RefCounted
var movement: Node
var _grid := MeshInstance3D.new()
var _blocked := MeshInstance3D.new()
var _slow := MeshInstance3D.new()
var _raw := MeshInstance3D.new()
var _smooth := MeshInstance3D.new()
var _enabled := false
func setup(grid: RefCounted) -> void:
	navigation = grid
	add_child(_grid)
	_draw_grid()
	add_child(_blocked)
	add_child(_slow)
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
func _draw_grid() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,_material(Color("6f8869")))
	var bounds: Rect2=navigation.bounds
	for x in range(navigation.grid_size().x+1):
		var coordinate: float=bounds.position.x+x*navigation.CELL_SIZE
		mesh.surface_add_vertex(Vector3(coordinate,0.03,bounds.position.y))
		mesh.surface_add_vertex(Vector3(coordinate,0.03,bounds.end.y))
	for z in range(navigation.grid_size().y+1):
		var coordinate: float=bounds.position.y+z*navigation.CELL_SIZE
		mesh.surface_add_vertex(Vector3(bounds.position.x,0.03,coordinate))
		mesh.surface_add_vertex(Vector3(bounds.end.x,0.03,coordinate))
	mesh.surface_end()
	_grid.mesh=mesh # Created once; toggling only changes parent visibility.
func _draw_blockers() -> void:
	_draw_cells(_blocked,navigation.blocked_cells(),Color("a25945"))
	_draw_cells(_slow,navigation.modified_cells().filter(func(cell): return navigation.get_cell_speed_multiplier(cell)<1.0),Color("d6b440"))
func _draw_cells(view: MeshInstance3D, cells: Array, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	if not cells.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,_material(color))
		for cell in cells:
			var center: Vector3 = navigation.cell_to_world(cell,0.025)
			var half: float = navigation.CELL_SIZE/2.0
			var a := center+Vector3(-half,0,-half)
			var b := center+Vector3(half,0,-half)
			var c := center+Vector3(half,0,half)
			var d := center+Vector3(-half,0,half)
			for point in [a,c,b,a,d,c]: mesh.surface_add_vertex(point)
		mesh.surface_end()
	view.mesh = mesh
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
