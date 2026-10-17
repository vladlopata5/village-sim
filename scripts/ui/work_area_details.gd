extends VBoxContainer
## Read-only WorkArea view inside the existing blue InfoPanel.
signal focus_requested(center: Vector2)
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var selection: Node
var control: RefCounted
var title: Label
var center_label: Label
var radius_label: Label
var assignments_label: Label
var focus_button: Button
var body: ScrollContainer
var refresh_count := 0
var _snapshot: Array = []

func _ready() -> void:
	title = _label(self)
	body = ScrollContainer.new()
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(column)
	center_label = _label(column)
	radius_label = _label(column)
	assignments_label = _label(column)
	focus_button = Button.new()
	focus_button.text = "Показать на карте"
	focus_button.pressed.connect(_focus)
	column.add_child(focus_button)

func _label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func setup(selected: Node, player: RefCounted) -> void:
	selection = selected
	control = player
	selection.selection_changed.connect(refresh)
	if control.work_areas != null: control.work_areas.changed.connect(refresh)
	control.residents_changed.connect(refresh)
	control.work_assignment_changed.connect(_assignment_changed)
	refresh()

func _assignment_changed(_resident_id: String) -> void: refresh()
func refresh() -> void:
	var area: RefCounted = selection.selected_work_area
	if area == null:
		_snapshot.clear()
		return
	if control.work_areas.get_area(area.id) != area:
		selection.clear()
		return
	var people: Array[String] = []
	for resident in control.get_residents():
		if resident.work_area_id == area.id: people.append("%s (%s)" % [resident.resident_name,resident.id])
	var snapshot: Array = [area.id,area.center,area.radius,people]
	if snapshot == _snapshot: return
	_snapshot = snapshot
	refresh_count += 1
	title.text = "Рабочая область\n"+str(area.id)
	var point := Coordinates.to_world(area.center)
	center_label.text = "Центр (мир): X %.1f, Z %.1f" % [point.x,point.z]
	radius_label.text = "Радиус: %.1f мировых единиц" % Coordinates.length_to_world(area.radius)
	assignments_label.text = "Не используется" if people.is_empty() else "Жители:\n"+"\n".join(people)

func apply_presentation(expanded: bool) -> void: body.visible = expanded
func _focus() -> void:
	var area: RefCounted = selection.selected_work_area
	if area != null and control.work_areas.get_area(area.id) == area: focus_requested.emit(area.center)

func _exit_tree() -> void:
	if is_instance_valid(selection) and selection.selection_changed.is_connected(refresh): selection.selection_changed.disconnect(refresh)
	if control != null:
		if control.work_areas != null and control.work_areas.changed.is_connected(refresh): control.work_areas.changed.disconnect(refresh)
		if control.residents_changed.is_connected(refresh): control.residents_changed.disconnect(refresh)
		if control.work_assignment_changed.is_connected(_assignment_changed): control.work_assignment_changed.disconnect(_assignment_changed)
