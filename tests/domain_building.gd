extends Node
var building_data: RefCounted
var position := Vector2.ZERO
var global_position: Vector2:
	get: return position
	set(value): position=value
var selected := false
func setup(data: RefCounted) -> void: building_data=data
func get_sim_position() -> Vector2: return position
func set_selected(value: bool) -> void: selected=value
