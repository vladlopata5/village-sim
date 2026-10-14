extends PanelContainer
## Captured identity and read-only admission. All writes go through PlayerControl.
const Profession = preload("res://scripts/resident_profession.gd")
var control: RefCounted
var selection: Node
var coordinator: Control
var resident_id := ""
var building_id: StringName = &""
var _resident: WeakRef
var _building: WeakRef
var buttons: Dictionary = {}
var reasons: Dictionary = {}
var title_label: Label
var feedback: Label
var cancel_button: Button
var _actions: VBoxContainer
var _connections: Array = []
var _dismiss_button := 0
var _poll_elapsed := 0.0
var refresh_count := 0
func _ready() -> void:
	position=Vector2(254,120)
	size=Vector2(440,260)
	if has_theme_stylebox("panel", "WindowPanel"):
		theme_type_variation = &"WindowPanel"
	else:
		var style := StyleBoxFlat.new()
		style.bg_color=Color(0.10,0.17,0.20,1)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,12)
		add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	add_child(column)
	title_label=Label.new()
	title_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size",14)
	column.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_force_pass_scroll_events=false
	column.add_child(scroll)
	_actions=VBoxContainer.new()
	_actions.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(_actions)
	feedback=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size",13)
	feedback.hide()
	column.add_child(feedback)
	cancel_button=Button.new()
	cancel_button.text="Отмена"
	cancel_button.focus_mode=Control.FOCUS_NONE
	cancel_button.pressed.connect(close)
	column.add_child(cancel_button)
	visibility_changed.connect(_visibility_changed)
	hide()
func setup(player: RefCounted, selected: Node, ui: Control) -> void:
	control=player; selection=selected; coordinator=ui
	for pair in [[&"residents_changed",_availability_changed],[&"profession_changed",_resident_changed],[&"work_assignment_changed",_resident_changed],[&"home_changed",_home_changed],[&"resident_unregistered",_resident_removed],[&"building_unregistered",_building_removed]]:
		control.connect(pair[0],pair[1])
		_connections.append([control,pair[0],pair[1]])
	selection.selection_changed.connect(_context_changed)
	_connections.append([selection,&"selection_changed",_context_changed])
func open_for(id: String) -> bool:
	var resident = control.get_resident(id)
	var building = selection.selected_building
	if resident==null or building==null or control.get_building(building.id)!=building: return false
	close()
	resident_id=id;building_id=building.id
	_resident=weakref(resident);_building=weakref(building)
	building.construction_changed.connect(_availability_changed)
	title_label.text="Назначение жителя «%s»\nЗдание: «%s»" % [resident.resident_name,building.display_name]
	feedback.hide()
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	buttons.clear();reasons.clear()
	for role in control.get_workplace_roles(building_id): _add_action(role,"Назначить: "+Profession.display_name(role))
	if control.has_housing_role(building_id):
		_add_action(&"home","Поселить в выбранный дом")
		_add_action(&"clear_home","Выселить из выбранного дома")
	if buttons.is_empty():
		feedback.text="У этого здания нет применимых назначений."
		feedback.show()
	coordinator.open_top_dialog(self)
	_refresh()
	return true
func _add_action(key: Variant, title: String) -> void:
	var button := Button.new()
	button.text=title
	button.add_theme_font_size_override("font_size",14)
	button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(execute.bind(key))
	_actions.add_child(button)
	buttons[key]=button
	var reason := Label.new()
	reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	reason.add_theme_font_size_override("font_size",13)
	_actions.add_child(reason)
	reasons[key]=reason
func _valid_context() -> bool:
	return _resident!=null and _building!=null and _resident.get_ref()!=null and _building.get_ref()!=null and control.get_resident(resident_id)==_resident.get_ref() and control.get_building(building_id)==_building.get_ref() and selection.selected_building==_building.get_ref()
func _error(key: Variant) -> String:
	if not _valid_context(): return "Контекст назначения устарел"
	var resident = control.get_resident(resident_id)
	if key is StringName and key==&"home": return control.home_assignment_error(resident_id,building_id)
	if key is StringName and key==&"clear_home": return "Житель не живёт в выбранном доме" if resident.home_location_id!=building_id else ""
	if key not in control.get_workplace_roles(building_id): return "Роль недоступна"
	var error: String=control.workplace_assignment_error(resident_id,building_id,key)
	if error.is_empty() and resident.work_location_id==building_id and resident.profession==key: return "Житель уже работает здесь в этой роли"
	return error
func _refresh() -> void:
	if not is_visible_in_tree(): return
	if not _valid_context(): close(); return
	refresh_count += 1
	var resident = control.get_resident(resident_id)
	var building = control.get_building(building_id)
	title_label.text="Назначение жителя «%s»\nЗдание: «%s»" % [resident.resident_name,building.display_name]
	for key in buttons:
		var error := _error(key)
		buttons[key].disabled=not error.is_empty()
		reasons[key].text=error
		reasons[key].visible=not error.is_empty()
func execute(key: Variant) -> bool:
	if not visible or not buttons.has(key): return false
	if not _valid_context(): close(); return false
	var error := _error(key)
	if not error.is_empty():
		feedback.text=error;feedback.show();_refresh()
		return false
	var accepted := false
	if key is StringName and key==&"home": accepted=control.assign_home(resident_id,building_id)
	elif key is StringName and key==&"clear_home": accepted=control.clear_home(resident_id)
	else: accepted=control.assign_workplace(resident_id,building_id,key)
	if accepted:
		close()
		return true
	feedback.text=_error(key)
	if feedback.text.is_empty(): feedback.text="Назначение отклонено игровыми правилами"
	feedback.show();_refresh()
	return false
func close() -> void:
	if coordinator!=null: coordinator.close_top_dialog(self)
	else: hide()
func _visibility_changed() -> void:
	if visible: return
	if _building!=null:
		var building = _building.get_ref()
		if building!=null and building.construction_changed.is_connected(_availability_changed): building.construction_changed.disconnect(_availability_changed)
	_resident=null;_building=null
	resident_id="";building_id=&""
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_poll_elapsed += delta
	if _poll_elapsed < 0.25: return
	_poll_elapsed=0.0
	_refresh()
func _availability_changed() -> void: _refresh()
func _resident_changed(_id: String) -> void: _refresh()
func _home_changed(_id: String, _previous: StringName, _current: StringName) -> void: _refresh()
func _resident_removed(_id: String) -> void: _refresh()
func _building_removed(_id: StringName) -> void: _refresh()
func _context_changed() -> void:
	if visible and not _valid_context(): close()
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if not event.pressed and event.button_index==_dismiss_button:
		_dismiss_button=0
		get_viewport().set_input_as_handled()
	elif visible and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and not get_global_rect().has_point(event.position):
		_dismiss_button=event.button_index
		close()
		get_viewport().set_input_as_handled()
func _exit_tree() -> void:
	hide()
	_visibility_changed()
	for connection in _connections:
		if is_instance_valid(connection[0]) and connection[0].is_connected(connection[1],connection[2]): connection[0].disconnect(connection[1],connection[2])
