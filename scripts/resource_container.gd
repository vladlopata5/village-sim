extends RefCounted
## Local quantities and reservations. Reservations never transfer resources.
const ResourceType = preload("res://scripts/resource_type.gd")
const Categories = preload("res://scripts/resource_category.gd")
const Catalog = preload("res://scripts/resource_catalog.gd")
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
var _removed := false
var _capacity_per_resource: Dictionary = {} # Production buffers only.
var _category_quotas: Dictionary = {}
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

func configure_warehouse(capacity: Variant, category_quotas: Dictionary) -> bool:
	# Opt in once. Existing stock/promises must physically fit, even with lower quotas.
	if is_warehouse() or typeof(capacity) != TYPE_INT or capacity < 0: return false
	if get_total_amount() + get_total_reserved_in() > capacity or not _valid_category_quotas(category_quotas,capacity): return false
	_shared_capacity = capacity
	_category_quotas = category_quotas.duplicate()
	_capacity_per_resource.clear()
	_notify_quotas_changed()
	return true

func set_category_quota(category: Variant, quota: Variant) -> bool:
	return set_category_quotas({category:quota})

func set_category_quotas(updates: Dictionary) -> bool:
	# Patch all requested quotas atomically; unspecified categories retain their quota.
	if not is_warehouse(): return false
	var next := _category_quotas.duplicate()
	for category in updates: next[category] = updates[category]
	if not _valid_category_quotas(next,_shared_capacity): return false
	if next == _category_quotas: return true
	_category_quotas = next
	_notify_quotas_changed()
	return true

func _valid_category_quotas(quotas: Dictionary, capacity: int) -> bool:
	var allocated := 0
	for category in quotas:
		if not supports_category(category): return false
		var quota: Variant = quotas[category]
		if typeof(quota) != TYPE_INT or quota < 0 or quota > capacity - allocated: return false
		allocated += quota
	return true

func get_resource_category(resource: int) -> int:
	return Catalog.get_category(resource)

func supports_category(category: Variant) -> bool:
	if typeof(category) != TYPE_INT or category not in Categories.Type.values(): return false
	for resource in ResourceType.Type.values():
		if allows_resource(resource) and get_resource_category(resource) == category: return true
	return false

func get_category_quota(category: Variant) -> int:
	if not is_warehouse() or typeof(category) != TYPE_INT or category not in Categories.Type.values(): return 0
	return _category_quotas.get(category,0)

func _category_total(values: Dictionary, category: int) -> int:
	if category not in Categories.Type.values(): return 0
	var total := 0
	for resource: int in values:
		if get_resource_category(resource) == category: total += values[resource]
	return total

func get_category_amount(category: int) -> int:
	return _category_total(_amounts,category)

func get_category_reserved_in(category: int) -> int:
	return _category_total(_reserved_in,category)

func get_category_reserved_out(category: int) -> int:
	return _category_total(_reserved_out,category)

func get_category_available_capacity(category: int) -> int:
	if not is_warehouse(): return 0
	return maxi(0,mini(get_category_quota(category)-get_category_amount(category)-get_category_reserved_in(category),_shared_capacity-get_total_amount()-get_total_reserved_in()))

func get_category_contents(category: int) -> Dictionary:
	# A detached view of concrete physical stock, never a second ledger.
	var contents: Dictionary = {}
	for resource: int in _amounts:
		if get_resource_category(resource) == category and get_amount(resource)>0: contents[resource] = get_amount(resource)
	return contents

func get_category_surplus(category: int) -> int:
	if not is_warehouse(): return 0
	return maxi(0,get_category_amount(category)-get_category_quota(category)-get_category_reserved_out(category))

func get_surplus_amount(resource: ResourceType.Type) -> int:
	return mini(get_available_amount(resource),get_category_surplus(get_resource_category(resource)))

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
	var limits: Dictionary = _category_quotas if is_warehouse() else _capacity_per_resource
	for capacity in limits.values(): total += capacity
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
	# Concrete-type query retained for legacy admission/needs. Not per-type warehouse space.
	if is_warehouse(): return get_category_quota(get_resource_category(resource)) if allows_resource(resource) else 0
	return _capacity_per_resource.get(resource, 0) if allows_resource(resource) else 0

func get_amount(resource: ResourceType.Type) -> int:
	return _amounts.get(resource, 0)

func get_reserved_out(resource: ResourceType.Type) -> int:
	return _reserved_out.get(resource, 0)

func get_reserved_in(resource: ResourceType.Type) -> int:
	return _reserved_in.get(resource, 0)

func get_supported_resource_types() -> Array[int]:
	# Capability for queued target actions: stock and temporary access may be absent.
	var types: Array = _capacity_per_resource.keys()
	if is_warehouse(): types = _allowed_resource_types if not _allowed_resource_types.is_empty() else ResourceType.Type.values()
	var result: Array[int] = []
	for resource: int in types:
		if allows_resource(resource) and (is_warehouse() or get_capacity(resource)>0): result.append(resource)
	return result

func get_available_resource_types() -> Array[int]:
	# Local concrete contents only: no scan of all catalog types or world stock.
	var result: Array[int] = []
	for resource: int in _amounts:
		if allows_resource(resource) and get_available_amount(resource)>0: result.append(resource)
	result.sort()
	return result

func get_available_amount(resource: ResourceType.Type) -> int:
	return get_amount(resource) - get_reserved_out(resource)

func get_free_capacity(resource: ResourceType.Type) -> int:
	if is_warehouse():
		if not allows_resource(resource): return 0
		var category := get_resource_category(resource)
		return maxi(0,mini(get_category_quota(category)-get_category_amount(category),get_shared_free_capacity()))
	return get_capacity(resource) - get_amount(resource)

func get_available_free_capacity(resource: ResourceType.Type) -> int:
	if is_warehouse():
		if not allows_resource(resource): return 0
		return get_category_available_capacity(get_resource_category(resource))
	return get_free_capacity(resource) - get_reserved_in(resource)

func add(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
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
	if _removed: return false
	if not has_resource(resource, amount):
		return false
	var previous_available := get_available_amount(resource)
	_amounts[resource] = get_amount(resource) - amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	return true

func reserve_out(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
	if not has_resource(resource, amount):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) + amount
	_emit_availability(resource, previous_available)
	reservations_changed.emit(resource)
	return true

func release_out(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
	if amount <= 0 or amount > get_reserved_out(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) - amount
	_emit_availability(resource, previous_available)
	reservations_changed.emit(resource)
	return true

func reserve_in(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
	if amount <= 0 or amount > get_available_free_capacity(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) + amount
	reservations_changed.emit(resource)
	return true

func release_in(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
	if not allows_resource(resource) or amount <= 0 or amount > get_reserved_in(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) - amount
	reservations_changed.emit(resource)
	return true

func take_reserved(resource: ResourceType.Type, amount: int) -> bool:
	if _removed: return false
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
	if _removed: return false
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
	if _removed: return false
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

func drain_for_removal() -> Dictionary:
	if _removed or get_total_reserved_in()>0: return {"ok":false,"contents":{}}
	for amount in _reserved_out.values():
		if amount>0: return {"ok":false,"contents":{}}
	var contents: Dictionary = {}
	for resource in _amounts:
		if _amounts[resource]>0: contents[resource] = _amounts[resource]
	_removed = true
	_amounts.clear() # Every quantity commits before the first synchronous observer.
	for resource in contents:
		availability_changed.emit(resource,0)
		changed.emit(resource,0)
	return {"ok":true,"contents":contents}
