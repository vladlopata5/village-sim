extends Marker2D
## Temporary presentation of existing place data.
const WorldLocation = preload("res://scripts/world_location.gd")
var location: WorldLocation

func setup(data: WorldLocation) -> void:
	location = data
	$Caption.text = location.display_name

func interaction_hit(screen_position: Vector2) -> bool:
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return point.length() <= 20
