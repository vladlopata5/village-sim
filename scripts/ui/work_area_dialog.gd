extends PanelContainer
## Rename/delete only. Geometry stays in the shared map preview tool.
var control: RefCounted
var selection: Node
var coordinator: Control
var area: RefCounted
var deleting := false
var title_label: Label
var warning: Label
var name_input: LineEdit
var feedback: Label
var confirm_button: Button
var cancel_button: Button

func _ready() -> void:
	theme_type_variation = &"WindowPanel"
	var column := VBoxContainer.new()
	add_child(column)
	title_label = Label.new()
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Название области"
	name_input.text_submitted.connect(func(_text): execute())
	column.add_child(name_input)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	warning = Label.new()
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(warning)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	var row := HBoxContainer.new()
	column.add_child(row)
	confirm_button = Button.new()
	confirm_button.pressed.connect(execute)
	row.add_child(confirm_button)
	cancel_button = Button.new()
	cancel_button.text = "Отмена"
	cancel_button.pressed.connect(close)
	row.add_child(cancel_button)
	visibility_changed.connect(func():
		if not visible: area = null)
	hide()

func setup(player: RefCounted, selected: Node, ui: Control) -> void:
	control = player
	selection = selected
	coordinator = ui
	selection.selection_changed.connect(_refresh)
	control.work_areas.changed.connect(_refresh)
	control.work_areas.presentation_changed.connect(_refresh)
	control.residents_changed.connect(_refresh)
	control.work_assignment_changed.connect(_assignment_changed)
	get_parent().resized.connect(_layout)

func open_rename(id: StringName) -> void: _open(id,false)
func open_delete(id: StringName) -> void: _open(id,true)
func _open(id: StringName, remove: bool) -> void:
	var current: RefCounted = control.work_areas.get_area(id)
	if current == null or selection.selected_work_area != current: return
	close()
	area = current
	deleting = remove
	name_input.text = area.display_name
	name_input.visible = not deleting
	feedback.text = ""
	confirm_button.text = "Удалить" if deleting else "Переименовать"
	confirm_button.disabled = false
	coordinator.open_top_dialog(self)
	_refresh()
	_layout.call_deferred()
	if not deleting: name_input.grab_focus()

func _layout() -> void:
	if not is_inside_tree(): return
	size = Vector2(440,320)
	position = (get_parent().size-size)/2

func _assignment_changed(_id: String) -> void: _refresh()
func _refresh() -> void:
	if not visible or area == null: return
	if selection.selected_work_area != area or control.work_areas.get_area(area.id) != area:
		close()
		return
	title_label.text = ("Удалить область «%s»?" if deleting else "Переименовать «%s»") % area.display_name
	if not deleting:
		warning.text = "Технический ID и назначения сохранятся."
		return
	var names: Array[String] = []
	for resident in control.get_work_area_residents(area.id): names.append("• %s (%s)" % [resident.resident_name,resident.id])
	warning.text = "Прямых назначений нет." if names.is_empty() else "Будут сняты прямые назначения:\n"+"\n".join(names)
	warning.text += "\nПрофессии сохранятся. Принятая работа не прерывается. Новая область автоматически не назначается."

func execute() -> void:
	if not visible or area == null or confirm_button.disabled: return
	if selection.selected_work_area != area or control.work_areas.get_area(area.id) != area: close(); return
	var id: StringName = area.id
	confirm_button.disabled = true
	var accepted: bool = control.remove_work_area(id) if deleting else control.rename_work_area(id,name_input.text)
	if accepted: close()
	else:
		confirm_button.disabled = false
		feedback.text = "Операция отклонена." if deleting else "Введите непустое название."

func close() -> void:
	if coordinator != null: coordinator.close_top_dialog(self)
	else: hide()

func _exit_tree() -> void:
	if get_parent().resized.is_connected(_layout): get_parent().resized.disconnect(_layout)
	if is_instance_valid(selection) and selection.selection_changed.is_connected(_refresh): selection.selection_changed.disconnect(_refresh)
	if control != null:
		for source in [control.work_areas.changed,control.work_areas.presentation_changed,control.residents_changed]:
			if source.is_connected(_refresh): source.disconnect(_refresh)
		if control.work_assignment_changed.is_connected(_assignment_changed): control.work_assignment_changed.disconnect(_assignment_changed)
