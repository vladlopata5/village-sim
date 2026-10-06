extends Node2D
## Preview only. No instance, resources, location registration or behavior.
const Definition = preload("res://scripts/building_definition.gd")
var definition: Definition
var valid := false
var caption: Label
func _ready() -> void:
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	z_index = 10
func refresh(selected: Definition, world_position: Vector2, allowed: bool) -> void:
	definition = selected
	visible = definition != null
	if not visible: return
	global_position = world_position
	valid = allowed
	caption.text = definition.display_name + ("" if valid else " — нельзя разместить")
	caption.position = Vector2(-definition.size.x / 2, -definition.size.y / 2 - 28)
	queue_redraw()
func _draw() -> void:
	if definition == null: return
	var rect := Rect2(-definition.size / 2, definition.size)
	var color := Color(0.4, 0.9, 0.55, 0.45) if valid else Color(1.0, 0.3, 0.3, 0.5)
	draw_rect(rect, color)
	draw_rect(rect, Color(color, 1.0), false, 2)
