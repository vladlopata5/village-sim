extends Node2D
## Temporary representation. This reference points to data owned outside the view.
const ResidentData = preload("res://scripts/resident_data.gd")
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
