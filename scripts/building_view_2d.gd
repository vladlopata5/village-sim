extends Node2D
## Replaceable placeholder referencing building data owned outside the view.
const BuildingData = preload("res://scripts/building_data.gd")
var building_data: BuildingData

func setup(data: BuildingData) -> void:
	building_data = data
	$Caption.text = building_data.display_name
	queue_redraw()

func _draw() -> void:
	if building_data == null:
		return
	draw_rect(Rect2(-72, -48, 144, 96), Color("28313b"))
	draw_rect(Rect2(-68, -44, 136, 88), Color("b7c78a"))

func interaction_hit(screen_position: Vector2) -> bool:
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return Rect2(-72, -48, 144, 96).has_point(point)
