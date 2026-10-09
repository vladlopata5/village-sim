extends RefCounted
## Projects authoritative road state into generic navigation, independent of visuals.
const Balance = preload("res://scripts/balance_config.gd")
var roads: RefCounted
var navigation: RefCounted
func setup(model: RefCounted, grid: RefCounted) -> void:
	roads=model
	navigation=grid
	roads.changed.connect(_refresh)
	_refresh()
func _refresh() -> void:
	var cells: Array[Vector2i]=roads.cells()
	if cells.is_empty(): navigation.remove_traversal_modifier(&"dirt_roads")
	else: navigation.set_traversal_cells(&"dirt_roads",cells,Balance.DIRT_ROAD_SPEED_MULTIPLIER)
