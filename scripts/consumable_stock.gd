extends RefCounted
## Building-owned numerical units; physical inputs are never stored here.
signal changed
var id: StringName
var display_name: String
var amount := 0
var capacity: int
var conversions: Dictionary
var _incoming: Dictionary = {} # Physical items, all converted units share capacity.
var _payments: Dictionary = {} # Batch identity -> units.
func _init(key: StringName, label: String, maximum: int, materials: Dictionary) -> void:
	id=key; display_name=label; capacity=maxi(0,maximum); conversions=materials.duplicate()
func yield_for(resource: int) -> int: return maxi(0,int(conversions.get(resource,0)))
func incoming_units() -> int:
	var total := 0
	for resource in _incoming: total+=int(_incoming[resource])*yield_for(resource)
	return total
func reserved_units() -> int:
	var total := 0
	for units in _payments.values(): total+=units
	return total
func available() -> int: return amount-reserved_units()
func room_for(resource: int) -> int:
	var units := yield_for(resource)
	return floori(float(capacity-amount-incoming_units())/units) if units>0 else 0
func incoming(resource: int) -> int: return int(_incoming.get(resource,0))
func reserve_in(resource: int, quantity: int) -> bool:
	if quantity<=0 or room_for(resource)<quantity:return false
	_incoming[resource]=incoming(resource)+quantity
	changed.emit();return true
func release_in(resource: int, quantity: int) -> bool:
	if quantity<=0 or incoming(resource)<quantity:return false
	_incoming[resource]=incoming(resource)-quantity
	changed.emit();return true
func deliver(resource: int, quantity: int) -> bool:
	if quantity<=0 or incoming(resource)<quantity or yield_for(resource)<=0 or amount+quantity*yield_for(resource)>capacity:return false
	_incoming[resource]=incoming(resource)-quantity
	amount+=quantity*yield_for(resource) # Commit before any synchronous observer.
	changed.emit();return true
func reserve(owner: StringName, units: int) -> bool:
	if owner.is_empty() or units<=0 or _payments.has(owner) or available()<units:return false
	_payments[owner]=units;changed.emit();return true
func holds(owner: StringName, units: int) -> bool: return units>0 and int(_payments.get(owner,0))==units and amount>=reserved_units()
func release(owner: StringName) -> void:
	if _payments.erase(owner):changed.emit()
func commit_payment(owner: StringName) -> bool:
	# Only the validated ProductionBatch transaction calls this; deliberately silent.
	if not holds(owner,int(_payments.get(owner,0))):return false
	amount-=int(_payments[owner]);_payments.erase(owner)
	return true
