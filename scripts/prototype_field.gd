extends Node2D
## Temporary drawing only; the grid does not define simulation coordinates.
const FIELD := Rect2(-1600, -1000, 3200, 2000)

func _draw() -> void:
	draw_rect(FIELD, Color("587454"))
	for x in range(-1600, 1601, 100):
		draw_line(Vector2(x, -1000), Vector2(x, 1000), Color(1, 1, 1, 0.12))
	for y in range(-1000, 1001, 100):
		draw_line(Vector2(-1600, y), Vector2(1600, y), Color(1, 1, 1, 0.12))
	draw_rect(FIELD, Color("b5c4a2"), false, 4.0)
	draw_circle(Vector2.ZERO, 10.0, Color("e9d8a6"))
	draw_line(Vector2(-25, 0), Vector2(25, 0), Color("e9d8a6"), 2.0)
	draw_line(Vector2(0, -25), Vector2(0, 25), Color("e9d8a6"), 2.0)

func show_phase(phase: String) -> void:
	match phase:
		"Утро": modulate = Color("ffe1ad")
		"День": modulate = Color.WHITE
		"Вечер": modulate = Color("daaa91")
		"Ночь": modulate = Color("65769c")
