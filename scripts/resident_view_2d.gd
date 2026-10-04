extends Node2D
## Temporary representation. This reference points to data owned outside the view.
const ResidentData = preload("res://scripts/resident_data.gd")
signal selection_requested(data: ResidentData)
var resident_data: ResidentData

func setup(data: ResidentData) -> void:
	resident_data = data
	queue_redraw()

func _draw() -> void:
	if resident_data == null:
		return
	# A simple head and body, with a dark outline for visibility on the field.
	draw_circle(Vector2.ZERO, 19.0, Color("28313b"))
	draw_circle(Vector2.ZERO, 16.0, Color("f2c66d"))
	draw_circle(Vector2(0, -22), 10.0, Color("28313b"))
	draw_circle(Vector2(0, -22), 7.0, Color("ffe5bb"))

func _unhandled_input(event: InputEvent) -> void:
	if resident_data == null or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if local_point.length() <= 19.0 or local_point.distance_to(Vector2(0, -22)) <= 10.0:
			selection_requested.emit(resident_data)
			get_viewport().set_input_as_handled()
