extends PanelContainer
## Captured identity and read-only admission. All writes go through PlayerControl.
signal focus_requested(target: RefCounted)
var view_button: Button
var focus_button: Button
var _context: WeakRef
var _owner_window: Control
var _reverse := false
var _offer_generation := 0
const Profession = preload("res://scripts/resident_profession.gd")
var control: RefCounted
var selection: Node
var coordinator: Control
var resident_id := ""
var building_id: StringName = &""
var household_id: StringName = &""
var _household: WeakRef
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
	var inspect := HBoxContainer.new()
	column.add_child(inspect)
	view_button=Button.new();inspect.add_child(view_button)
	view_button.pressed.connect(_view_target)
	focus_button=Button.new();focus_button.text="Показать на карте";inspect.add_child(focus_button)
	focus_button.pressed.connect(_focus_target)
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
	coordinator.info_panel.presentation_changed.connect(_context_changed)
	_connections.append([coordinator.info_panel,&"presentation_changed",_context_changed])
func open_for(id: String, owner_window: Control = null) -> bool:
	if owner_window!=null and not owner_window.visible:return false
	var household: RefCounted = null
	if not household_id.is_empty():
		if not _valid_context(false):close();return false
		household=_household.get_ref()
	elif selection.selected_building!=null:
		var home: RefCounted=selection.selected_building
		household=home.get_household(coordinator.info_panel.active_tab)
		if household==null and home.households.size()==1:household=home.households[0]
		if household!=null:
			coordinator.info_panel.set_expanded(true)
			coordinator.info_panel.select_tab(household.id)
	return _open(control.get_resident(id),selection.selected_building,selection.selected_building,owner_window,false,household)
func open_for_building(id: StringName, owner_window: Control = null) -> bool:
	return _open(selection.selected_resident,control.get_building(id),selection.selected_resident,owner_window,true)
func begin_household_selection(id: StringName, owner_window: Control) -> bool:
	close()
	var household: RefCounted=control.get_household(id)
	var building: RefCounted=control.get_household_home(id)
	if household==null or building==null or selection.selected_building!=building:return false
	_capture_context(null,building,building,owner_window,false,household)
	if not _valid_context(false):close();return false
	return true
func _capture_context(resident: RefCounted, building: RefCounted, context: RefCounted, owner_window: Control, reverse: bool, household: RefCounted) -> void:
	_offer_generation += 1
	resident_id=resident.id if resident!=null else "";building_id=building.id
	_resident=weakref(resident) if resident!=null else null
	_building=weakref(building);_context=weakref(context)
	household_id=household.id if household!=null else &""
	_household=weakref(household) if household!=null else null
	_owner_window=owner_window;_reverse=reverse
	if _owner_window!=null: _owner_window.visibility_changed.connect(_context_changed)
	building.construction_changed.connect(_availability_changed)
func _open(resident: RefCounted, building: RefCounted, context: RefCounted, owner_window: Control, reverse: bool, household: RefCounted = null) -> bool:
	if resident==null or building==null or context==null or control.get_building(building.id)!=building: return false
	close()
	_capture_context(resident,building,context,owner_window,reverse,household)
	view_button.text="Открыть карточку здания" if reverse else "Открыть карточку жителя"
	feedback.hide()
	for child in _actions.get_children():
		_actions.remove_child(child);child.queue_free()
	buttons.clear();reasons.clear()
	for role in control.get_workplace_roles(building_id):
		_add_action(role,"Назначить работать здесь" if role==resident.profession else "Назначить: "+Profession.display_name(role))
	# Housing in BuildingCard -> Residents already exists; do not add a new inverse relation.
	if not reverse and control.has_housing_role(building_id):
		_add_action(&"home","Поселить в хозяйство №%d" % household.local_index if household!=null else "Поселить в выбранный дом")
		_add_action(&"clear_home","Выселить из выбранного дома")
	if buttons.is_empty():
		feedback.text="У этого здания нет применимых рабочих назначений.";feedback.show()
	coordinator.open_top_dialog(self)
	size=Vector2(440,320);position=(get_parent().size-size)/2
	_refresh()
	return visible and _valid_context()
func _view_target() -> void:
	if not visible or not _valid_context(): return
	var target = _building.get_ref() if _reverse else _resident.get_ref()
	var reverse := _reverse
	close()
	if reverse: selection.select_building(target)
	else: selection.select(target)
func _focus_target() -> void:
	if not visible or not _valid_context(): return
	var target = _building.get_ref() if _reverse else _resident.get_ref()
	_view_target()
	focus_requested.emit(target)
