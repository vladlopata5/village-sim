extends RefCounted
## Local quantities and reservations. Reservations never transfer resources.
const ResourceType = preload("res://scripts/resource_type.gd")
signal changed(resource: ResourceType.Type, amount: int)
signal availability_changed(resource: ResourceType.Type, available_amount: int)
var owner_id: StringName
var _allowed_resource_types: Array = [] # Empty means unrestricted; capacities still required.
var _amounts: Dictionary = {}
var _capacity_per_resource: Dictionary = {}
var _reserved_out: Dictionary = {}
var _reserved_in: Dictionary = {}

func _init(owner: StringName) -> void:
	owner_id = owner

func set_allowed_resource_types(types: Array) -> bool:
	for resource in _capacity_per_resource:
		if not types.is_empty() and resource not in types and (get_amount(resource) > 0 or get_reserved_out(resource) > 0 or get_reserved_in(resource) > 0): return false
	_allowed_resource_types = types.duplicate()
	return true

func allows_resource(resource: ResourceType.Type) -> bool:
	return _allowed_resource_types.is_empty() or resource in _allowed_resource_types

func set_capacity(resource: ResourceType.Type, capacity: int) -> bool:
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
	return get_capacity(resource) - get_amount(resource)

func get_available_free_capacity(resource: ResourceType.Type) -> int:
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
	return true

func release_out(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_reserved_out(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) - amount
	_emit_availability(resource, previous_available)
	return true

func reserve_in(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_available_free_capacity(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) + amount
	return true

func release_in(resource: ResourceType.Type, amount: int) -> bool:
	if not allows_resource(resource) or amount <= 0 or amount > get_reserved_in(resource):
		return false
	_reserved_in[resource] = get_reserved_in(resource) - amount
	return true

func take_reserved(resource: ResourceType.Type, amount: int) -> bool:
	if amount <= 0 or amount > get_reserved_out(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_out[resource] = get_reserved_out(resource) - amount
	_amounts[resource] = get_amount(resource) - amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	return true

func add_reserved(resource: ResourceType.Type, amount: int) -> bool:
	if not allows_resource(resource) or amount <= 0 or amount > get_reserved_in(resource):
		return false
	var previous_available := get_available_amount(resource)
	_reserved_in[resource] = get_reserved_in(resource) - amount
	_amounts[resource] = get_amount(resource) + amount
	_emit_availability(resource, previous_available)
	changed.emit(resource, get_amount(resource))
	return true

func _emit_availability(resource: ResourceType.Type, previous_available: int) -> void:
	var available := get_available_amount(resource)
	if available != previous_available: availability_changed.emit(resource, available)
