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
