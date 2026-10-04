extends Marker2D
## Temporary presentation of existing place data.
const WorldLocation = preload("res://scripts/world_location.gd")
var location: WorldLocation

func setup(data: WorldLocation) -> void:
	location = data
	$Caption.text = location.display_name
