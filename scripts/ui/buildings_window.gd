extends "res://scripts/ui/settlement_list_window.gd"
## VIEW selects buildings; ASSIGN emits a target while preserving the source card.
signal resident_assignment_requested(building_id: StringName)
signal building_selected(building_id: StringName)
signal assignment_selected(building_id: StringName)
signal focus_requested(building_id: StringName)
const BuildingArea = preload("res://scripts/building_work_area.gd")
enum Mode { VIEW, ASSIGN }
var mode := Mode.VIEW
var mode_label: Label
const Profession = preload("res://scripts/resident_profession.gd")
var control: RefCounted
var selection: Node
var empty_label: Label
var focus_button: Button
var rows: Dictionary = {}
var refresh_count := 0
var row_creation_count := 0
var _tracked: Dictionary = {} # Live instances for disconnecting their display signals.
var _snapshots: Dictionary = {}
var _dirty: Dictionary = {}
var _pending := false
var _pressed_id: StringName = &""

func _ready() -> void:
	super._ready()
	configure_table("Здания поселения","BuildingsTable",["Здание","Тип","Состояние"],[4,3,2])
	mode_label = Label.new()
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(mode_label)
	mode_label.hide()
	empty_label = Label.new()
	empty_label.text = "Зданий пока нет."
	header.add_child(empty_label)
	table.gui_input.connect(_table_input)
	focus_button = Button.new()
	focus_button.text = "Показать на карте"
	focus_button.pressed.connect(_focus)
	add_footer_action(focus_button)
	visibility_changed.connect(_shown)
	hide()

func setup(player: RefCounted, selected: Node) -> void:
	control = player
	selection = selected
	control.building_registered.connect(_registered)
	control.building_unregistered.connect(_removed)
	selection.selection_changed.connect(_selection_changed)
	for building in control.get_buildings(): observe(building)
	_selection_changed()

func _shown() -> void:
	_pressed_id = &""
	if not is_visible_in_tree(): end_assignment(); return
	_flush()

func begin_assignment(caption: String) -> void:
	mode = Mode.ASSIGN
	mode_label.text = caption
	mode_label.show()
	focus_button.hide()
	close_button.text = "Отмена"
	_refresh_modes()
func end_assignment() -> void:
	if mode == Mode.VIEW: return
	mode = Mode.VIEW
	mode_label.hide()
	focus_button.show()
	close_button.text = "Закрыть"
	_refresh_modes()
func _refresh_modes() -> void:
	for id in _tracked: _dirty[id] = true
	_queue_refresh()

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
			var item := create_list_row(id)
			rows[id] = item
			row_creation_count += 1
		var snapshot: Array = _snapshots[id]
		var row: TreeItem = rows[id]
		row.set_text(0,snapshot[0])
		row.set_tooltip_text(0,str(id))
		row.set_text(1,snapshot[1])
		row.set_text(2,"Построено" if snapshot[2] else "Строится")
		if mode == Mode.ASSIGN:
			var supported := BuildingArea.supports(control.get_building(id))
			row.set_text(2,"Можно назначить" if supported else ("Строится" if not snapshot[2] else "Нет рабочей области"))
			row.set_custom_color(2,Color("b8e5b5") if supported else Color("a5a5a5"))
		else: row.clear_custom_color(2)
	_dirty.clear()
	empty_label.visible = rows.is_empty()
	_selection_changed()

func _selection_changed() -> void:
	if selection == null: return
	var building: RefCounted = selection.selected_building
	focus_button.disabled = building == null or control.get_building(building.id) != building
	if building != null and rows.has(building.id): rows[building.id].select(0)
func activate_row(id: StringName) -> void:
	var building = control.get_building(id)
	if building == null: return
	if mode == Mode.ASSIGN:
		if BuildingArea.supports(building): assignment_selected.emit(id)
	elif selection.selected_resident!=null: resident_assignment_requested.emit(id)
	else: building_selected.emit(id)
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
	super._exit_tree()
