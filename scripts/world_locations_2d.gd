extends RefCounted
## Replaceable 2D mapping, not simulation data.
const WorldLocation = preload("res://scripts/world_location.gd")
var _locations: Dictionary = {}
var _views: Dictionary = {}

func register(location: WorldLocation, view: Node2D) -> void:
	_locations[location.id] = location
	_views[location.id] = view

func get_location(location_id: StringName) -> WorldLocation:
	return _locations.get(location_id)

# null means an unknown location or an absent visual representation.
func get_position(location_id: StringName) -> Variant:
	var view = _views.get(location_id)
	if not is_instance_valid(view):
		return null
	return view.global_position