func _add_action(key: Variant, title: String) -> void:
	var button := Button.new()
	button.text=title
	button.add_theme_font_size_override("font_size",14)
	button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(_execute_offer.bind(key,_offer_generation))
	_actions.add_child(button)
	buttons[key]=button
	var reason := Label.new()
	reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	reason.add_theme_font_size_override("font_size",13)
	_actions.add_child(reason)
	reasons[key]=reason
func _valid_context(require_resident: bool = true) -> bool:
	if _building==null or _context==null or _context.get_ref()==null:return false
	if control.get_building(building_id)!=_building.get_ref() or selection.selected_entity!=_context.get_ref():return false
	if not is_instance_valid(_owner_window) and _owner_window!=null:return false
	if _owner_window!=null and not _owner_window.visible:return false
	if not household_id.is_empty():
		var panel: Control=coordinator.info_panel
		if _household==null or control.get_household(household_id)!=_household.get_ref():return false
		if control.get_household_home(household_id)!=_building.get_ref() or not control.is_housing_target(_building.get_ref()) or _building.get_ref().removal_started:return false
		if not panel.expanded or not panel.building_details.is_visible_in_tree() or panel.active_tab!=household_id:return false
	return not require_resident or (_resident!=null and control.get_resident(resident_id)==_resident.get_ref())
func _error(key: Variant) -> String:
	if not _valid_context(): return "Контекст назначения устарел"
	var resident = control.get_resident(resident_id)
	if key is StringName and key==&"home":
		if household_id.is_empty():return "Выберите доступное хозяйство на вкладке дома"
		if resident.household_id==household_id:return "Житель уже живёт в этом хозяйстве"
		return control.household_assignment_error(resident_id,household_id)
	if key is StringName and key==&"clear_home":
		var matches: bool=not household_id.is_empty() and resident.household_id==household_id
		return "Житель не живёт в выбранном хозяйстве" if not matches else ""
	if key not in control.get_workplace_roles(building_id): return "Роль недоступна"
	var error: String=control.workplace_assignment_error(resident_id,building_id,key,true)
	if error.is_empty() and resident.work_location_id==building_id and resident.profession==key: return "Житель уже работает здесь в этой роли"
	return error
func _refresh() -> void:
	if not is_visible_in_tree(): return
	if not _valid_context(): close(); return
	refresh_count += 1
	var resident = control.get_resident(resident_id)
	var building = control.get_building(building_id)
	title_label.text="Назначение жителя «%s»\nЗдание: «%s»" % [resident.resident_name,building.display_name]
	if _household!=null:title_label.text+="\nХозяйство №%d" % _household.get_ref().local_index
	for key in buttons:
		var error := _error(key)
		buttons[key].disabled=not error.is_empty()
		reasons[key].text=error
		reasons[key].visible=not error.is_empty()
func _execute_offer(key: Variant, generation: int) -> bool:
	return execute(key) if generation==_offer_generation else false
func execute(key: Variant) -> bool:
	if not visible or not buttons.has(key): return false
	if not _valid_context(): close(); return false
	var error := _error(key)
	if not error.is_empty():
		feedback.text=error;feedback.show();_refresh()
		return false
	var accepted := false
	if key is StringName and key==&"home": accepted=control.assign_household(resident_id,household_id)
	elif key is StringName and key==&"clear_home": accepted=control.clear_household(resident_id)
	else: accepted=control.assign_workplace(resident_id,building_id,key,true)
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
	_visibility_changed() # Also releases a captured household while the resident picker is still open.
func _visibility_changed() -> void:
	if visible: return
	_offer_generation += 1
	if _building!=null:
		var building = _building.get_ref()
		if building!=null and building.construction_changed.is_connected(_availability_changed): building.construction_changed.disconnect(_availability_changed)
	if is_instance_valid(_owner_window) and _owner_window.visibility_changed.is_connected(_context_changed): _owner_window.visibility_changed.disconnect(_context_changed)
	_owner_window=null;_context=null
	_resident=null;_building=null
	resident_id="";building_id=&"";household_id=&"";_household=null
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_poll_elapsed += delta
	if _poll_elapsed < 0.25: return
	_poll_elapsed=0.0
	_refresh()
func _availability_changed() -> void:
	_context_changed()
	_refresh()
func _resident_changed(_id: String) -> void: _refresh()
func _home_changed(_id: String, _previous: StringName, _current: StringName) -> void: _refresh()
func _resident_removed(_id: String) -> void: _refresh()
func _building_removed(_id: StringName) -> void: _refresh()
func _context_changed() -> void:
	if (visible or _household!=null) and not _valid_context(_resident!=null):
		var close_picker: bool=_household!=null and _owner_window!=null and _owner_window==coordinator._windows.get(coordinator._current_window)
		close()
		if close_picker:coordinator.close_window()
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
