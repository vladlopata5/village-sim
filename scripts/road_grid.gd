extends RefCounted
## Authoritative world road cells, independent of player tools and navigation weights.
const Clock = preload("res://scripts/game_time.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Grid = preload("res://scripts/build_grid.gd")
const CELL_SIZE := Grid.CELL_SIZE
const WORLD_BOUNDS := Grid.WORLD_BOUNDS
signal changed
var geometry: RefCounted
var _roads: Dictionary = {}
# Natural wear never enters _roads or emits changed: planning keeps its old costs.
signal levels_changed(cells: Array[Vector2i])
var levels := PackedByteArray()
var allowed: Callable
var chance: float = Balance.TRAMPLE_CHANCE
var decay_per_night: int = Balance.TRAMPLE_DECAY_PER_NIGHT
var _active: Dictionary = {}
var _used: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _last_boundary := 0
var _clock_ready := false
func _init(bounds: Rect2 = WORLD_BOUNDS) -> void:
	geometry = Grid.new(bounds)
	levels.resize(geometry.grid_size().x * geometry.grid_size().y)
	_random.seed = Balance.TRAMPLE_SEED
func setup_trampling(now: int, seed_value: int = Balance.TRAMPLE_SEED) -> void:
	_random.seed = seed_value
	_last_boundary = floori(float(now - Clock.NIGHT_START) / Clock.MINUTES_PER_DAY) * Clock.MINUTES_PER_DAY + Clock.NIGHT_START
	_clock_ready = true
func trample_level(cell: Vector2i) -> int:
	return levels[_index(cell)] if in_bounds(cell) else 0
func trampled_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for index in _active: result.append(_cell(index))
	return result
func visit(cell: Vector2i) -> void:
	if not in_bounds(cell) or (allowed.is_valid() and not allowed.call(cell)): return
	_used[_index(cell)] = true # A failed roll and a level-15 visit still protect the cell.
	if trample_level(cell) < Balance.TRAMPLE_MAX_LEVEL and _random.randf() < chance:
		set_trample_level(cell,trample_level(cell)+1)
func set_trample_level(cell: Vector2i, value: int) -> bool:
	if not in_bounds(cell) or not _write_level(cell,value): return false
	var modified: Array[Vector2i] = [cell]
	levels_changed.emit(modified)
	return true
func clear_trampling(points: Array) -> void:
	var modified: Array[Vector2i] = []
	for cell in points:
		if not in_bounds(cell): continue
		_used.erase(_index(cell))
		if _write_level(cell,0): modified.append(cell)
	if not modified.is_empty(): levels_changed.emit(modified)
func on_minute(now: int) -> void:
	if not _clock_ready:
		setup_trampling(now)
		return
	while _last_boundary + Clock.MINUTES_PER_DAY <= now:
		_last_boundary += Clock.MINUTES_PER_DAY # Commit before callbacks: duplicate/reentrant time is harmless.
		var modified: Array[Vector2i] = []
		for index in _active.keys():
			if not _used.has(index) and _write_level(_cell(index),levels[index]-maxi(0,decay_per_night)):
				modified.append(_cell(index))
		_used.clear()
		if not modified.is_empty(): levels_changed.emit(modified)
func execution_speed(cell: Vector2i, planned_speed: float) -> float:
	if trample_level(cell) < Balance.TRAMPLE_FAST_LEVEL: return planned_speed
	# Ground's default 1 is not a modifier. Existing tree/manual modifiers use min.
	return Balance.DIRT_ROAD_SPEED_MULTIPLIER if is_equal_approx(planned_speed,1.0) else minf(planned_speed,Balance.DIRT_ROAD_SPEED_MULTIPLIER)
func _index(cell: Vector2i) -> int: return cell.y * geometry.grid_size().x + cell.x
func _cell(index: int) -> Vector2i:
	var width: int = geometry.grid_size().x
	return Vector2i(index % width,floori(float(index) / width))
func _write_level(cell: Vector2i, value: int) -> bool:
	var index := _index(cell)
	value = clampi(value,0,Balance.TRAMPLE_MAX_LEVEL)
	if levels[index] == value: return false
	levels[index] = value
	if value > 0: _active[index] = true
	else:
		_active.erase(index)
		_used.erase(index)
	return true
func contains(cell: Vector2i) -> bool: return _roads.has(cell)
func in_bounds(cell: Vector2i) -> bool: return Rect2i(Vector2i.ZERO,geometry.grid_size()).has_point(cell)
func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.assign(_roads.keys())
	result.sort_custom(func(a,b): return a.y<b.y or (a.y==b.y and a.x<b.x))
	return result
func add_road(cell: Vector2i) -> bool: return edit([cell],false)
func remove_road(cell: Vector2i) -> bool: return edit([cell],true)
func edit(points: Array, erase: bool) -> bool:
	var modified := false
	for cell in points:
		if not in_bounds(cell): continue
		if erase:
			if _roads.erase(cell): modified=true
		elif not contains(cell):
			_roads[cell]=true
			modified=true
	if modified: changed.emit()
	return modified
