extends RefCounted
## Local quantities and reservations. Reservations never transfer resources.
const ResourceType = preload("res://scripts/resource_type.gd")
signal reservations_changed(resource: ResourceType.Type)
signal changed(resource: ResourceType.Type, amount: int)
signal availability_changed(resource: ResourceType.Type, available_amount: int)
signal quotas_changed
var quota_revision := 0
var _shared_capacity := -1 # Negative means the original per-resource container mode.
var shared_capacity: int:
	get: return _shared_capacity
var owner_id: StringName
var _allowed_resource_types: Array = [] # Empty means unrestricted; capacities still required.
var _amounts: Dictionary = {}
var _capacity_per_resource: Dictionary = {}
var _reserved_out: Dictionary = {}
var _reserved_in: Dictionary = {}

func _init(owner: StringName) -> void:
	owner_id = owner

func set_allowed_resource_types(types: Array) -> bool:
	var configured: Array = _capacity_per_resource.keys()
	if is_warehouse():
		# A missing quota means zero, not permission to hide existing stock/promises.
		for resource in _amounts.keys() + _reserved_in.keys() + _reserved_out.keys():
			if resource not in configured: configured.append(resource)
	for resource in configured:
		if not types.is_empty() and resource not in types and (get_amount(resource) > 0 or get_reserved_out(resource) > 0 or get_reserved_in(resource) > 0): return false
	_allowed_resource_types = types.duplicate()
	return true

func allows_resource(resource: ResourceType.Type) -> bool:
	return _allowed_resource_types.is_empty() or resource in _allowed_resource_types

func is_warehouse() -> bool:
	return _shared_capacity >= 0

func configure_warehouse(capacity: Variant, quotas: Dictionary) -> bool:
	# Opt in once. Existing stock/promises must physically fit, even with lower quotas.
	if is_warehouse() or typeof(capacity) != TYPE_INT or capacity < 0: return false
	if get_total_amount() + get_total_reserved_in() > capacity or not _valid_quotas(quotas,capacity): return false
	_shared_capacity = capacity
	_capacity_per_resource = quotas.duplicate()
	_notify_quotas_changed()
	return true

func set_quota(resource: Variant, quota: Variant) -> bool:
	return set_quotas({resource:quota})

func set_quotas(updates: Dictionary) -> bool:
	# Patch all requested quotas atomically; unspecified resources retain their quota.
	if not is_warehouse(): return false
	var next := _capacity_per_resource.duplicate()
	for resource in updates: next[resource] = updates[resource]
	if not _valid_quotas(next,_shared_capacity): return false
	if next == _capacity_per_resource: return true
	_capacity_per_resource = next
	_notify_quotas_changed()
	return true

func _valid_quotas(quotas: Dictionary, capacity: int) -> bool:
	var allocated := 0
	for resource in quotas:
		if typeof(resource) != TYPE_INT or resource not in ResourceType.Type.values() or not allows_resource(resource): return false
		var quota: Variant = quotas[resource]
		if typeof(quota) != TYPE_INT or quota < 0 or quota > capacity - allocated: return false
		allocated += quota
	return true

func _notify_quotas_changed() -> void:
	quota_revision += 1
	quotas_changed.emit() # Local data notification only; never requests an AI decision.

func get_total_amount() -> int:
	var total := 0
	for amount in _amounts.values(): total += amount
	return total

func get_total_reserved_in() -> int:
	var total := 0
	for amount in _reserved_in.values(): total += amount
	return total

func get_allocated_capacity() -> int:
	var total := 0
	for capacity in _capacity_per_resource.values(): total += capacity
	return total

func get_shared_free_capacity() -> int:
	return maxi(0,_shared_capacity-get_total_amount()) if is_warehouse() else -1

func set_capacity(resource: ResourceType.Type, capacity: int) -> bool:
	# Warehouse edits use the strict, atomic quota API; cannot bypass the shared cap.
	if is_warehouse(): return false
	if not allows_resource(resource) or capacity < 0 or capacity < get_amount(resource) + get_reserved_in(resource):
		return false
	_capacity_per_resource[resource] = capacity
	return true

func get_capacity(resource: ResourceType.Type) -> int:
	return _capacity_per_resource.get(resource, 0) if allows_resource(resource) else 0

