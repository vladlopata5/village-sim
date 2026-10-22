extends "res://scripts/rock_data.gd"
## A separate finite source; claims, partial work and receipts use stone semantics.
func _init(entity_id: StringName, simulation_position: Vector2) -> void:
	super(entity_id,simulation_position)
	resource_type = preload("res://scripts/resource_type.gd").Type.CLAY
