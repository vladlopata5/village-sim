extends PanelContainer
# Presentation counters for focused UI diagnostics; never used by simulation.
var refresh_count := 0
## A Tree projection of PlayerControl's registry; never a second population model.
signal assignment_requested(resident_id: String)
const Profession = preload("res://scripts/resident_profession.gd")
var row_creation_count := 0
var poll_count := 0
var registry_scan_count := 0
var control: RefCounted
var selection: Node
var rows: Dictionary = {} # resident ID -> existing TreeItem (presentation only).
var visible_ids: Array[String] = []
var search: LineEdit
var profession_filter: OptionButton
var eligibility_filter: OptionButton
var employment_filter: OptionButton
var sort_order: OptionButton
var reverse_order: CheckButton
var table: Tree
var context_label: Label
var count_label: Label
var _root: TreeItem
var _dirty_ids: Dictionary = {}
var _roster_dirty := true
var _projection_dirty := true
var _pending := false
var _layout_pending := false
var _connections: Array = []
var _pressed_id := ""
var _canonical_layout := false
var _poll_elapsed := 0.0
var _display_snapshot: Dictionary = {}
func _ready() -> void:
	position=Vector2(134,160)
	size=Vector2(680,400)
	if has_theme_stylebox("panel", "WindowPanel"):
		theme_type_variation = &"WindowPanel"
	else:
		var style := StyleBoxFlat.new()
		style.bg_color=Color(0.12,0.15,0.13,1)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,12)
		add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	add_child(column)
	context_label=Label.new()
	context_label.text="Жители"
	context_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(context_label)
	search=LineEdit.new()
	search.name="Search"
	search.placeholder_text="Поиск по имени"
	search.text_changed.connect(func(_text): _projection_changed())
	column.add_child(search)
	var filters := HBoxContainer.new()
	column.add_child(filters)
	profession_filter=_profession_options(filters,"Текущая профессия")
	eligibility_filter=_profession_options(filters,"Доступная профессия")
	employment_filter=_options(filters,"Назначение",["Все","Есть место / область","Без места / области"])
	var sort_row := HBoxContainer.new()
	column.add_child(sort_row)
	var sort_label := Label.new()
	sort_label.text="Сортировка:"
	sort_row.add_child(sort_label)
	sort_order=OptionButton.new()
	for title in ["По имени","По возрасту","По назначению"]: sort_order.add_item(title)
	sort_order.item_selected.connect(func(_index): _projection_changed())
	sort_row.add_child(sort_order)
	reverse_order=CheckButton.new()
	reverse_order.text="Обратно"
	reverse_order.toggled.connect(func(_value): _projection_changed())
	sort_row.add_child(reverse_order)
	table=Tree.new()
	table.name="ResidentsTable"
	table.columns=3
	table.hide_root=true
	table.select_mode=Tree.SELECT_ROW
	table.column_titles_visible=true
	table.custom_minimum_size=Vector2(0,160)
	table.size_flags_vertical=Control.SIZE_EXPAND_FILL
	table.mouse_force_pass_scroll_events=false
	for index in range(3):
		table.set_column_title(index,["Имя","Профессия","Рабочее место"][index])
		table.set_column_expand_ratio(index,[4,3,5][index])
	table.gui_input.connect(_table_input)
	column.add_child(table)
	_root=table.create_item()
	var footer := HBoxContainer.new()
	column.add_child(footer)
	count_label=Label.new()
	count_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(count_label)
	var close := Button.new()
	close.text="Закрыть"
	close.focus_mode=Control.FOCUS_NONE
	close.pressed.connect(hide)
	footer.add_child(close)
	visibility_changed.connect(_visibility_changed)
	hide()
func _process(delta: float) -> void:
	if not is_visible_in_tree() or control==null: return
	_poll_elapsed += delta
	if _poll_elapsed < 1.0: return
	_poll_elapsed = 0.0
	_poll_visible()
func _poll_visible() -> void:
	if not is_visible_in_tree() or control==null: return
	poll_count += 1
	for id in rows:
		var resident = control.get_resident(id)
		if resident==null: continue
		var snapshot := [resident.resident_name,resident.age,workplace_label(resident)]
		if _display_snapshot.get(id)!=snapshot: _row_changed(id)
	_selection_changed()
