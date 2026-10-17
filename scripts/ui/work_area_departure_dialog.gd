extends PanelContainer
## Presentation only. Main revalidates the captured assignment before any write.
signal confirmed
var coordinator: Control
var warning: Label
var confirm_button: Button
var cancel_button: Button
func _ready() -> void:
	theme_type_variation=&"WindowPanel"
	var column:=VBoxContainer.new()
	add_child(column)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	warning=Label.new()
	warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	warning.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(warning)
	var row:=HBoxContainer.new()
	column.add_child(row)
	confirm_button=Button.new()
	confirm_button.text="Продолжить"
	confirm_button.pressed.connect(confirmed.emit)
	row.add_child(confirm_button)
	cancel_button=Button.new()
	cancel_button.text="Отмена"
	cancel_button.pressed.connect(close)
	row.add_child(cancel_button)
	hide()
func open(text: String) -> void:
	warning.text=text
	coordinator.open_top_dialog(self)
	size=Vector2(440,280)
	position=(get_parent().size-size)/2
func close() -> void:
	coordinator.close_top_dialog(self)
