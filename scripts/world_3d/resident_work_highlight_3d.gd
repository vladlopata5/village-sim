extends Node3D
## One read-only overlay for the resident Work tab. Not an assignment or work planner.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const BuildingView = preload("res://scripts/world_3d/building_view_3d.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
var circle := MeshInstance3D.new()
var _panel: Control
var _control: RefCounted
var _areas: RefCounted
var _locations: RefCounted
var _building_view: Node
var _signature: Array = []
var _radius := -1.0

func _ready() -> void:
	circle.name = "WorkAreaOutline"
	circle.visible = false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ffd56b")
	circle.material_override = material
	add_child(circle)

func setup(panel: Control, control: RefCounted, areas: RefCounted, locations: RefCounted) -> void:
	_panel = panel
	_control = control
	_areas = areas
	_locations = locations
	_panel.presentation_changed.connect(refresh)
	_panel.visibility_changed.connect(refresh)
	_control.work_assignment_changed.connect(_assignment_changed)
	_control.profession_changed.connect(_assignment_changed)
	_control.building_unregistered.connect(_building_removed)
	_control.building_work_area_changed.connect(_building_removed)
	_areas.changed.connect(refresh)
	refresh()

func _process(_delta: float) -> void:
	# Position/work_radius have no change signal. Read only a small current identity;
	# the signature guard prevents render/mesh updates when nothing changed.
	refresh()

func _assignment_changed(resident_id: String) -> void:
	if _panel.selection.selected_resident != null and _panel.selection.selected_resident.id == resident_id: refresh()
func _building_removed(_building_id: StringName) -> void: refresh()

func refresh() -> void:
	if not is_instance_valid(_panel) or _panel.selection == null or not _panel.is_visible_in_tree() or not _panel.expanded:
		_show(null,Vector2.ZERO,0.0,[])
		return
	var selected_area: RefCounted = _panel.selection.selected_work_area
	if selected_area != null:
		if _areas.get_area(selected_area.id) == selected_area:
			_show(null,selected_area.center,Coordinates.length_to_world(selected_area.radius),[selected_area.get_instance_id(),selected_area.revision,selected_area.center,selected_area.radius])
		else: _show(null,Vector2.ZERO,0.0,[])
		return
	if _panel.active_tab != &"work":
		_show(null,Vector2.ZERO,0.0,[])
		return
	var resident: RefCounted = _panel.selection.selected_resident
	if resident == null or _control.get_resident(resident.id) != resident:
		_show(null,Vector2.ZERO,0.0,[])
		return
	var presentation: Node
	var center := Vector2.ZERO
	var radius := 0.0 # WORLD units, not ground-resource search radius.
	var area_identity: Array = []
	if not resident.work_location_id.is_empty():
		var building: RefCounted = _control.get_building(resident.work_location_id)
		if building != null and building.is_built() and resident.profession in _control.get_workplace_roles(building.id):
			presentation = _locations.get_view(building.id)
			if presentation != null and ((resident.profession == Profession.LUMBERJACK and building.type == Types.LUMBERJACK_HUT) or (resident.profession == Profession.MINER and building.type == Types.QUARRY) or (resident.profession == Profession.CLAY_DIGGER and building.type == Types.CLAY_HUT) or (resident.profession == Profession.GATHERER and building.type == Types.GATHERER_HUT) or (resident.profession == Profession.SHEPHERD and building.type == Types.SHEPHERD_HUT)):
				var area: RefCounted = _control.get_building_work_area(building.id)
				if area != null:
					center = area.center
					radius = Coordinates.length_to_world(area.radius)
					area_identity = [area.id,area.revision]
	elif resident.profession in [Profession.LUMBERJACK,Profession.MINER]:
		var area: RefCounted = _areas.get_area(resident.work_area_id)
		if area != null:
			center = area.center
			radius = Coordinates.length_to_world(area.radius)
			area_identity = [area.get_instance_id(),area.revision]
	if not center.is_finite() or not is_finite(radius) or radius <= 0: radius = 0.0
	var identity := [resident.get_instance_id(),resident.work_assignment_revision,presentation.get_instance_id() if presentation != null else 0,center,radius] + area_identity
	_show(presentation,center,radius,identity)

func _show(presentation: Node, center: Vector2, radius: float, identity: Array) -> void:
	if identity == _signature: return
	_signature = identity
	if _building_view != presentation:
		if is_instance_valid(_building_view): _building_view.set_workplace_highlighted(false)
		_building_view = presentation
		if is_instance_valid(_building_view): _building_view.set_workplace_highlighted(true)
	circle.visible = radius > 0
	if radius <= 0: return
	if radius != _radius:
		_radius = radius
		circle.mesh = BuildingView.make_work_area_mesh(radius)
	# Slightly above the separate green navigation-debug contour; neither owns the other.
	circle.position = Coordinates.to_world(center) + Vector3(0,0.02,0)

func _exit_tree() -> void:
	if is_instance_valid(_building_view): _building_view.set_workplace_highlighted(false)
	if is_instance_valid(_panel):
		if _panel.presentation_changed.is_connected(refresh): _panel.presentation_changed.disconnect(refresh)
		if _panel.visibility_changed.is_connected(refresh): _panel.visibility_changed.disconnect(refresh)
	if _control != null:
		for pair in [[_control.work_assignment_changed,_assignment_changed],[_control.profession_changed,_assignment_changed],[_control.building_unregistered,_building_removed],[_control.building_work_area_changed,_building_removed]]:
			if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
	if _areas != null and _areas.changed.is_connected(refresh): _areas.changed.disconnect(refresh)
