extends RefCounted
## One entity for the entire lifecycle; changing state never replaces its identity.
const Definition = preload("res://scripts/building_definition.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
const Balance = preload("res://scripts/balance_config.gd")
enum State { UNDER_CONSTRUCTION, BUILT }
var id: StringName
var definition: Definition
var position: Vector2
signal construction_changed
var _state: State = State.BUILT
var state: State:
	get: return _state
	set(value):
		# Direct writes cannot bypass completion or move a built instance backwards.
		if value == State.BUILT: complete_construction()
var _construction_reserved_in: Dictionary = {}
var _construction_delivered: Dictionary = {}
var construction_delivered: Dictionary:
	get: return _construction_delivered.duplicate()
var _active_builder_ids: Array[String] = []
var active_builder_ids: Array[String]:
	get: return _active_builder_ids.duplicate()
var construction_progress: int = 0:
	set(value):
		if is_built(): return
		var clamped := clampi(value, 0, definition.construction_work_required)
		if clamped == construction_progress: return
		construction_progress = clamped
		construction_changed.emit()
var resources: ResourceContainer
var production_progress: int = 0
var logistics_weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT
# Compatibility accessors keep existing systems using the same instance data.
var display_name: String:
	get: return definition.display_name
var type: int:
	get: return definition.type
func _init(instance_id: StringName, building_definition: Definition, world_position: Vector2 = Vector2.ZERO, initial_state: State = State.BUILT) -> void:
	id = instance_id
	definition = building_definition
	position = world_position
	_state = initial_state
	for resource in definition.construction_requirements:
		_construction_delivered[resource] = 0
	resources = ResourceContainer.new(id)
func is_built() -> bool: return state == State.BUILT
func footprint() -> Rect2: return Rect2(position - definition.size / 2.0, definition.size)

func get_required_amount(resource: int) -> int:
	return definition.construction_requirements.get(resource, 0)
func get_delivered_amount(resource: int) -> int:
	return _construction_delivered.get(resource, 0)
func get_missing_amount(resource: int) -> int:
	return maxi(get_required_amount(resource) - get_delivered_amount(resource), 0)
func add_delivered_material(resource: int, amount: int) -> bool:
	# Caller records actual arrival only. No reservation/warehouse lookup or transfer here.
	if is_built() or amount <= 0 or amount > get_uncovered_construction_amount(resource): return false
	_construction_delivered[resource] = get_delivered_amount(resource) + amount
	construction_changed.emit()
	return true
func are_construction_materials_complete() -> bool:
	for resource in definition.construction_requirements:
		if get_delivered_amount(resource) < get_required_amount(resource): return false
	return true
func get_construction_progress_ratio() -> float:
	if definition.construction_work_required == 0: return 1.0
	return float(construction_progress) / definition.construction_work_required
func add_construction_work(minutes: int) -> bool:
	if is_built() or minutes <= 0 or construction_progress >= definition.construction_work_required: return false
	construction_progress += minutes
	return true
func has_free_builder_slot() -> bool:
	return not is_built() and _active_builder_ids.size() < definition.max_builders
func claim_builder_slot(resident_id: String) -> bool:
	if resident_id.is_empty() or resident_id in _active_builder_ids or not has_free_builder_slot(): return false
	_active_builder_ids.append(resident_id)
	construction_changed.emit()
	return true
func release_builder_slot(resident_id: String) -> bool:
	if resident_id not in _active_builder_ids: return false
	_active_builder_ids.erase(resident_id)
	construction_changed.emit()
	return true
func can_complete_construction() -> bool:
	return not is_built() and are_construction_materials_complete() and construction_progress >= definition.construction_work_required
func complete_construction() -> bool:
	if not can_complete_construction(): return false
	_state = State.BUILT
	_active_builder_ids.clear()
	construction_changed.emit()
	return true

func get_construction_reserved_in(resource: int) -> int:
	return _construction_reserved_in.get(resource, 0)
func get_uncovered_construction_amount(resource: int) -> int:
	return maxi(get_missing_amount(resource) - get_construction_reserved_in(resource), 0)
func reserve_construction_material(resource: int, amount: int) -> bool:
	if is_built() or amount <= 0 or amount > get_uncovered_construction_amount(resource): return false
	_construction_reserved_in[resource] = get_construction_reserved_in(resource) + amount
	construction_changed.emit()
	return true
func release_construction_material(resource: int, amount: int) -> bool:
	if amount <= 0 or amount > get_construction_reserved_in(resource): return false
	_construction_reserved_in[resource] -= amount
	construction_changed.emit()
	return true
func deliver_reserved_construction_material(resource: int, amount: int) -> bool:
	if is_built() or amount <= 0 or amount > get_construction_reserved_in(resource) or amount > get_missing_amount(resource): return false
	_construction_reserved_in[resource] -= amount
	_construction_delivered[resource] = get_delivered_amount(resource) + amount
	construction_changed.emit()
	return true
func get_construction_material_ratio() -> float:
	var required := 0
	var delivered := 0
	for resource in definition.construction_requirements:
		required += get_required_amount(resource)
		delivered += mini(get_delivered_amount(resource), get_required_amount(resource))
	return float(delivered) / required if required > 0 else 1.0
