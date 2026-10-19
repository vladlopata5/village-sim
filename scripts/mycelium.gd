extends RefCounted
## Persistent land property and natural stock. Never a GroundResource/haul source.
const Balance = preload("res://scripts/balance_config.gd")
const RESOURCE_TYPE = preload("res://scripts/resource_type.gd").Type.MUSHROOM
signal mushrooms_changed(cell: Vector2i, amount: int)
var geometry: RefCounted
var allowed: Callable
var _mycelium: Dictionary = {}
var _mushrooms: Dictionary = {}
func _init(grid: RefCounted) -> void: geometry=grid
func in_bounds(cell: Vector2i) -> bool: return Rect2i(Vector2i.ZERO,geometry.grid_size()).has_point(cell)
func add_mycelium(cell: Vector2i) -> bool:
	if not in_bounds(cell) or _mycelium.has(cell): return false
	_mycelium[cell]=true
	return true
func has_mycelium(cell: Vector2i) -> bool: return _mycelium.has(cell)
func cells() -> Array[Vector2i]:
	var result: Array[Vector2i]=[];result.assign(_mycelium.keys())
	result.sort_custom(func(a,b):return a.y<b.y or (a.y==b.y and a.x<b.x))
	return result
func mushroom_cells() -> Array: return _mushrooms.keys()
func amount(cell: Vector2i) -> int: return _mushrooms.get(cell,0)
func total() -> int:
	var count:=0
	for quantity in _mushrooms.values():count+=quantity
	return count
func can_grow(cell: Vector2i) -> bool:
	return in_bounds(cell) and amount(cell)<Balance.MUSHROOM_CELL_LIMIT and (not allowed.is_valid() or allowed.call(cell))
func add_mushrooms(cell: Vector2i, quantity: int = 1) -> int:
	if quantity<=0 or not can_grow(cell): return 0
	var added:=mini(quantity,Balance.MUSHROOM_CELL_LIMIT-amount(cell))
	_mushrooms[cell]=amount(cell)+added # Commit before synchronous observers can reenter.
	mushrooms_changed.emit(cell,amount(cell))
	return added
func remove_mushrooms(cell: Vector2i, quantity: int = 1) -> int:
	if quantity<=0: return 0
	var removed:=mini(quantity,amount(cell))
	if removed==0: return 0
	var remaining:=amount(cell)-removed
	if remaining==0:_mushrooms.erase(cell)
	else:_mushrooms[cell]=remaining
	mushrooms_changed.emit(cell,remaining)
	return removed
func clear_cells(footprint: Array) -> void:
	# Remove the whole footprint before any observer sees a partially cleared site.
	var changed: Array=[]
	for cell in footprint:
		if _mushrooms.erase(cell):changed.append(cell)
	for cell in changed:mushrooms_changed.emit(cell,amount(cell))
func zone_amount(source: Vector2i) -> int:
	var count:=0;var radius: int=Balance.MUSHROOM_GROWTH_RADIUS
	for y in range(-radius,radius+1):
		for x in range(-radius,radius+1):count+=amount(source+Vector2i(x,y))
	return count
func attempt(source: Vector2i, random: RefCounted) -> Dictionary:
	var result:={"cell":source,"grew":false,"reason":&"zone_full"}
	if not has_mycelium(source):result.reason=&"no_mycelium";return result
	if zone_amount(source)>=Balance.MUSHROOM_ZONE_LIMIT:return result
	var radius: int=Balance.MUSHROOM_GROWTH_RADIUS
	var width:=radius*2+1
	var index: int=random.randi_range(0,width*width-1)
	var target:=source+Vector2i(index%width,floori(float(index)/width))-Vector2i.ONE*radius
	result.cell=target;result.reason=&"blocked"
	if not can_grow(target):return result
	result.reason=&"chance"
	if random.randf()>=Balance.MUSHROOM_GROWTH_CHANCE:return result
	result.grew=add_mushrooms(target)==1
	result.reason=&"grown" if result.grew else &"blocked"
	return result
