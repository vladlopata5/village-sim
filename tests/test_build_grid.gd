extends SceneTree
const Grid = preload("res://scripts/build_grid.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Placement = preload("res://scripts/world_3d/building_placement_3d.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var grid = Grid.new()
	check(Grid.CELL_SIZE == 0.5 and grid.grid_size() == Vector2i(256,160), "Independent BuildGrid uses explicit world bounds and 0.5 cells")
	for cell in [Vector2i.ZERO,Vector2i(255,159),Vector2i(130,80)]:
		check(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "Build cell/world round trip")
	for type in [Types.HOME,Types.FOOD,Types.STORAGE,Types.GATHERER_HUT]:
		var current_definition = Definition.for_type(type)
		check(current_definition.footprint_cells == (Vector2i(6,4) if type == Types.HOME else Vector2i(12,8)), "Physical footprints explicitly defined in build cells")
	var size := Vector2i(3,5)
	var point: Vector3 = grid.snap(Vector3(0.12,0,0.62),size)
	check(point == Vector3(0.25,0,0.75), "Odd footprint snaps edges onto build cell boundaries")
	for turns in range(4):
		check(grid.rotated_size(size,turns) == (size if turns % 2 == 0 else Vector2i(5,3)), "Quarter-turn rectangular rotation")
		check(grid.footprint_cells(point,size,turns).size() == 15, "Quarter-turn footprint has exact cell count")
	var cells: Array = grid.footprint_cells(point,size)
	check(grid.validation_reason(cells).is_empty(), "Empty region permits footprint")
	check(grid.occupy(&"one",cells), "Occupy stores entity ownership")
	for cell in cells: check(grid.occupant(cell) == &"one", "Occupied cell retains stable ID")
	check(not grid.validation_reason(cells).is_empty(), "Overlap rejects placement")
	check(not grid.occupy(&"two",cells) and grid.occupant(cells[0]) == &"one", "Conflict cannot overwrite owner")
	check(not grid.occupy(&"one",cells), "Repeated registration cannot overwrite ownership")
	grid.release(&"two")
	check(grid.occupant(cells[0]) == &"one", "Unknown release cannot free another owner")
	grid.release(&"one")
	check(grid.validation_reason(cells).is_empty(), "Release frees only owned footprint")
	check(not grid.validation_reason(grid.footprint_cells(Vector3(64,0,0),size)).is_empty(), "Footprint beyond bounds is unavailable")
	check(grid.footprint_cells(Vector3(INF,0,0),size).is_empty(), "Invalid coordinates reject before cell conversion")
	check(grid.footprint_cells(Vector3.ZERO,Vector2i.ZERO).is_empty(), "Zero footprint unavailable")
	check(grid.footprint_cells(Vector3(0.1,0,0.1),Vector2i(6,4)).size() == 35, "Non-aligned starter registration conservatively covers touched cells")
	var placement = Placement.new()
	placement.grid = grid
	placement.setup([])
	var definition = Definition.for_type(Types.HOME)
	definition.footprint_cells = Vector2i(3,4)
	placement.select(definition)
	check(not placement.can_place(), "No ground point cannot confirm")
	placement.update_world_position(Vector3(1.12,0,2.14))
	var original: Vector3 = placement.world_position
	for turn in range(4): placement.rotate()
	check(placement.world_position == original, "Rotation resnaps original cursor; no accumulated drift")
	placement.update_world_position(Vector3(NAN,0,0))
	check(not placement.can_place(), "Nonfinite cursor cannot leave valid stale ghost")
	print("BuildGrid: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
