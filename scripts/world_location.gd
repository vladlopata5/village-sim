extends RefCounted
## Identity and name only; no renderer or spatial coordinates.
var id: StringName
var display_name: String

func _init(location_id: StringName, location_name: String) -> void:
	id = location_id
	display_name = location_name
