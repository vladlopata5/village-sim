extends RefCounted
## Stack data. Unplaced legacy drops keep their old exclusive one-unit API until E1.2.
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const LIFETIME_MINUTES := Balance.GROUND_STACK_LIFETIME_MINUTES
signal availability_changed
var id: StringName:
	set(value):
		if id.is_empty(): id=value
var resource_type: ResourceType.Type:
	set(value):
		if _cell==null: resource_type=value
var _amount: int
var amount: int:
	get: return _amount
	set(value):
		# Existing fixtures may resize an unplaced drop. Cell stacks mutate only via owner APIs.
		if not is_stack() and value>=reserved_total(): _amount=maxi(0,value)
var capacity: int:
	get: return Balance.GROUND_STONE_STACK_CAPACITY if resource_type==ResourceType.Type.STONE else Balance.GROUND_STACK_CAPACITY
var _cell: Variant = null
var cell: Variant:
	get: return _cell
var owner_callback: Callable
var _reservations: Dictionary = {}
var reservations: Dictionary:
	get: return _reservations.duplicate()
# Compatibility inspection only; stack callers must use reserved_amount(owner).
var reservation_owner_id: StringName:
	get: return _reservations.keys()[0] if not _reservations.is_empty() else &""
var world_position: Vector2:
	set(value):
		if _cell!=null or world_position==value: return
		world_position=value
		availability_changed.emit()
var created_at: int
var lifetime: int = LIFETIME_MINUTES
func _init(resource: ResourceType.Type, quantity: int, position: Vector2, minute: int) -> void:
	resource_type=resource
	_amount=maxi(0,quantity)
	world_position=position
	created_at=minute
func is_stack() -> bool: return _cell!=null
func age_minutes(now: int) -> int: return maxi(0,now-created_at)
func reserved_amount(owner: StringName) -> int: return int(_reservations.get(owner,0))
func reserved_total() -> int:
	var total:=0
	for quantity in _reservations.values(): total+=int(quantity)
	return total
func available_amount() -> int:
	if not is_stack() and not _reservations.is_empty(): return 0
	return amount-reserved_total()
func reserve(owner: StringName, quantity: int = 1) -> bool:
	if owner.is_empty() or quantity<=0 or _reservations.has(owner) or available_amount()<quantity: return false
	if not is_stack() and not _reservations.is_empty(): return false # Legacy full-drop exclusion.
	_reservations[owner]=quantity
	availability_changed.emit()
	return true
func release(owner: StringName, quantity: int = -1) -> bool:
	var owned:=reserved_amount(owner)
	if owned<=0 or quantity==0 or quantity < -1 or quantity>owned: return false
	var released:=owned if quantity==-1 else quantity
	if released==owned: _reservations.erase(owner)
	else: _reservations[owner]=owned-released
	availability_changed.emit()
	return true
# Owner commits registry updates before emitting notifications for a final pickup.
func _take_reserved(owner: StringName, quantity: int) -> bool:
	var owned:=reserved_amount(owner)
	if owner.is_empty() or quantity<=0 or owned<quantity or amount<quantity: return false
	_amount-=quantity
	if owned==quantity: _reservations.erase(owner)
	else: _reservations[owner]=owned-quantity
	return true
func _configure_cell(value: Vector2i, position: Vector2) -> bool:
	if is_stack() or amount<1 or amount>capacity: return false
	world_position=position
	_cell=value
	return true
func _add_amount(quantity: int, now: int) -> bool:
	if not is_stack() or quantity<=0 or quantity>capacity-amount: return false
	_amount+=quantity
	created_at=now # Replenishment renews the whole stack, including owned units.
	availability_changed.emit()
	return true
