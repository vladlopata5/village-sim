extends Control
## Canonical presentation shell. Game services, selection and tools remain in Main.
signal blocking_ui_changed
const InputContext = preload("res://scripts/ui/ui_input_context.gd")
var input_context = InputContext.new()
@onready var info_panel: PanelContainer = $InfoAnchor/InfoPanel
@onready var resident_card: Control = info_panel.resident_details
@onready var building_card: Control = info_panel.building_details
@onready var time_controls: PanelContainer = $TimeAnchor/TimeControls
var cancel_world_tool: Callable
var context_menu: Control
var _construction: PanelContainer
var residents_button: Button
var _windows: Dictionary = {}
var _current_window: StringName = &""
var _top_dialog: Control
var _pointer_controls: Array[Control] = []
func _ready() -> void:
	input_context.setup(self)
	register_pointer_control(info_panel)
	register_pointer_control(time_controls)
	resized.connect(_layout_actions)
func register_pointer_control(control: Control) -> void:
	if control not in _pointer_controls:
		_pointer_controls.append(control)
		control.tree_exiting.connect(func(): _pointer_controls.erase(control))
	control.mouse_force_pass_scroll_events = false
func pointer_blocked(point: Vector2) -> bool:
	for control in _pointer_controls:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false
func mount_messages(feed: Control) -> void:
	feed.reparent($MessagesAnchor)
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	feed.position = Vector2.ZERO
	feed.size = Vector2(560, 110)
	feed.newest_first = true
	# Decorative messages do not own pointer input. All children already IGNORE.
func mount_construction(panel: PanelContainer) -> void:
	_construction=panel
	panel.reparent($ActionsAnchor)
	residents_button=panel.buttons[&"residents"]
	panel.quick_window_requested.connect(toggle_window)
	panel.collapse_changed.connect(_construction_changed)
	for surface in panel.input_surfaces(): register_pointer_control(surface)
	_layout_actions()
func _construction_changed(_collapsed: bool) -> void:
	_layout_actions()
func set_actions_expanded(expanded: bool) -> void:
	_construction.set_collapsed(not expanded)
func actions_expanded() -> bool:
	return _construction!=null and not _construction.collapsed
func active_green_tab() -> StringName:
	return _construction.active_tab if _construction!=null else &""
func _layout_actions() -> void:
	if _construction==null: return
	$ActionsAnchor.offset_right=size.x-12.0
	$ActionsAnchor.offset_bottom=8.0
	$ActionsAnchor.offset_top=8.0-_construction.STRIP_HEIGHT if _construction.collapsed else 8.0-(_construction.CATALOG_SIZE.y+_construction.CATALOG_GAP+_construction.STRIP_HEIGHT)
	_construction.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func update_population(count: int) -> void:
	residents_button.text = "↗ Жители: %d" % count
func register_window(id: StringName, window: Control) -> void:
	assert(not _windows.has(id))
	window.reparent($Windows)
	if window is PanelContainer:
		window.remove_theme_stylebox_override("panel")
		window.theme_type_variation = &"WindowPanel"
	_windows[id] = window
	window.hide()
	register_pointer_control(window)
	window.visibility_changed.connect(blocking_ui_changed.emit)
func open_window(id: StringName) -> void:
	if not _windows.has(id): return
	close_window()
	_current_window = id
	_windows[id].show()
func toggle_window(id: StringName) -> void:
	if _current_window == id and _windows[id].visible: close_window()
	else: open_window(id)
func close_window() -> void:
	if _windows.has(_current_window): _windows[_current_window].hide()
	_current_window = &""
func open_top_dialog(dialog: Control) -> void:
	if is_instance_valid(_top_dialog): _top_dialog.hide()
	if dialog.get_parent() != $Windows: dialog.reparent($Windows)
	dialog.move_to_front()
	dialog.z_index = 2 # Upper UI layer, also above the independent F10 panel.
	_top_dialog = dialog
	register_pointer_control(dialog)
	dialog.show()
	blocking_ui_changed.emit()
func close_top_dialog(dialog: Control=null) -> void:
	if dialog!=null and _top_dialog!=dialog: return
	if is_instance_valid(_top_dialog): _top_dialog.hide()
	_top_dialog=null
	blocking_ui_changed.emit()
func bind_context_menu(menu: Control) -> void:
	context_menu = menu
	menu.z_index=4 # Context actions remain above the new overlapping surfaces.
	register_pointer_control(menu)
func try_escape() -> bool:
	if is_instance_valid(_top_dialog) and _top_dialog.visible:
		close_top_dialog()
		return true
	if is_instance_valid(context_menu) and context_menu.visible:
		context_menu.hide()
		blocking_ui_changed.emit()
		return true
	if _windows.has(_current_window) and _windows[_current_window].visible:
		close_window()
		return true
	return cancel_world_tool.is_valid() and cancel_world_tool.call()
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if event.echo or try_escape(): get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	# Feed uses IGNORE, and scroll events can bubble. Boundaries still consume
	# press AND release before any world handler or wheel zoom can use them.
	if event is InputEventMouse and pointer_blocked(event.position):
		get_viewport().set_input_as_handled()
