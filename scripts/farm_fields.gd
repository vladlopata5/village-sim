extends RefCounted
## World-owned soil/crops and short operation claims, independent from farm ownership.
const Season=preload("res://scripts/season.gd")
enum Terrain { GRASS, DIRT, WATER, SAND }
enum State { BARE, PLOWED, SOWN }
signal changed(cells: Array)
signal operation_invalidated(owner: StringName)
var geometry: RefCounted
var revision:=0
var _soil:=PackedByteArray()
var _plots: Dictionary={}
var _claims: Dictionary={}
var _owners: Dictionary={}
var _random:=RandomNumberGenerator.new()
var _clock: Node
var _last_day:=1
func _init(grid: RefCounted, seed_value: int=preload("res://scripts/balance_config.gd").FARM_YIELD_SEED) -> void:
	geometry=grid;_soil.resize(grid.grid_size().x*grid.grid_size().y);_random.seed=seed_value
func setup(clock: Node) -> void:
	_clock=clock;_last_day=clock.get_day()
	clock.minute_changed.connect(_minute);clock.season_changed.connect(_season)
func in_bounds(cell: Vector2i) -> bool:return Rect2i(Vector2i.ZERO,geometry.grid_size()).has_point(cell)
func _index(cell: Vector2i) -> int:return cell.y*geometry.grid_size().x+cell.x
func terrain(cell: Vector2i) -> Terrain:return _soil[_index(cell)] as Terrain if in_bounds(cell) else Terrain.GRASS
func state(cell: Vector2i) -> State:return _plots.get(cell,{}).get("state",State.BARE) as State
func maturity(cell: Vector2i) -> int:return int(_plots.get(cell,{}).get("maturity",0))
func plot_cells() -> Array:return _plots.keys()
func claimed(cell: Vector2i) -> bool:return _claims.has(cell)
func owned(cell: Vector2i, owner: StringName) -> bool:return not owner.is_empty() and _claims.get(cell,&"")==owner
func owned_cells(owner: StringName) -> Array:return _owners.get(owner,[]).duplicate()
func available(cell: Vector2i, expected: State) -> bool:return in_bounds(cell) and terrain(cell)!=Terrain.WATER and state(cell)==expected and not claimed(cell)
func reserve(cells: Array, owner: StringName, expected: State, valid: Callable=Callable()) -> bool:
	if owner.is_empty() or cells.is_empty() or cells.size()>5 or not _season_allows(expected):return false
	if _owners.has(owner):return owned_cells(owner)==cells and cells.all(func(cell):return owned(cell,owner) and state(cell)==expected)
	var unique: Dictionary={}
	for cell in cells:
		if not cell is Vector2i or unique.has(cell) or not available(cell,expected) or (valid.is_valid() and not valid.call(cell)):return false
		unique[cell]=true
	_owners[owner]=cells.duplicate()
	for cell in cells:_claims[cell]=owner
	revision+=1
	return true
func _release_cell(cell: Vector2i, owner: StringName) -> void:
	if not owned(cell,owner):return
	_claims.erase(cell)
	_owners[owner].erase(cell)
	if _owners[owner].is_empty():_owners.erase(owner)
func release(owner: StringName) -> void:
	if not _owners.has(owner):return
	for cell in owned_cells(owner):_release_cell(cell,owner)
	revision+=1
func _notify(cells: Array) -> void:
	revision+=1;changed.emit(cells)
func plow(cell: Vector2i, owner: StringName) -> bool:
	if not owned(cell,owner) or state(cell)!=State.BARE or not _season_allows(State.BARE):return false
	_soil[_index(cell)]=Terrain.DIRT
	_plots[cell]={"state":State.PLOWED}
	_release_cell(cell,owner);_notify([cell]);return true
func sow(cell: Vector2i, owner: StringName, day: int, payment: Callable) -> bool:
	if not owned(cell,owner) or state(cell)!=State.PLOWED or not _season_allows(State.PLOWED) or day<1 or day!=_clock.get_day() or not payment.is_valid():return false
	# Publish before a resource-take callback can observe the consumed seed. A failed
	# take has no callbacks and rolls back; winter/cancellation after a committed
	# take may remove this crop, but cannot recreate it or charge the seed twice.
	_plots[cell]={"state":State.SOWN,"maturity":0,"grown_day":day}
	if not payment.call():
		_plots[cell]={"state":State.PLOWED};return false
	_release_cell(cell,owner);_notify([cell]);return true
func mow(cell: Vector2i, owner: StringName) -> int:
	if not owned(cell,owner) or state(cell)!=State.SOWN or maturity(cell)<4 or not _season_allows(State.SOWN):return -1
	var age:=maturity(cell)
	var amount:=1
	if age==4:amount=1 if _random.randf()<0.5 else 0
	elif age>=6:amount+=1 if _random.randf()<0.5 else 0
	_plots.erase(cell);_soil[_index(cell)]=Terrain.DIRT
	_release_cell(cell,owner);_notify([cell]);return amount
func _minute(_now: int) -> void:
	var day: int=_clock.get_day()
	if day<=_last_day:return
	_last_day=day
	if _clock.get_season()==Season.Type.WINTER:return
	var updated: Array=[]
	for cell in _plots:
		var plot: Dictionary=_plots[cell]
		if plot.state==State.SOWN and day>plot.grown_day:
			plot.maturity+=day-int(plot.grown_day);plot.grown_day=day;updated.append(cell)
	if not updated.is_empty():_notify(updated)
func _season(_previous: int, current: int) -> void:
	if current!=Season.Type.WINTER:return
	var cells:=plot_cells();var owners: Array=_owners.keys()
	_plots.clear();_claims.clear();_owners.clear()
	# Every cultivated cell already has a DIRT base. Winter removes no dropped goods.
	if not cells.is_empty():_notify(cells)
	for owner in owners:operation_invalidated.emit(owner)

func dirt_cells() -> Array:
	var result: Array=[]
	var width: int=geometry.grid_size().x
	for index in _soil.size():
		if _soil[index]==Terrain.DIRT:result.append(Vector2i(index%width,floori(float(index)/width)))
	return result

func _season_allows(expected: State) -> bool:
	if _clock==null:return false
	var current: int=_clock.get_season()
	return current==Season.Type.AUTUMN if expected==State.SOWN else current in [Season.Type.SPRING,Season.Type.SUMMER]

func set_terrain(cells: Array, kind: int, validation: Callable = Callable()) -> bool:
	if kind not in Terrain.values() or cells.is_empty():return false
	var unique: Dictionary={}
	for cell in cells:
		if not cell is Vector2i or not in_bounds(cell) or state(cell)!=State.BARE or claimed(cell) or (validation.is_valid() and not validation.call(cell)):return false
		unique[cell]=true
	var modified: Array=[]
	for cell in unique:
		if terrain(cell)!=kind:_soil[_index(cell)]=kind;modified.append(cell)
	if not modified.is_empty():_notify(modified)
	return true
func surface_cells() -> Array:
	var result: Array=[]
	var width: int=geometry.grid_size().x
	for index in _soil.size():
		if _soil[index]!=Terrain.GRASS:result.append(Vector2i(index%width,floori(float(index)/width)))
	return result
