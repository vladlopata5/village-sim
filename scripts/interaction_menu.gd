extends PanelContainer
## Renders options and delegates execution. No knowledge of buildings, needs or jobs.
var service: RefCounted
var resident_ids: Array = []
var options: Array = []
var _column := VBoxContainer.new()
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_column)
	hide()
func open_for(ids: Array, target_id: StringName, screen_position: Vector2) -> void:
	resident_ids = ids.duplicate()
	options = service.get_interactions(resident_ids, target_id)
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	if options.is_empty():
		hide()
		return
	for option in options:
		var button := Button.new()
		button.text = option.label if option.enabled else option.label + "
Недоступно: " + option.disabled_reason
		button.disabled = not option.enabled
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_choose.bind(option))
		_column.add_child(button)
	size = Vector2.ZERO
	position = screen_position.clamp(Vector2.ZERO, (get_viewport_rect().size - get_combined_minimum_size()).max(Vector2.ZERO))
	show()
func _choose(option: RefCounted) -> void:
	hide()
	service.execute(resident_ids, option)
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed and not get_global_rect().has_point(event.position): hide()
