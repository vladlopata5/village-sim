extends PanelContainer
## Event-driven population view; selection remains the existing shared model.
var control: RefCounted
var selection: Node
var resident_buttons: Dictionary = {}
var _rows: VBoxContainer
func setup(player: RefCounted, selected: Node) -> void:
	control = player
	selection = selected
	position = Vector2(420,160)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12,0.15,0.13,1.0)
	background.content_margin_left = 12
	background.content_margin_right = 12
	background.content_margin_top = 12
	background.content_margin_bottom = 12
	add_theme_stylebox_override("panel",background)
	custom_minimum_size = Vector2(320,260)
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "Управление поселением — Жители"
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320,220)
	column.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var close := Button.new()
	close.text = "Закрыть"
	close.pressed.connect(hide)
	column.add_child(close)
	control.residents_changed.connect(refresh)
	refresh()
	hide()
func refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	resident_buttons.clear()
	for resident in control.get_residents():
		var button := Button.new()
		button.text = resident.resident_name
		button.pressed.connect(_select_resident.bind(resident.id))
		_rows.add_child(button)
		resident_buttons[resident.id] = button
func _select_resident(id: String) -> void:
	var resident: RefCounted = control.get_resident(id)
	if resident == null: return
	hide()
	selection.select(resident)
