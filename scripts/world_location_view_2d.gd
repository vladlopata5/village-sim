extends Marker2D
## Temporary presentation of existing place data.
const WorldLocation = preload("res://scripts/world_location.gd")
var location: WorldLocation
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
		draw_rect(Rect2(-building_data.definition.size / 2, building_data.definition.size), Color(0.7, 0.8, 0.9, 0.3))
