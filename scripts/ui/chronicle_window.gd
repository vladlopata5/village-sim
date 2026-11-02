extends "res://scripts/ui/settlement_list_window.gd"
## Read-only view. Hidden windows keep no subscriptions to individual residents.
const History = preload("res://scripts/settlement_chronicle.gd")
var store: RefCounted
var empty_label: Label
var refresh_count := 0
var _dirty := true
var _pending := false

func _ready() -> void:
	super._ready()
	configure_table("Летопись поселения", "ChronicleTable", ["Дата и события"], [1])
	empty_label = Label.new()
	empty_label.text = "В летописи пока нет событий."
	header.add_child(empty_label)
	visibility_changed.connect(_shown)

func setup(history: RefCounted) -> void:
	if store == history: return
	if store != null and store.changed.is_connected(_changed): store.changed.disconnect(_changed)
	store = history
	if store != null: store.changed.connect(_changed)
	_changed("")

func _changed(_id: String) -> void:
	_dirty = true
	if not is_visible_in_tree() or _pending: return
	_pending = true
	_flush.call_deferred()

func _shown() -> void:
	if is_visible_in_tree(): _flush()

func _flush() -> void:
	_pending = false
	if not _dirty or store == null or not is_visible_in_tree(): return
	_dirty = false
	refresh_count += 1
	var scroll := table.get_scroll()
	table.clear()
	_root = table.create_item()
	var days := {}
	for record in store.entries():
		var day := History.day_for_minute(record.minute)
		if not days.has(day):
			var group := table.create_item(_root)
			group.set_text(0, History.date_text(record.minute))
			group.set_selectable(0, false)
			group.set_metadata(0, day)
			days[day] = group
		var item := table.create_item(days[day])
		item.set_text(0, History.time_text(record.minute) + " · " + record.text)
		item.set_metadata(0, record.id)
		item.set_tooltip_text(0, record.text)
		item.set_autowrap_mode(0, TextServer.AUTOWRAP_WORD_SMART)
		item.set_text_overrun_behavior(0, TextServer.OVERRUN_NO_TRIMMING)
		item.custom_minimum_height = ROW_MINIMUM_HEIGHT
	empty_label.visible = store.size() == 0
	# Tree exposes get_scroll but no setter; restore its native internal scrollbar.
	for child in table.get_children(true):
		if child is VScrollBar: child.set_deferred("value", scroll.y)

func _exit_tree() -> void:
	if store != null and store.changed.is_connected(_changed): store.changed.disconnect(_changed)
	super._exit_tree()
