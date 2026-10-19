extends RefCounted
## Persistent land property; natural stock stays separate from dropped resources.
const Balance = preload("res://scripts/balance_config.gd")
const RESOURCE_TYPE = preload("res://scripts/resource_type.gd").Type.MUSHROOM
signal mushrooms_changed(cell: Vector2i, amount: int)
signal availability_changed
var revision := 0
var _next_id := 1
var _ids: Dictionary = {} # Cell -> generation ID, retained while stock is nonempty.
var _cells_by_id: Dictionary = {}
var _claims: Dictionary = {} # Generation ID -> {owner: one unit}.
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
	if amount(cell)==0:
		var id := StringName("mushroom_%06d" % _next_id)
		_next_id+=1
		_ids[cell]=id;_cells_by_id[id]=cell
	_mushrooms[cell]=amount(cell)+added
	_notify(cell)
	return added
func source_id(cell: Vector2i) -> StringName: return _ids.get(cell,&"")
func source_cell(id: StringName) -> Variant: return _cells_by_id.get(id)
func position(id: StringName) -> Variant:
	var cell: Variant=source_cell(id)
	if not cell is Vector2i: return null
	return preload("res://scripts/world_3d/world_coordinates.gd").to_sim(geometry.cell_to_world(cell))
func available_amount(id: StringName) -> int:
	var cell: Variant=source_cell(id)
	if not cell is Vector2i or (allowed.is_valid() and not allowed.call(cell)): return 0
	return amount(cell)-_claims.get(id,{}).size()
func reserve(id: StringName, owner: StringName) -> bool:
	if owner.is_empty(): return false
	if reserved(id,owner): return true
	if available_amount(id)<1: return false
	if not _claims.has(id): _claims[id]={}
	_claims[id][owner]=1
	revision+=1;availability_changed.emit()
	return true
func reserved(id: StringName, owner: StringName) -> bool:
	return _cells_by_id.has(id) and _claims.get(id,{}).has(owner)
func release(id: StringName, owner: StringName) -> void:
	if not _claims.get(id,{}).erase(owner): return
	if _claims[id].is_empty(): _claims.erase(id)
	revision+=1;availability_changed.emit()
func take_reserved(id: StringName, owner: StringName) -> bool:
	if not reserved(id,owner): return false
	var cell: Vector2i=_cells_by_id[id]
	if allowed.is_valid() and not allowed.call(cell): return false
	_claims[id].erase(owner)
	if _claims[id].is_empty(): _claims.erase(id)
	_remove_quantity(cell,1)
	# Inventory.receive commits immediately after this callback returns. No observer
	# sees the removed unit before it belongs to that inventory.
	revision+=1
	_notify.call_deferred(cell)
	return true
func _remove_quantity(cell: Vector2i, quantity: int) -> void:
	var remaining:=amount(cell)-quantity
	if remaining>0: _mushrooms[cell]=remaining;return
	_mushrooms.erase(cell)
	var id: StringName=source_id(cell)
	_ids.erase(cell);_cells_by_id.erase(id);_claims.erase(id)
func _notify(cell: Vector2i) -> void:
	revision+=1
	mushrooms_changed.emit(cell,amount(cell))
	availability_changed.emit()
func remove_mushrooms(cell: Vector2i, quantity: int = 1) -> int:
	if quantity<=0: return 0
	var removed:=mini(quantity,available_amount(source_id(cell)))
	if removed==0: return 0
	_remove_quantity(cell,removed);_notify(cell)
	return removed
func clear_cells(footprint: Array) -> void:
	# Invalidate every generation and claim before any construction observer runs.
	var changed: Array=[]
	for cell in footprint:
		if amount(cell)>0: changed.append(cell);_remove_quantity(cell,amount(cell))
	for cell in changed: _notify(cell)
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
