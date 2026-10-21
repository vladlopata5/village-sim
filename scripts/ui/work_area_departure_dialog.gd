extends PanelContainer
## Presentation only. Main revalidates the captured assignment before any write.
signal confirmed
var coordinator: Control
var warning: Label
var confirm_button: Button
var cancel_button: Button
var view_button: Button
var focus_button: Button
var _view_action: Callable
var _focus_action: Callable
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
	var inspect:=HBoxContainer.new();column.add_child(inspect)
	view_button=Button.new();view_button.text="Открыть карточку области";inspect.add_child(view_button)
	view_button.pressed.connect(func():
		if _view_action.is_valid(): _view_action.call())
	focus_button=Button.new();focus_button.text="Показать на карте";inspect.add_child(focus_button)
	focus_button.pressed.connect(func():
		if _focus_action.is_valid(): _focus_action.call())
	view_button.hide();focus_button.hide()
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
	_view_action=Callable();_focus_action=Callable()
	view_button.hide();focus_button.hide()
	confirm_button.disabled=false;confirm_button.text="Продолжить"
	warning.text=text
	coordinator.open_top_dialog(self)
	size=Vector2(440,280)
	position=(get_parent().size-size)/2
func inspect_with(view: Callable, focus: Callable, caption: String = "Открыть карточку области") -> void:
	view_button.text=caption
	_view_action=view;_focus_action=focus
	view_button.show();focus_button.show()
func close() -> void:
	_view_action=Callable();_focus_action=Callable()
	coordinator.close_top_dialog(self)
