extends PanelContainer
## Browsing projection of the real building registry. Row activation is not assignment.
signal building_selected(building_id: StringName)
signal focus_requested(building_id: StringName)
const Profession = preload("res://scripts/resident_profession.gd")
var control: RefCounted
var selection: Node
var _info_panel: Control
var table: Tree
var empty_label: Label
var focus_button: Button
var close_button: Button
var rows: Dictionary = {}
var refresh_count := 0
var row_creation_count := 0
var _root: TreeItem
var _tracked: Dictionary = {} # Live instances for disconnecting their display signals.
var _snapshots: Dictionary = {}
var _dirty: Dictionary = {}
var _pending := false
var _layout_pending := false
var _pressed_id: StringName = &""

func _ready() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "Здания поселения"
	column.add_child(title)
	empty_label = Label.new()
	empty_label.text = "Зданий пока нет."
	column.add_child(empty_label)
	table = Tree.new()
	table.name = "BuildingsTable"
	table.columns = 3
	table.hide_root = true
	table.select_mode = Tree.SELECT_ROW
	table.column_titles_visible = true
	table.custom_minimum_size.y = 160
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.mouse_force_pass_scroll_events = false
	for index in range(3):
		table.set_column_title(index,["Здание","Тип","Состояние"][index])
		table.set_column_expand_ratio(index,[4,3,2][index])
	table.gui_input.connect(_table_input)
	column.add_child(table)
	_root = table.create_item()
	var footer := HBoxContainer.new()
	column.add_child(footer)
	focus_button = Button.new()
	focus_button.text = "Показать на карте"
	focus_button.pressed.connect(_focus)
	footer.add_child(focus_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	close_button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(hide)
	footer.add_child(close_button)
	visibility_changed.connect(_shown)
	hide()

func setup(player: RefCounted, selected: Node, info_panel: Control = null) -> void:
	control = player
	selection = selected
	_info_panel = info_panel
	control.building_registered.connect(_registered)
	control.building_unregistered.connect(_removed)
	selection.selection_changed.connect(_selection_changed)
	get_parent().resized.connect(_queue_layout)
	if _info_panel != null: _info_panel.resized.connect(_queue_layout)
	for building in control.get_buildings(): observe(building)
	_selection_changed()
	_queue_layout()

func _queue_layout() -> void:
	if _layout_pending or not is_inside_tree(): return
	_layout_pending = true
	get_tree().process_frame.connect(_layout,CONNECT_ONE_SHOT)
func _layout() -> void:
	_layout_pending = false
	if not get_parent() is Control: return
	position = Vector2(12,12)
	var available_width: float = get_parent().size.x-356
	if is_instance_valid(_info_panel) and _info_panel.is_visible_in_tree():
		available_width = minf(available_width,_info_panel.get_global_rect().position.x-get_parent().global_position.x-24)
	size = Vector2(maxf(420,available_width),maxf(260,get_parent().size.y-244))
func _shown() -> void:
	_pressed_id = &""
	if not is_visible_in_tree(): return
	_flush()
	_queue_layout()

func _registered(id: StringName) -> void: observe(control.get_building(id))
func observe(building: RefCounted) -> void:
	if building == null or control.get_building(building.id) != building: return
	var id: StringName = building.id
	if _tracked.get(id) != building:
		_untrack(id)
		_tracked[id] = building
		building.construction_changed.connect(_display_changed.bind(id))
	_display_changed(id)

func _type_label(building: RefCounted) -> String:
	var definition = building.definition
	if definition.is_storage: return "Хранение ресурсов"
	if definition.housing_capacity > 0: return "Жильё"
	if definition.worker_profession != Profession.Type.NONE: return Profession.display_name(definition.worker_profession)
	return definition.display_name
func _display_changed(id: StringName) -> void:
	var building: RefCounted = _tracked.get(id)
	if building == null: return
	var snapshot := [building.display_name,_type_label(building),building.is_built()]
	if _snapshots.get(id) == snapshot: return # Progress, claims and materials are not list columns.
	_snapshots[id] = snapshot
	_dirty[id] = true
	_queue_refresh()
func _untrack(id: StringName) -> void:
	var building: RefCounted = _tracked.get(id)
	var callback := _display_changed.bind(id)
	if building != null and building.construction_changed.is_connected(callback): building.construction_changed.disconnect(callback)
	_tracked.erase(id)
	_snapshots.erase(id)
func _removed(id: StringName) -> void:
	_untrack(id)
	if selection.selected_building != null and selection.selected_building.id == id: selection.clear()
	_dirty[id] = true
	_queue_refresh()

func _queue_refresh() -> void:
	if not is_visible_in_tree() or _pending: return
	_pending = true
	_flush.call_deferred()
func _flush() -> void:
	_pending = false
	if not is_visible_in_tree() or control == null or _dirty.is_empty(): return
	refresh_count += 1
	for id in _dirty:
		if control.get_building(id) == null:
			if rows.has(id): rows[id].free(); rows.erase(id)
			continue
		if not rows.has(id):
			var item := table.create_item(_root)
			item.set_metadata(0,id)
			item.custom_minimum_height = 30
			for column in range(3): item.set_autowrap_mode(column,TextServer.AUTOWRAP_WORD_SMART)
			rows[id] = item
			row_creation_count += 1
		var snapshot: Array = _snapshots[id]
		var row: TreeItem = rows[id]
		row.set_text(0,snapshot[0])
		row.set_tooltip_text(0,str(id))
		row.set_text(1,snapshot[1])
		row.set_text(2,"Построено" if snapshot[2] else "Строится")
	_dirty.clear()
	empty_label.visible = rows.is_empty()
	_selection_changed()

func _selection_changed() -> void:
	if selection == null: return
	var building: RefCounted = selection.selected_building
	focus_button.disabled = building == null or control.get_building(building.id) != building
	if building != null and rows.has(building.id): rows[building.id].select(0)
func activate_row(id: StringName) -> void:
	if control.get_building(id) != null: building_selected.emit(id)
func _focus() -> void:
	var building: RefCounted = selection.selected_building
	if building != null and control.get_building(building.id) == building: focus_requested.emit(building.id)
func _table_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	var item := table.get_item_at_position(event.position)
	var id: StringName = item.get_metadata(0) if item != null else &""
	if event.pressed: _pressed_id = id
	else:
		if not id.is_empty() and id == _pressed_id: activate_row(id)
		_pressed_id = &""

func _exit_tree() -> void:
	for id in _tracked.keys(): _untrack(id)
	if control != null:
		if control.building_registered.is_connected(_registered): control.building_registered.disconnect(_registered)
		if control.building_unregistered.is_connected(_removed): control.building_unregistered.disconnect(_removed)
	if is_instance_valid(selection) and selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
	if is_instance_valid(_info_panel) and _info_panel.resized.is_connected(_queue_layout): _info_panel.resized.disconnect(_queue_layout)
	if get_parent() is Control and get_parent().resized.is_connected(_queue_layout): get_parent().resized.disconnect(_queue_layout)
	if get_tree().process_frame.is_connected(_layout): get_tree().process_frame.disconnect(_layout)
