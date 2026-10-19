extends "res://scripts/ui/settlement_list_window.gd"
## VIEW opens cards; ASSIGN emits a target without changing world selection.
signal context_requested(area_id: StringName)
signal area_selected(area_id: StringName)
signal assignment_selected(area_id: StringName)
signal create_requested
enum Mode { VIEW, ASSIGN }
var mode := Mode.VIEW
var mode_label: Label
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var areas: RefCounted
var control: RefCounted
var selection: Node
var empty_label: Label
var create_button: Button
var rows: Dictionary = {}
var refresh_count := 0
var row_creation_count := 0
var _dirty := true
var _pending := false
var _pressed_id: StringName = &""

func _ready() -> void:
	super._ready()
	configure_table("Рабочие области","AreasTable",["Область","Радиус (мир)","Назначено жителей"],[3,2,2])
	mode_label = Label.new()
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(mode_label)
	mode_label.hide()
	empty_label = Label.new()
	empty_label.text = "Областей пока нет. Создайте область на карте."
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(empty_label)
	table.gui_input.connect(_table_input)
	create_button = Button.new()
	create_button.text = "Создать область"
	create_button.pressed.connect(create_requested.emit)
	add_footer_action(create_button)
	visibility_changed.connect(_shown)
	hide()

func setup(registry: RefCounted, player: RefCounted, selected: Node) -> void:
	areas = registry
	control = player
	selection = selected
	areas.changed.connect(_changed)
	areas.presentation_changed.connect(_changed)
	control.residents_changed.connect(_changed)
	control.work_assignment_changed.connect(_assignment_changed)
	selection.selection_changed.connect(_selection_changed)

func begin_assignment(caption: String) -> void:
	mode = Mode.ASSIGN
	mode_label.text = caption
	mode_label.show()
	create_button.hide()
	empty_label.text = "Областей пока нет. Создайте область в обычном режиме окна."
	close_button.text = "Отмена"
func end_assignment() -> void:
	if mode == Mode.VIEW: return
	mode = Mode.VIEW
	mode_label.hide()
	create_button.show()
	empty_label.text = "Областей пока нет. Создайте область на карте."
	close_button.text = "Закрыть"

func _shown() -> void:
	_pressed_id = &""
	if is_visible_in_tree():
		_flush()
	else: end_assignment()

func _assignment_changed(_resident_id: String) -> void: _changed()
func _changed() -> void:
	_dirty = true
	if not is_visible_in_tree() or _pending: return
	_pending = true
	_flush.call_deferred()

func _flush() -> void:
	_pending = false
	if not _dirty or areas == null or not is_visible_in_tree(): return
	_dirty = false
	refresh_count += 1
	var counts: Dictionary = {}
	for resident in control.get_residents():
		if not resident.work_area_id.is_empty(): counts[resident.work_area_id] = counts.get(resident.work_area_id,0)+1
	for id in rows.keys():
		if areas.get_area(id) == null:
			rows[id].free()
			rows.erase(id)
	for area in areas.all():
		if not rows.has(area.id):
			var item := create_list_row(area.id)
			rows[area.id] = item
			row_creation_count += 1
		var row: TreeItem = rows[area.id]
		row.set_text(0,area.display_name)
		row.set_tooltip_text(0,str(area.id))
		row.set_text(1,"%.1f" % Coordinates.length_to_world(area.radius))
		row.set_text(2,str(counts.get(area.id,0)))
	empty_label.visible = rows.is_empty()
	_selection_changed()

func _selection_changed() -> void:
	if selection == null or selection.selected_work_area == null: return
	var id: StringName = selection.selected_work_area.id
	if rows.has(id): rows[id].select(0)

func activate_row(id: StringName) -> void:
	if areas.get_area(id) == null: return
	if mode == Mode.ASSIGN: assignment_selected.emit(id)
	elif selection.selected_resident!=null or selection.selected_building!=null: context_requested.emit(id)
	else: area_selected.emit(id)

func _table_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	var item := table.get_item_at_position(event.position)
	var id: StringName = item.get_metadata(0) if item != null else &""
	if event.pressed: _pressed_id = id
	else:
		if not id.is_empty() and id == _pressed_id: activate_row(id)
		_pressed_id = &""

func _exit_tree() -> void:
	if areas != null and areas.changed.is_connected(_changed): areas.changed.disconnect(_changed)
	if areas != null and areas.presentation_changed.is_connected(_changed): areas.presentation_changed.disconnect(_changed)
	if control != null:
		if control.residents_changed.is_connected(_changed): control.residents_changed.disconnect(_changed)
		if control.work_assignment_changed.is_connected(_assignment_changed): control.work_assignment_changed.disconnect(_assignment_changed)
	if is_instance_valid(selection) and selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
	super._exit_tree()