func _options(parent: Node, title: String, values: Array) -> OptionButton:
	var column := VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text=title
	label.add_theme_font_size_override("font_size",13)
	column.add_child(label)
	var menu := OptionButton.new()
	menu.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	menu.clip_text=true
	menu.focus_mode=Control.FOCUS_NONE
	for value in values: menu.add_item(value)
	menu.item_selected.connect(func(_index): _projection_changed())
	column.add_child(menu)
	return menu
func _profession_options(parent: Node, title: String) -> OptionButton:
	var menu := _options(parent,title,["Все"])
	menu.set_item_metadata(0,-1)
	for role in Profession.Type.values():
		menu.add_item(Profession.display_name(role))
		menu.set_item_metadata(menu.item_count-1,role)
	return menu
func setup(player: RefCounted, selected: Node) -> void:
	control=player
	selection=selected
	_connect(control,&"residents_changed",_registry_changed)
	_connect(control,&"profession_changed",_row_changed)
	_connect(control,&"work_assignment_changed",_row_changed)
	_connect(control,&"home_changed",_home_changed)
	_connect(control,&"building_unregistered",_building_removed)
	_connect(selection,&"selection_changed",_selection_changed)
	if control.work_areas!=null: _connect(control.work_areas,&"changed",_registry_changed)
	_selection_changed()
func _connect(source: Object, event: StringName, callback: Callable) -> void:
	source.connect(event,callback)
	_connections.append([source,event,callback])
func _registry_changed() -> void:
	_roster_dirty=true
	_projection_dirty=true
	_queue_refresh()
func _row_changed(id: String) -> void:
	_dirty_ids[id]=true
	_projection_dirty=true
	_queue_refresh()
func _home_changed(id: String, _previous: StringName, _current: StringName) -> void: _row_changed(id)
func _building_removed(_id: StringName) -> void: _registry_changed()
func _selection_changed() -> void:
	var building = selection.selected_building
	var caption: String="Жители" if building==null else "Жители • выбранное здание: "+building.display_name
	if context_label.text==caption: return
	context_label.text=caption
	_layout_fixed.call_deferred()
func _projection_changed() -> void:
	_projection_dirty=true
	_queue_refresh()
func _queue_refresh() -> void:
	if not is_visible_in_tree() or _pending or control==null: return
	_pending=true
	_flush.call_deferred()
func _visibility_changed() -> void:
	_pressed_id=""
	if is_visible_in_tree() and control!=null:
		_flush()
		_layout_fixed.call_deferred()
func _layout_fixed() -> void:
	if not is_inside_tree() or _layout_pending: return
	_layout_pending=true
	get_tree().process_frame.connect(_apply_fixed_layout,CONNECT_ONE_SHOT)
func set_canonical_layout() -> void:
	_canonical_layout=true
	get_parent().resized.connect(_layout_fixed)
	_layout_fixed.call_deferred()
func _apply_fixed_layout() -> void:
	_layout_pending=false
	position=Vector2(12,12) if _canonical_layout else Vector2(134,160)
	size=Vector2(get_parent().size.x-356,get_parent().size.y-244) if _canonical_layout else Vector2(680,400)
func has_work_assignment(resident: RefCounted) -> bool:
	return not resident.work_location_id.is_empty() or not resident.work_area_id.is_empty()
func workplace_label(resident: RefCounted) -> String:
	if not resident.work_location_id.is_empty():
		var building = control.get_building(resident.work_location_id)
		return building.display_name if building!=null else "Здание недоступно"
	if not resident.work_area_id.is_empty():
		var area = control.work_areas.get_area(resident.work_area_id) if control.work_areas!=null else null
		return "Свободная область: %s" % resident.work_area_id if area!=null else "Область недоступна: %s" % resident.work_area_id
	if resident.profession==Profession.Type.PORTER: return "Носильщик без рабочего места"
	if resident.profession==Profession.Type.BUILDER: return "Работа в мире • без закреплённого места"
	return "Место работы не назначено"
