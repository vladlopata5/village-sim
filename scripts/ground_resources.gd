extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Physical drops: lifetime and generic reserved pickup; no automatic transport.
const Drop = preload("res://scripts/ground_resource.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Grid = preload("res://scripts/build_grid.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Balance = preload("res://scripts/balance_config.gd")
enum PlacementMode { NATURAL, WORKER }
var _stack_mode := false
var _grid = Grid.new()
var _by_cell: Dictionary = {}
var _offsets: Dictionary = {}
# Explicit opt-in before any drops are created; canonical worlds enable it on startup.
func enable_stack_mode(bounds: Rect2 = Grid.WORLD_BOUNDS) -> bool:
	if not drops.is_empty() or _stack_mode or not bounds.has_area(): return false
	_grid=Grid.new(bounds)
	_stack_mode=true
	return true
func is_stack_mode() -> bool: return _stack_mode
func get_at(cell: Vector2i) -> Drop: return _by_cell.get(cell)
func has_resources_in_cells(cells: Array) -> bool:
	if _stack_mode:
		for cell in cells:
			var drop:=get_at(cell)
			if drop!=null and drop.amount>0:return true # Includes every owner's reservations.
	else:
		for drop in drops:
			if drop.amount>0 and cell_from_position(drop.world_position) in cells:return true
	return false
func cell_from_position(position: Vector2) -> Vector2i: return _grid.world_to_cell(Coordinates.to_world(position))
func position_from_cell(cell: Vector2i) -> Vector2: return Coordinates.to_sim(_grid.cell_to_world(cell))
signal availability_changed
signal added(drop: Drop)
signal removed(drop: Drop)
var drops: Array[Drop] = [] # Ordered enumeration; mutate through this owner's APIs.
var _by_id: Dictionary = {} # References only; quantities/claims remain on Drop.
var _next_id := 1
var _clock: Node

func setup(clock: Node) -> void:
	_clock = clock
	_clock.minute_changed.connect(_on_minute)

func create_drop(resource: ResourceType.Type, amount: int, position: Vector2) -> Drop:
	if _stack_mode or amount <= 0:
		return null
	var drop = Drop.new(resource, amount, position, _clock.total_minutes)
	while _by_id.has(StringName("ground_%d" % _next_id)): _next_id += 1
	drop.id = StringName("ground_%d" % _next_id)
	_next_id += 1
	return drop if register_drop(drop) else null

func get_by_id(id: StringName) -> Drop:
	return _by_id.get(id)

func register_drop(drop: Drop) -> bool:
	if drop == null or drop.id.is_empty() or drop.amount <= 0 or _by_id.has(drop.id) or drop.owner_callback.is_valid(): return false
	if _stack_mode:
		if not drop.is_stack() or drop.amount>drop.capacity or not _valid_cell(drop.cell) or _by_cell.has(drop.cell) or drop.world_position!=position_from_cell(drop.cell): return false
		_by_cell[drop.cell]=drop
	elif drop.is_stack(): return false
	drop.owner_callback=_drop_changed.bind(weakref(drop)) # No signal -> bound Drop self-cycle.
	drop.availability_changed.connect(drop.owner_callback)
	drops.append(drop)
	_by_id[drop.id] = drop
	if logger != null: logger.info(EventLog.RESOURCE, "GroundResource создан: %d %s на земле; срок 3 игровых дня" % [drop.amount, ResourceType.Type.keys()[drop.resource_type]])
	added.emit(drop)
	availability_changed.emit()
	return true

func _forget(drop: Drop) -> bool:
	if drop == null or get_by_id(drop.id) != drop: return false
	drops.erase(drop)
	_by_id.erase(drop.id)
	if drop.is_stack(): _by_cell.erase(drop.cell)
	if drop.availability_changed.is_connected(drop.owner_callback): drop.availability_changed.disconnect(drop.owner_callback)
	drop.owner_callback=Callable()
	return true

func remove_drop(drop: Drop) -> bool:
	if not _forget(drop): return false
	if not drop._reservations.is_empty():
		drop._reservations.clear()
		drop.availability_changed.emit()
	removed.emit(drop)
	availability_changed.emit()
	return true

func _on_minute(now: int) -> void:
	for drop in drops.duplicate():
		if drop.is_stack():
			if drop.age_minutes(now)>=drop.lifetime: _expire_stack(drop,true)
			continue
		if drop.age_minutes(now) >= drop.lifetime and _forget(drop):
			drop.release(drop.reservation_owner_id)
			if logger != null: logger.info(EventLog.RESOURCE, "GroundResource исчез: истёк срок 3 игровых дня")
			removed.emit(drop)
			availability_changed.emit()

func take_reserved(drop: Drop, worker_id: StringName, quantity: int = 1) -> bool:
	if drop==null or get_by_id(drop.id)!=drop or not drop._take_reserved(worker_id,quantity): return false
	if drop.is_stack():
		var empty:=drop.amount==0
		if empty: _forget(drop)
		drop.availability_changed.emit()
		if empty:
			removed.emit(drop)
			availability_changed.emit()
	else:
		# Preserve legacy final-release callback order until gameplay integration.
		drop.availability_changed.emit()
		if drop.amount==0 and _forget(drop): removed.emit(drop)
		availability_changed.emit()
	return true
func _drop_changed(reference: WeakRef) -> void:
	var drop: Drop=reference.get_ref()
	if drop==null: return
	if drop.is_stack() and get_by_id(drop.id)==drop and _clock!=null and drop.age_minutes(_clock.total_minutes)>=drop.lifetime:
		if _expire_stack(drop,false): return
	availability_changed.emit()
func _expire_stack(drop: Drop, notify: bool) -> bool:
	if get_by_id(drop.id)!=drop or drop.available_amount()<=0: return false
	drop._amount=drop.reserved_total() # Expire only unowned units; no age reset.
	var empty:=drop.amount==0
	if empty: _forget(drop)
	if notify: drop.availability_changed.emit()
	if empty: removed.emit(drop)
	if empty or not notify: availability_changed.emit()
	return true
func _valid_cell(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO,_grid.grid_size()).has_point(cell)
func try_place(resource: ResourceType.Type, quantity: int, cell: Vector2i) -> Dictionary:
	var result:={"placed":0,"remaining":quantity,"stack":null}
	if not _stack_mode or quantity<=0 or resource not in ResourceType.Type.values() or not _valid_cell(cell) or _clock==null: return result
	var drop:=get_at(cell)
	if drop!=null:
		if drop.resource_type!=resource: return result
		var added_quantity:=mini(quantity,drop.capacity-drop.amount)
		if added_quantity<=0: return result
		# The mutation is complete before observers run or reenter.
		drop._add_amount(added_quantity,_clock.total_minutes)
		return {"placed":added_quantity,"remaining":quantity-added_quantity,"stack":drop}
	var limit: int=Balance.GROUND_STONE_STACK_CAPACITY if resource==ResourceType.Type.STONE else Balance.GROUND_STACK_CAPACITY
	var count:=mini(quantity,limit)
	drop=Drop.new(resource,count,position_from_cell(cell),_clock.total_minutes)
	while _by_id.has(StringName("ground_%d" % _next_id)): _next_id+=1
	drop.id=StringName("ground_%d" % _next_id)
	_next_id+=1
	if not drop._configure_cell(cell,position_from_cell(cell)) or not register_drop(drop): return result
	return {"placed":count,"remaining":quantity-count,"stack":drop}
func _ordered_offsets(radius: int) -> Array:
	if _offsets.has(radius): return _offsets[radius]
	var result: Array[Vector2i]=[]
	for y in range(-radius,radius+1):
		for x in range(-radius,radius+1):
			var offset:=Vector2i(x,y)
			if offset.length_squared()<=radius*radius: result.append(offset)
	result.sort_custom(func(a,b):
		var first: int=a.length_squared()
		var second: int=b.length_squared()
		return a.y<b.y or (a.y==b.y and a.x<b.x) if first==second else first<second)
	_offsets[radius]=result
	return result
func find_placement(resource: ResourceType.Type, origin: Vector2i, radius: int, allowed: Callable = Callable(), reachable: Callable = Callable(), excluded: Array = []) -> Variant:
	if not _stack_mode or resource not in ResourceType.Type.values() or radius<0 or radius>Balance.GROUND_WORKER_PLACEMENT_RADIUS: return null
	for offset in _ordered_offsets(radius):
		var cell: Vector2i=origin+offset
		if cell in excluded or not _valid_cell(cell): continue
		var drop:=get_at(cell)
		if drop!=null and (drop.resource_type!=resource or drop.amount>=drop.capacity): continue
		if allowed.is_valid() and not allowed.call(cell): continue
		if reachable.is_valid() and not reachable.call(cell): continue
		return cell
	return null
func place_near(resource: ResourceType.Type, quantity: int, origin: Vector2i, mode: PlacementMode, allowed: Callable = Callable(), reachable: Callable = Callable()) -> Dictionary:
	var result:={"placed":0,"discarded":0,"remaining":quantity,"stack_ids":[]}
	if not _stack_mode or not is_instance_valid(_clock) or quantity<=0 or resource not in ResourceType.Type.values() or mode not in PlacementMode.values(): return result
	if mode==PlacementMode.WORKER and quantity!=1: return result
	var radius: int=Balance.GROUND_NATURAL_PLACEMENT_RADIUS if mode==PlacementMode.NATURAL else Balance.GROUND_WORKER_PLACEMENT_RADIUS
	var tried: Array=[]
	while result.remaining>0:
		var cell: Variant=find_placement(resource,origin,radius,allowed,reachable,tried)
		if cell==null: break
		tried.append(cell) # A reentrant callback cannot trap the batch on one candidate.
		var placed:=try_place(resource,result.remaining,cell)
		result.placed+=placed.placed
		result.remaining=placed.remaining
		if placed.placed>0: result.stack_ids.append(placed.stack.id)
	result.discarded=result.remaining # Both approved modes allow destruction of new overflow.
	result.remaining=0
	return result
