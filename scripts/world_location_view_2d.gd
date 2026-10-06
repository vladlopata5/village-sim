extends Marker2D
## Temporary presentation of existing place data.
const WorldLocation = preload("res://scripts/world_location.gd")
var location: WorldLocation
var selected := false
var building_data: RefCounted

func setup(data: WorldLocation) -> void:
	location = data
	$Caption.text = location.display_name
	queue_redraw()

func interaction_hit(screen_position: Vector2) -> bool:
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return point.length() <= 20

func _draw() -> void:
	if building_data != null:
		var rect := Rect2(-building_data.definition.size / 2, building_data.definition.size)
		draw_rect(rect, Color(0.7, 0.8, 0.9, 0.3))
		if selected: draw_rect(rect.grow(3), Color("69e5ff"), false, 3)

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()
func selection_hit(screen_position: Vector2) -> bool:
	if building_data == null or not is_visible_in_tree(): return false
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return Rect2(-building_data.definition.size / 2, building_data.definition.size).has_point(point)