func _matches(resident: RefCounted) -> bool:
	if not search.text.is_empty() and not search.text.to_lower() in resident.resident_name.to_lower(): return false
	var current: int=profession_filter.get_selected_metadata()
	var eligible: int=eligibility_filter.get_selected_metadata()
	if current!=-1 and resident.profession!=current: return false
	if eligible!=-1 and not control.profession_eligibility_error(resident.id,eligible).is_empty(): return false
	if employment_filter.selected==1 and not has_work_assignment(resident): return false
	if employment_filter.selected==2 and has_work_assignment(resident): return false
	return true
func _less(first: String, second: String) -> bool:
	var a = control.get_resident(first)
	var b = control.get_resident(second)
	var key_a: Variant=a.resident_name.to_lower()
	var key_b: Variant=b.resident_name.to_lower()
	if sort_order.selected==1: key_a=a.age; key_b=b.age
	elif sort_order.selected==2: key_a=int(has_work_assignment(a)); key_b=int(has_work_assignment(b))
	if key_a==key_b: return first<second # Stable IDs, also in reverse order.
	return key_a>key_b if reverse_order.button_pressed else key_a<key_b
func _update_row(id: String) -> void:
	var resident = control.get_resident(id)
	if resident==null: return
	if not rows.has(id):
		row_creation_count += 1
		var new_item := table.create_item(_root)
		new_item.set_metadata(0,id)
		new_item.custom_minimum_height=30
		for column in range(3):
			new_item.set_autowrap_mode(column,TextServer.AUTOWRAP_WORD_SMART)
		rows[id]=new_item
	var item: TreeItem=rows[id]
	item.set_text(0,resident.resident_name)
	item.set_text(1,Profession.display_name(resident.profession))
	item.set_text(2,workplace_label(resident))
	_display_snapshot[id]=[resident.resident_name,resident.age,item.get_text(2)]
func _flush() -> void:
	_pending=false
	if not is_visible_in_tree() or control==null: return
	refresh_count += 1
	if _roster_dirty:
		registry_scan_count += 1
		var ids: Array=control.get_residents().map(func(resident): return resident.id)
		for id in rows.keys():
			if id not in ids:
				rows[id].free()
				rows.erase(id)
				_display_snapshot.erase(id)
		for id in ids: _dirty_ids[id]=true
		_roster_dirty=false
	for id in _dirty_ids: _update_row(id)
	_dirty_ids.clear()
	if not _projection_dirty: return
	_projection_dirty=false
	var ordered: Array=rows.keys()
	ordered.sort_custom(_less)
	visible_ids.clear()
	var previous: TreeItem=null
	for id in ordered:
		var item: TreeItem=rows[id]
		item.visible=_matches(control.get_resident(id))
		if previous!=null: item.move_after(previous)
		previous=item
		if item.visible: visible_ids.append(id)
	count_label.text=("Совпадений нет • " if visible_ids.is_empty() else "")+"Показано: %d / %d" % [visible_ids.size(),rows.size()]
func preset_profession(role: int=-1) -> void:
	search.text=""
	profession_filter.select(0)
	employment_filter.select(0)
	eligibility_filter.select(0)
	for index in range(eligibility_filter.item_count):
		if eligibility_filter.get_item_metadata(index)==role: eligibility_filter.select(index)
	sort_order.select(0 if role==-1 else 2)
	reverse_order.set_pressed_no_signal(false)
	_projection_changed()
func activate_row(id: String) -> void:
	var resident = control.get_resident(id)
	if resident==null: return
	if selection.selected_building!=null: assignment_requested.emit(id)
	else: selection.select(resident)
func _table_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT: return
	var item := table.get_item_at_position(event.position)
	var id: String=str(item.get_metadata(0)) if item!=null else ""
	if event.pressed: _pressed_id=id
	else:
		if not id.is_empty() and _pressed_id==id: activate_row(id)
		_pressed_id=""
func _exit_tree() -> void:
	if _canonical_layout and get_parent().resized.is_connected(_layout_fixed): get_parent().resized.disconnect(_layout_fixed)
	if get_tree().process_frame.is_connected(_apply_fixed_layout): get_tree().process_frame.disconnect(_apply_fixed_layout)
	for connection in _connections:
		if is_instance_valid(connection[0]) and connection[0].is_connected(connection[1],connection[2]): connection[0].disconnect(connection[1],connection[2])
