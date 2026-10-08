extends "res://scripts/building_placement.gd"
## Uses the shared ID/registry/lifecycle flow, with world-grid placement rules.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var grid: RefCounted
var quarter_turns := 0
var world_position := Vector3.ZERO
var has_ground_position := false
var _cursor_position := Vector3.ZERO
func select(definition: Definition) -> void:
	quarter_turns = 0
	has_ground_position = false
	super.select(definition)
func update_world_position(point: Vector3) -> void:
	has_ground_position = point.is_finite()
	if not is_active() or not has_ground_position: return
	_cursor_position = point
	world_position = grid.snap(point, selected_definition.footprint_cells, quarter_turns)
	position = Coordinates.to_sim(world_position)
func rotate() -> void:
	if not is_active(): return
	quarter_turns = (quarter_turns + 1) % 4
	if has_ground_position: update_world_position(_cursor_position)
	changed.emit()
func proposed_cells() -> Array:
	if not is_active() or not has_ground_position: return []
	return grid.footprint_cells(world_position, selected_definition.footprint_cells, quarter_turns)
func validation_reason() -> String: return grid.validation_reason(proposed_cells())
func can_place() -> bool: return is_active() and has_ground_position and validation_reason().is_empty()
func _create_instance(id: StringName) -> Instance:
	var building := super._create_instance(id)
	building.quarter_turns = quarter_turns
	return building
