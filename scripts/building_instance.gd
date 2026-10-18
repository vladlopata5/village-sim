extends RefCounted
## One entity for the entire lifecycle; changing state never replaces its identity.
const Definition = preload("res://scripts/building_definition.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
const Batch = preload("res://scripts/production_batch.gd")
const Balance = preload("res://scripts/balance_config.gd")
enum State { UNDER_CONSTRUCTION, BUILT }
var id: StringName
var definition: Definition
var position: Vector2
var work_area_override_id: StringName = &"" # Per-instance reference; empty uses definition radius.
# Orientation is fixed on placement; only quarter turns are supported.
var quarter_turns: int = 0:
	set(value): quarter_turns = posmod(value, 4)
signal construction_changed
var construction_revision := 0 # Lazy Builder identity, not an assignment ledger.
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
		_notify_construction_changed()
var resources: ResourceContainer
var _production_batches: Array[Batch] = []
var production_batches: Array[Batch]:
	get: return _production_batches.duplicate()
var production_removed := false
var _next_batch_id := 1
var production_worker_id: String:
	get: return _production_batches[0].worker_id if not _production_batches.is_empty() else ""
var _simple_production_progress := 0 # Original gatherer/non-recipe state is unchanged.
var production_progress: int:
	get:
		if definition.production_recipe == null: return _simple_production_progress
		return _production_batches[0].progress if not _production_batches.is_empty() and not _production_batches[0].is_terminal() else 0
	set(value):
		if definition.production_recipe == null: _simple_production_progress = value

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
func prepare_production_batch(worker: String) -> Batch:
	# F5a deliberately permits one batch. The collection keeps future slots independent.
	if production_removed or not is_built() or definition.production_recipe == null or not _production_batches.is_empty(): return null
	var created := Batch.new(StringName("%s:batch_%04d" % [id,_next_batch_id]),definition.production_recipe,resources)
	_next_batch_id += 1
	_production_batches.append(created) # Publish identity before reservations emit signals.
	if not created.prepare(worker):
		created.cancel()
		retire_production_batch(created)
		return null
	return created

func owns_production_batch(batch: Batch) -> bool:
	return not production_removed and batch in _production_batches

func resumable_production_batch() -> Batch:
	if production_removed: return null
	for batch in _production_batches:
		if batch.can_resume(): return batch
	return null

func retire_production_batch(batch: Batch) -> void:
	if batch.is_terminal(): _production_batches.erase(batch)

func dispose_production() -> void:
	if production_removed: return
	production_removed = true
	var previous := _production_batches
	_production_batches = []
	for batch in previous: batch.cancel()

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
	_notify_construction_changed()
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
	_notify_construction_changed()
	return true
func release_builder_slot(resident_id: String) -> bool:
	if resident_id not in _active_builder_ids: return false
	_active_builder_ids.erase(resident_id)
	_notify_construction_changed()
	return true
func can_complete_construction() -> bool:
	return not is_built() and are_construction_materials_complete() and construction_progress >= definition.construction_work_required
func complete_construction() -> bool:
	if not can_complete_construction(): return false
	_state = State.BUILT
	_active_builder_ids.clear()
	_notify_construction_changed()
	return true

func get_construction_reserved_in(resource: int) -> int:
	return _construction_reserved_in.get(resource, 0)
func get_uncovered_construction_amount(resource: int) -> int:
	return maxi(get_missing_amount(resource) - get_construction_reserved_in(resource), 0)
func reserve_construction_material(resource: int, amount: int) -> bool:
	if is_built() or amount <= 0 or amount > get_uncovered_construction_amount(resource): return false
	_construction_reserved_in[resource] = get_construction_reserved_in(resource) + amount
	_notify_construction_changed()
	return true
func release_construction_material(resource: int, amount: int) -> bool:
	if amount <= 0 or amount > get_construction_reserved_in(resource): return false
	_construction_reserved_in[resource] -= amount
	_notify_construction_changed()
	return true
func deliver_reserved_construction_material(resource: int, amount: int) -> bool:
	if is_built() or amount <= 0 or amount > get_construction_reserved_in(resource) or amount > get_missing_amount(resource): return false
	_construction_reserved_in[resource] -= amount
	_construction_delivered[resource] = get_delivered_amount(resource) + amount
	_notify_construction_changed()
	return true
func get_construction_material_ratio() -> float:
	var required := 0
	var delivered := 0
	for resource in definition.construction_requirements:
		required += get_required_amount(resource)
		delivered += mini(get_delivered_amount(resource), get_required_amount(resource))
	return float(delivered) / required if required > 0 else 1.0

func _notify_construction_changed() -> void:
	construction_revision += 1
	construction_changed.emit()
