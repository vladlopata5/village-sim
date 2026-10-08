extends PanelContainer
## Short-lived UI output, independent from game-time diary history.
const Balance = preload("res://scripts/balance_config.gd")
var messages: Array = []
var _column: VBoxContainer
var _scroll: ScrollContainer
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 16
	offset_right = 576
	offset_top = -220
	offset_bottom = -118
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_column)
	visible = false
func add_message(text: String) -> void:
	if text.is_empty(): return
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 540
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(label)
	messages.append(label)
	while messages.size() > Balance.SOCIAL_FEED_MAX_MESSAGES: expire_message(messages[0])
	visible = true
	call_deferred("_show_latest")
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = Balance.SOCIAL_FEED_LIFETIME_SECONDS
	add_child(timer)
	var label_reference: WeakRef = weakref(label)
	timer.timeout.connect(func():
		var expired: Label = label_reference.get_ref()
		if expired != null: expire_message(expired)
		timer.queue_free())
	timer.start()
func expire_message(label: Label) -> void:
	if not label in messages: return
	messages.erase(label)
	_column.remove_child(label)
	label.queue_free()
	visible = not messages.is_empty()

func _show_latest() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
