extends PanelContainer
## VIEW opens cards; ASSIGN emits a target without changing world selection.
signal context_requested(area_id: StringName)
signal area_selected(area_id: StringName)
signal assignment_selected(area_id: StringName)
signal create_requested
enum Mode { VIEW, ASSIGN }
var mode := Mode.VIEW
var mode_label: Label
var close_button: Button
var _info_panel: Control
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var areas: RefCounted
var control: RefCounted
var selection: Node
var table: Tree
var empty_label: Label
var create_button: Button
var rows: Dictionary = {}
var refresh_count := 0
var row_creation_count := 0
var _root: TreeItem
var _dirty := true
var _pending := false
var _layout_pending := false
var _pressed_id: StringName = &""

func _ready() -> void:
	# Avoid measuring wrapped children against a zero-width new panel.
	size = Vector2(680,400)
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "Рабочие области"
	column.add_child(title)
	mode_label = Label.new()
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(mode_label)
	mode_label.hide()
	empty_label = Label.new()
	empty_label.text = "Областей пока нет. Создайте область на карте."
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(empty_label)
	table = Tree.new()
	table.name = "AreasTable"
	table.columns = 3
	table.hide_root = true
	table.select_mode = Tree.SELECT_ROW
	table.column_titles_visible = true
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size.y = 160
	table.mouse_force_pass_scroll_events = false
	for index in range(3):
		table.set_column_title(index,["Область","Радиус (мир)","Назначено жителей"][index])
		table.set_column_expand_ratio(index,[3,2,2][index])
	table.gui_input.connect(_table_input)
	column.add_child(table)
	_root = table.create_item()
	var footer := HBoxContainer.new()
	column.add_child(footer)
	create_button = Button.new()
	create_button.text = "Создать область"
	create_button.pressed.connect(create_requested.emit)
	footer.add_child(create_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(hide)
	footer.add_child(close_button)
	visibility_changed.connect(_shown)
	hide()

func setup(registry: RefCounted, player: RefCounted, selected: Node, info_panel: Control = null) -> void:
	areas = registry
	control = player
	selection = selected
	_info_panel = info_panel
	if _info_panel != null: _info_panel.resized.connect(_queue_layout)
	areas.changed.connect(_changed)
	areas.presentation_changed.connect(_changed)
	control.residents_changed.connect(_changed)
	control.work_assignment_changed.connect(_assignment_changed)
	selection.selection_changed.connect(_selection_changed)
	get_parent().resized.connect(_queue_layout)
	_queue_layout()

func _queue_layout() -> void:
	if _layout_pending or not is_inside_tree(): return
	_layout_pending = true
	get_tree().process_frame.connect(_layout,CONNECT_ONE_SHOT)

func _layout() -> void:
	_layout_pending = false
	_apply_layout()
func _apply_layout() -> void:
	if not get_parent() is Control: return
	position = Vector2(12,12)
	var available_width: float = get_parent().size.x-356
	if is_instance_valid(_info_panel) and _info_panel.is_visible_in_tree():
		available_width = minf(available_width,_info_panel.get_global_rect().position.x-get_parent().global_position.x-24)
	size.x = maxf(420,available_width)
	size.y = get_combined_minimum_size().y if rows.is_empty() else maxf(260,get_parent().size.y-244)

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
		_apply_layout()
		_flush()
		_queue_layout()
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
			var item := table.create_item(_root)
			item.set_metadata(0,area.id)
			item.custom_minimum_height = 30
			rows[area.id] = item
			row_creation_count += 1
		var row: TreeItem = rows[area.id]
		row.set_text(0,area.display_name)
		row.set_tooltip_text(0,str(area.id))
		row.set_text(1,"%.1f" % Coordinates.length_to_world(area.radius))
		row.set_text(2,str(counts.get(area.id,0)))
	empty_label.visible = rows.is_empty()
	table.visible = not rows.is_empty()
	_queue_layout()
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
	if is_instance_valid(_info_panel) and _info_panel.resized.is_connected(_queue_layout): _info_panel.resized.disconnect(_queue_layout)
	if get_parent() is Control and get_parent().resized.is_connected(_queue_layout): get_parent().resized.disconnect(_queue_layout)
	if get_tree().process_frame.is_connected(_layout): get_tree().process_frame.disconnect(_layout)
