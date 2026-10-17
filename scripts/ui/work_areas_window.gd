extends PanelContainer
## Browsing only: row activation is separate from any future assignment command.
signal area_selected(area_id: StringName)
signal create_requested
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
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "Рабочие области"
	column.add_child(title)
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
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(hide)
	footer.add_child(close)
	visibility_changed.connect(_shown)
	hide()

func setup(registry: RefCounted, player: RefCounted, selected: Node) -> void:
	areas = registry
	control = player
	selection = selected
	areas.changed.connect(_changed)
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
	if not get_parent() is Control: return
	position = Vector2(12,12)
	size = Vector2(maxf(420,get_parent().size.x-356),maxf(260,get_parent().size.y-244))

func _shown() -> void:
	_pressed_id = &""
	if is_visible_in_tree():
		_flush()
		_queue_layout()

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
		row.set_text(0,str(area.id))
		row.set_text(1,"%.1f" % Coordinates.length_to_world(area.radius))
		row.set_text(2,str(counts.get(area.id,0)))
	empty_label.visible = rows.is_empty()
	_selection_changed()

func _selection_changed() -> void:
	if selection == null or selection.selected_work_area == null: return
	var id: StringName = selection.selected_work_area.id
	if rows.has(id): rows[id].select(0)

func activate_row(id: StringName) -> void:
	if areas.get_area(id) != null: area_selected.emit(id)

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
	if control != null:
		if control.residents_changed.is_connected(_changed): control.residents_changed.disconnect(_changed)
		if control.work_assignment_changed.is_connected(_assignment_changed): control.work_assignment_changed.disconnect(_assignment_changed)
	if is_instance_valid(selection) and selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
	if get_parent() is Control and get_parent().resized.is_connected(_queue_layout): get_parent().resized.disconnect(_queue_layout)
	if get_tree().process_frame.is_connected(_layout): get_tree().process_frame.disconnect(_layout)
