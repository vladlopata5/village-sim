extends VBoxContainer
## WorkArea presentation; player commands and preview belong to Main/PlayerControl.
signal focus_requested(center: Vector2)
signal rename_requested(area_id: StringName)
signal edit_requested(area_id: StringName)
signal delete_requested(area_id: StringName)
signal assign_building_requested(area_id: StringName)
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var selection: Node
var control: RefCounted
var title: Label
var center_label: Label
var radius_label: Label
var assignments_label: Label
var buildings_label: Label
var assign_building_button: Button
var focus_button: Button
var rename_button: Button
var edit_button: Button
var delete_button: Button
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
	buildings_label = _label(column)
	assign_building_button = _action(column,"Назначить здание",assign_building_requested)
	focus_button = Button.new()
	focus_button.text = "Показать на карте"
	focus_button.pressed.connect(_focus)
	column.add_child(focus_button)
	rename_button = _action(column,"Переименовать",rename_requested)
	edit_button = _action(column,"Редактировать область",edit_requested)
	delete_button = _action(column,"Удалить область",delete_requested)

func _action(parent: Node, caption: String, event: Signal) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(func():
		var area: RefCounted = selection.selected_work_area
		if area != null and control.work_areas.get_area(area.id) == area: event.emit(area.id))
	parent.add_child(button)
	return button

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
	if control.work_areas != null: control.work_areas.presentation_changed.connect(refresh)
	control.residents_changed.connect(refresh)
	control.work_assignment_changed.connect(_assignment_changed)
	control.building_work_area_changed.connect(_building_changed)
	control.building_unregistered.connect(_building_changed)
	refresh()

func _assignment_changed(_resident_id: String) -> void: refresh()
func _building_changed(_building_id: StringName) -> void: refresh()
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
	var buildings: Array[String] = []
	for building in control.get_work_area_buildings(area.id): buildings.append("%s (%s)" % [building.display_name,building.id])
	var snapshot: Array = [area.id,area.display_name,area.center,area.radius,people,buildings]
	if snapshot == _snapshot: return
	_snapshot = snapshot
	refresh_count += 1
	title.text = area.display_name+"\nID: "+str(area.id)
	var point := Coordinates.to_world(area.center)
	center_label.text = "Центр (мир): X %.1f, Z %.1f" % [point.x,point.z]
	radius_label.text = "Радиус: %.1f мировых единиц" % Coordinates.length_to_world(area.radius)
	assignments_label.text = "Не используется" if people.is_empty() else "Жители:\n"+"\n".join(people)
	if people.is_empty() and not buildings.is_empty(): assignments_label.text = "Прямых назначений жителей нет."
	buildings_label.text = "Здания: нет назначений" if buildings.is_empty() else "Здания:\n"+"\n".join(buildings)

func apply_presentation(expanded: bool) -> void: body.visible = expanded
func _focus() -> void:
	var area: RefCounted = selection.selected_work_area
	if area != null and control.work_areas.get_area(area.id) == area: focus_requested.emit(area.center)

func _exit_tree() -> void:
	if is_instance_valid(selection) and selection.selection_changed.is_connected(refresh): selection.selection_changed.disconnect(refresh)
	if control != null:
		if control.work_areas != null and control.work_areas.changed.is_connected(refresh): control.work_areas.changed.disconnect(refresh)
		if control.work_areas != null and control.work_areas.presentation_changed.is_connected(refresh): control.work_areas.presentation_changed.disconnect(refresh)
		if control.residents_changed.is_connected(refresh): control.residents_changed.disconnect(refresh)
		if control.work_assignment_changed.is_connected(_assignment_changed): control.work_assignment_changed.disconnect(_assignment_changed)
		for source in [control.building_work_area_changed,control.building_unregistered]:
			if source.is_connected(_building_changed): source.disconnect(_building_changed)
