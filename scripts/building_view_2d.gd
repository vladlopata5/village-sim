extends Node2D
## Replaceable placeholder referencing building data owned outside the view.
const BuildingInstance = preload("res://scripts/building_instance.gd")
var selected := false
var building_data: BuildingInstance

func setup(data: BuildingInstance) -> void:
	building_data = data
	$Caption.text = building_data.display_name + ("" if building_data.is_built() else " — строится")
	queue_redraw()

func _draw() -> void:
	if building_data == null:
		return
	var rect := Rect2(-building_data.definition.size / 2, building_data.definition.size)
	draw_rect(rect, Color("28313b"))
	draw_rect(rect.grow(-4), Color("b7c78a") if building_data.is_built() else Color("b99a69"))
	if selected: draw_rect(rect.grow(3), Color("69e5ff"), false, 3)

func interaction_hit(screen_position: Vector2) -> bool:
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return building_data != null and Rect2(-building_data.definition.size / 2, building_data.definition.size).has_point(point)

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()
func selection_hit(screen_position: Vector2) -> bool:
	if building_data == null or not is_visible_in_tree(): return false
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return Rect2(-building_data.definition.size / 2, building_data.definition.size).has_point(point)