func get_amount(resource: ResourceType.Type) -> int:
	return _amounts.get(resource, 0)

func get_reserved_out(resource: ResourceType.Type) -> int:
	return _reserved_out.get(resource, 0)

func get_reserved_in(resource: ResourceType.Type) -> int:
	return _reserved_in.get(resource, 0)

func get_available_amount(resource: ResourceType.Type) -> int:
	return get_amount(resource) - get_reserved_out(resource)

func get_free_capacity(resource: ResourceType.Type) -> int:
	if is_warehouse(): return maxi(0,mini(get_capacity(resource)-get_amount(resource),get_shared_free_capacity()))
	return get_capacity(resource) - get_amount(resource)

func get_available_free_capacity(resource: ResourceType.Type) -> int:
	if is_warehouse():
		var individual := get_capacity(resource)-get_amount(resource)-get_reserved_in(resource)
		var shared := _shared_capacity-get_total_amount()-get_total_reserved_in()
		return maxi(0,mini(individual,shared))
	return get_free_capacity(resource) - get_reserved_in(resource)

func add(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_available_free_capacity(resource):
		return false
	var previous_available := get_available_amount(resource)
	_amounts[resource] = get_amount(resource) + amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	return true

func has_resource(resource: ResourceType.Type, amount: int) -> bool:
	return amount > 0 and get_available_amount(resource) >= amount

func try_take(resource: ResourceType.Type, amount: int) -> bool:
	if not has_resource(resource, amount):
		return false
	var previous_available := get_available_amount(resource)
	_amounts[resource] = get_amount(resource) - amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	return true

func reserve_out(resource: ResourceType.Type, amount: int) -> bool:
	if not has_resource(resource, amount):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) + amount
	_emit_availability(resource, previous_available)
	reservations_changed.emit(resource)
	return true

func release_out(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_reserved_out(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) - amount
	_emit_availability(resource, previous_available)
	reservations_changed.emit(resource)
	return true

func reserve_in(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_available_free_capacity(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) + amount
	reservations_changed.emit(resource)
	return true

func release_in(resource: ResourceType.Type, amount: int) -> bool:
	if not allows_resource(resource) or amount <= 0 or amount > get_reserved_in(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) - amount
	reservations_changed.emit(resource)
	return true

func take_reserved(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_reserved_out(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) - amount
	_amounts[resource] = get_amount(resource) - amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	reservations_changed.emit(resource)
	return true

func add_reserved(resource: ResourceType.Type, amount: int) -> bool:
	if not allows_resource(resource) or amount <= 0 or amount > get_reserved_in(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_in[resource] = get_reserved_in(resource) - amount
	_amounts[resource] = get_amount(resource) + amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	reservations_changed.emit(resource)
	return true

func _emit_availability(resource: ResourceType.Type, previous_available: int) -> void:
	var available := get_available_amount(resource)
	if available != previous_available: availability_changed.emit(resource, available)


func transform_reserved(inputs: Dictionary, outputs: Dictionary) -> bool:
	# Validate the entire local transaction before signals can invoke other consumers.
	var types: Array = inputs.keys()
	for resource in outputs:
		if resource not in types: types.append(resource)
	for resource in types:
		var consumed: int = inputs.get(resource,0)
		var produced: int = outputs.get(resource,0)
		if consumed < 0 or produced < 0 or consumed > get_reserved_out(resource) or produced > get_reserved_in(resource): return false
		var next_amount := get_amount(resource)-consumed+produced
		if not allows_resource(resource) or next_amount < get_reserved_out(resource)-consumed or next_amount+get_reserved_in(resource)-produced > get_capacity(resource): return false
	var previous: Dictionary = {}
	for resource in types:
		previous[resource] = get_available_amount(resource)
		_amounts[resource] = get_amount(resource)-int(inputs.get(resource,0))+int(outputs.get(resource,0))
		_reserved_out[resource] = get_reserved_out(resource)-int(inputs.get(resource,0))
		_reserved_in[resource] = get_reserved_in(resource)-int(outputs.get(resource,0))
	# All quantities/reservations are already final even inside synchronous callbacks.
	for resource in types:
		_emit_availability(resource,previous[resource])
		changed.emit(resource,get_amount(resource))
		reservations_changed.emit(resource)
	return true
