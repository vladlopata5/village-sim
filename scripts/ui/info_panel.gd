extends PanelContainer
## Owns only presentation state. Selection and simulation objects remain external.
const TITLES = {&"bio":"Био",&"work":"Работа",&"relations":"Отношения",&"info":"Инфо",&"production":"Производство",&"storage":"Склад"}
var selection: Node
var clock: Node
var control: RefCounted
var expanded := false
var active_tab: StringName = &""
var _tabs: Array[StringName] = []
var _preview_definition: RefCounted
var _last_day := -1
@onready var resident_details: PanelContainer = $Column/Body/ResidentDetails
@onready var building_details: PanelContainer = $Column/Body/BuildingDetails
@onready var preview: VBoxContainer = $Column/Body/PreviewScroll/BuildingTypePreview
@onready var day_summary: Label = $Column/Body/DaySummary
func _ready() -> void:
	$Column/Header/Expand.pressed.connect(func(): set_expanded(not expanded))
	$Column/Header/Close.pressed.connect(_close)
	building_details.presentation_changed.connect(_sync_tabs)
	_layout()
func setup(time: Node, selected: Node, player: RefCounted, job_provider: Callable, visitors_provider: Callable, natural_progress: Callable = Callable()) -> void:
	clock = time
	selection = selected
	control = player
	resident_details.clock = clock
	resident_details.job_provider = job_provider
	building_details.visitors_provider = visitors_provider
	building_details.natural_progress_provider = natural_progress
	clock.minute_changed.connect(_minute)
	selection.selection_changed.connect(_selection_changed)
	control.resident_unregistered.connect(_resident_removed)
	control.building_unregistered.connect(_building_removed)
	control.profession_changed.connect(_profession_changed)
	control.work_assignment_changed.connect(_work_changed)
	control.residents_changed.connect(_staff_changed)
	_minute(clock.total_minutes)
	_selection_changed()
func _selection_changed() -> void:
	_preview_definition = null
	if selection.selected_entity == null: expanded = false
	_sync_tabs()
	_apply()
func _sync_tabs() -> void:
	if selection == null: return
	var tabs: Array[StringName] = []
	if selection.selected_resident != null: tabs.assign([&"bio",&"work",&"relations"])
	elif selection.selected_building != null: tabs = building_details.available_tabs()
	if active_tab not in tabs: active_tab = tabs[0] if not tabs.is_empty() else &""
	if tabs != _tabs:
		_tabs = tabs
		for child in $Column/Tabs.get_children():
			$Column/Tabs.remove_child(child)
			child.queue_free()
		for id in _tabs:
			var button := Button.new()
			button.text = TITLES[id]
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(select_tab.bind(id))
			button.set_meta("tab_id",id)
			$Column/Tabs.add_child(button)
	_apply()
func select_tab(id: StringName) -> void:
	if id not in _tabs: return
	active_tab = id
	resident_details.get_node("%Scroll").scroll_vertical = 0
	building_details.get_node("%Scroll").scroll_vertical = 0
	_apply()
func set_expanded(value: bool) -> void:
	expanded = value and selection != null and (selection.selected_entity != null or _preview_definition != null)
	_apply()
func _apply() -> void:
	var resident: bool = selection != null and selection.selected_resident != null
	var building: bool = selection != null and selection.selected_building != null
	var is_preview := _preview_definition != null
	resident_details.visible = resident
	building_details.visible = building
	$Column/Body/PreviewScroll.visible = is_preview
	day_summary.visible = not resident and not building and not is_preview
	$Column/Header.visible = not day_summary.visible
	$Column/Tabs.visible = expanded and not _tabs.is_empty()
	$Column/Header/Expand.text = "Свернуть" if expanded else "Развернуть"
	for button in $Column/Tabs.get_children(): button.set_pressed_no_signal(button.get_meta("tab_id")==active_tab)
	resident_details.apply_presentation(expanded,active_tab)
	building_details.apply_presentation(expanded,active_tab)
	_layout()
func _layout() -> void:
	var height := 52.0 if day_summary.visible else (568.0 if expanded else 152.0)
	reset_size()
	offset_left = -320.0
	offset_right = 0.0
	offset_top = -height
	offset_bottom = 0.0
func show_type_preview(definition: RefCounted) -> bool:
	# E3 supplies its authoritative placement definition; no fictitious entity.
	if selection == null or selection.selected_entity != null or definition == null: return false
	_preview_definition = definition
	preview.show_definition(definition)
	expanded = true
	_apply()
	return true
func clear_type_preview() -> void:
	if _preview_definition == null: return
	_preview_definition = null
	expanded = false
	_apply()
func _close() -> void:
	if _preview_definition != null: clear_type_preview()
	elif selection != null: selection.clear()
func _minute(minutes: int) -> void:
	var day := floori(float(minutes)/1440.0)
	day_summary.text = "День %d" % (day+1)
	if day != _last_day:
		_last_day = day
		resident_details._refresh_diary()
func _resident_removed(id: String) -> void:
	if selection.selected_resident != null and selection.selected_resident.id == id: selection.clear()
func _building_removed(id: StringName) -> void:
	if selection.selected_building != null and selection.selected_building.id == id: selection.clear()
func _profession_changed(id: String) -> void:
	if selection.selected_resident != null and selection.selected_resident.id == id:
		resident_details._refresh_work_place()
		resident_details._refresh()
func _work_changed(id: String) -> void:
	_profession_changed(id)
	_staff_changed()
func _staff_changed() -> void:
	if selection.selected_building != null: building_details._refresh()
func _exit_tree() -> void:
	if clock != null and clock.minute_changed.is_connected(_minute): clock.minute_changed.disconnect(_minute)
	if selection != null and selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
	if control != null:
		for pair in [["resident_unregistered",_resident_removed],["building_unregistered",_building_removed],["profession_changed",_profession_changed],["work_assignment_changed",_work_changed],["residents_changed",_staff_changed]]:
			if control.is_connected(pair[0],pair[1]): control.disconnect(pair[0],pair[1])
