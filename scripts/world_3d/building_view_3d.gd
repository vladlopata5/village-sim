extends StaticBody3D
## One visual for the existing BuildingInstance lifecycle; no resources/production logic.
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var building_data: RefCounted
var indicator: MeshInstance3D
var _selected := false
var _workplace_highlighted := false
var material: StandardMaterial3D
var work_area: MeshInstance3D
var layout: Node3D
var _indexed_layout_id := 0
var _marker_groups: Dictionary = {} # Script -> ordered node references, never occupancy.
var construction_visual: MultiMeshInstance3D
var _finished_visuals: Array[Node3D] = []
var level_visual: MeshInstance3D
var well_visual: Node3D
var well_placeholder: Node3D
var bread_visual: Node3D
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
	_finished_visuals.append(visual)
	if data.type==preload("res://scripts/building_type.gd").Type.WELL:
		well_placeholder=visual
		well_visual=preload("res://scripts/world_3d/well_visual_3d.gd").create()
		add_child(well_visual)
		_finished_visuals.append(well_visual)
	if data.type==preload("res://scripts/building_type.gd").Type.SHEPHERD_HUT or data.type in [preload("res://scripts/building_type.gd").Type.FARM,preload("res://scripts/building_type.gd").Type.CLAY_HUT]:
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size=Vector3(size.x+0.4,0.9,size.y+0.4)
		roof.mesh=prism
		roof.position.y=height+0.45
		var roof_material := StandardMaterial3D.new()
		roof_material.albedo_color=Color("705f48")
		roof.material_override=roof_material
		add_child(roof)
		_finished_visuals.append(roof)
	if data.type == preload("res://scripts/building_type.gd").Type.WINDMILL:
		bread_visual = preload("res://scripts/world_3d/bread_building_visuals_3d.gd").create(data.type)
		bread_visual.rotation.y = data.quarter_turns*PI/2.0
		add_child(bread_visual)
		_finished_visuals.append(bread_visual)
	if data.type==preload("res://scripts/building_type.gd").Type.POTTERY_WORKSHOP:
		var chimney:=MeshInstance3D.new()
		var stack:=BoxMesh.new();stack.size=Vector3(.7,1.2,.7)
		chimney.mesh=stack;chimney.position=Vector3(-size.x*.3,height+.4,-size.y*.25)
		var clay_material:=StandardMaterial3D.new();clay_material.albedo_color=Color("80503b")
		chimney.material_override=clay_material;add_child(chimney);_finished_visuals.append(chimney)
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
	caption.position.y = (6.5 if data.type==preload("res://scripts/building_type.gd").Type.WINDMILL else height + 0.36) + (0.9 if data.definition.animal_capacity>0 or data.type==preload("res://scripts/building_type.gd").Type.FARM else 0.0)
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(caption)
	if data.definition.work_radius > 0:
		_create_work_area(data.definition.work_radius)
	layout = preload("res://scripts/world_3d/building_layouts_3d.gd").create(data.definition)
	layout.rotation.y = data.quarter_turns*PI/2.0
	add_child(layout)
	rebuild_marker_index()
	_create_layout_visuals()
	data.construction_changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var colors := [Color("bd976b"), Color("829ba7"), Color("9aaa70"), Color("c2aa91"),Color("88735d"),Color("a28559"),Color("547ea8"),Color("89918b"),Color("b5a677"),Color("9186b0"),Color("bb8393"),Color("b69e69"),Color("d4c6a3"),Color("c59a79"),Color("b58259"),Color("c16e4c"),Color("8d969e")]
	material.albedo_color = colors[building_data.type] if building_data.is_built() else Color("8b7357")
	if well_visual!=null:
		well_visual.visible=building_data.is_built();well_placeholder.visible=not building_data.is_built()
	if bread_visual!=null:
		bread_visual.visible = building_data.is_built()
		var rotor: Node = bread_visual.get_node_or_null("Rotor")
		if rotor!=null:rotor.set_process(building_data.is_built())
	var staged: bool=building_data.is_upgrading() or (not building_data.is_built() and not building_data.previously_built)
	for visual in _finished_visuals:visual.visible=not staged
	if not staged:
		if well_visual!=null:well_visual.visible=building_data.is_built();well_placeholder.visible=not building_data.is_built()
		if bread_visual!=null:bread_visual.visible=building_data.is_built()
		if construction_visual!=null:construction_visual.free();construction_visual=null
	else:
		if construction_visual==null:
			construction_visual=preload("res://scripts/world_3d/construction_visual_3d.gd").new()
			add_child(construction_visual)
		construction_visual.present(building_data.construction_visual_id(),Geometry.building_size(building_data),Geometry.building_height(building_data))
	if building_data.level>1 and level_visual==null:
		level_visual=MeshInstance3D.new()
		var band:=BoxMesh.new();var size:=Geometry.building_size(building_data)
		band.size=Vector3(size.x*.85,.22,size.y*.85);level_visual.mesh=band
		level_visual.position.y=Geometry.building_height(building_data)+.12
		var tint:=StandardMaterial3D.new();tint.albedo_color=Color("557b86");level_visual.material_override=tint
		add_child(level_visual)
	if level_visual!=null:level_visual.visible=not staged
	for marker in _marker_groups.get(preload("res://scripts/world_3d/building_slot_3d.gd"),[]):marker.visible=marker.minimum_level<=building_data.level
	set_inside_count(inside_count)
	caption.text = building_data.display_name + (" II" if building_data.level==2 else "") + (" — улучшение II" if building_data.is_upgrading() else "" if building_data.is_built() else " — " + building_data.work_status().to_lower())
func set_selected(value: bool) -> void:
	_selected = value
	indicator.visible = _selected or _workplace_highlighted
func set_workplace_highlighted(value: bool) -> void:
	_workplace_highlighted = value
	indicator.visible = _selected or _workplace_highlighted

func rebuild_marker_index() -> void:
	_clear_marker_index()
	if not is_instance_valid(layout): return
	_indexed_layout_id = layout.get_instance_id()
	_index_markers(layout)

func _index_markers(node: Node) -> void:
	# Same authored DFS order as BuildingLayouts3D.markers, discovered once per layout.
	for child in node.get_children():
		var marker_script: Script = child.get_script()
		if marker_script != null:
			if not _marker_groups.has(marker_script): _marker_groups[marker_script] = []
			_marker_groups[marker_script].append(child)
			var callback := _marker_exiting.bind(child,marker_script)
			if not child.tree_exiting.is_connected(callback): child.tree_exiting.connect(callback)
		_index_markers(child)

func get_markers(marker_script: Script) -> Array:
	if not is_instance_valid(layout):
		_clear_marker_index()
		return []
	if _indexed_layout_id != layout.get_instance_id(): rebuild_marker_index()
	var registered: Array = _marker_groups.get(marker_script,[])
	# Detached setup/test layouts do not emit tree_exiting when a child is freed.
	if not layout.is_inside_tree():
		registered = registered.filter(func(marker): return is_instance_valid(marker) and layout.is_ancestor_of(marker))
		_marker_groups[marker_script] = registered
	# Caller owns its array; geometry/occupant still belong to the live nodes.
	return registered.duplicate()

func _marker_exiting(marker: Node, marker_script: Script) -> void:
	var registered: Array = _marker_groups.get(marker_script,[])
	registered.erase(marker)

func _clear_marker_index() -> void:
	for marker_script in _marker_groups:
		for marker in _marker_groups[marker_script]:
			if not is_instance_valid(marker): continue
			var callback := _marker_exiting.bind(marker,marker_script)
			if marker.tree_exiting.is_connected(callback): marker.tree_exiting.disconnect(callback)
	_marker_groups.clear()
	_indexed_layout_id = 0

func _exit_tree() -> void:
	_clear_marker_index()

static func make_work_area_mesh(radius: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var color := StandardMaterial3D.new()
	color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	color.albedo_color = Color("80c994")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES,color)
	for index in range(64):
		for angle in [index*TAU/64.0,(index+1)*TAU/64.0]:
			mesh.surface_add_vertex(Vector3(cos(angle)*radius,0.04,sin(angle)*radius))
	mesh.surface_end()
	return mesh

func _create_work_area(radius: float) -> void:
	work_area = MeshInstance3D.new()
	work_area.mesh = make_work_area_mesh(radius)
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
	var colors := [Color("7fe889"),Color("ffe178"),Color("ec89e1"),Color("82b7ff"),Color("ff9f5c"),Color("afdbed"),Color("c6a9e6")]
	for marker in get_markers(preload("res://scripts/world_3d/building_slot_3d.gd")):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.24,0.12,0.24)
		var tint := StandardMaterial3D.new()
		tint.albedo_color = colors[marker.purpose]
		mesh.material = tint
		var cube := MeshInstance3D.new()
		cube.mesh = mesh
		cube.position.y = 0.06
		marker.add_child(cube)
	for marker in get_markers(preload("res://scripts/world_3d/building_entrance_3d.gd")):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(marker.zone_size.x,0.08,marker.zone_size.y)
		var tint := StandardMaterial3D.new()
		tint.albedo_color = Color("c8c4aa")
		mesh.material = tint
		var platform := MeshInstance3D.new()
		platform.mesh = mesh
		platform.position.y = 0.04
		marker.add_child(platform)
