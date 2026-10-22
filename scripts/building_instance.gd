extends RefCounted
## One entity for the entire lifecycle; changing state never replaces its identity.
const Definition = preload("res://scripts/building_definition.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
const Batch = preload("res://scripts/production_batch.gd")
const Balance = preload("res://scripts/balance_config.gd")
enum State { UNDER_CONSTRUCTION, BUILT, REMOVED }
enum WorkDirection { BUILD, DEMOLISH }
var work_direction := WorkDirection.BUILD
var previously_built := false
var work_paused := false # Owned cleanup/inside occupants must finish before work resumes.
var removal_started := false
var direction_revision := 0
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
var animal_housing: RefCounted
var consumable_stocks: Dictionary = {}
var consumable_receivers: Dictionary = {}
var resources: ResourceContainer
var _production_batches: Array[Batch] = []
var production_batches: Array[Batch]:
	get: return _production_batches.duplicate()
var production_revision := 0
var supply = preload("res://scripts/production_supply.gd").new(self)
var production_removed := false
var _next_batch_id := 1
var production_worker_id: String:
	get: return _production_batches[0].worker_id if not _production_batches.is_empty() else ""
var _simple_production_progress := 0 # Original gatherer/non-recipe state is unchanged.
var production_progress: int:
	get:
		if definition.production_recipe == null: return _simple_production_progress
		return _production_batches[0].progress if _production_batches.size()==1 and not _production_batches[0].is_terminal() else 0
	set(value):
		if definition.production_recipe == null: _simple_production_progress = value

signal logistics_policy_changed
var _stock_targets: Dictionary = {}
var logistics_weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT
# Compatibility accessors keep existing systems using the same instance data.
var display_name: String:
	get: return definition.display_name
var type: int:
	get: return definition.type
func is_structural_work() -> bool:
	return _state == State.UNDER_CONSTRUCTION and not work_paused and not removal_started
func needs_materials() -> bool:
	return not previously_built and work_direction == WorkDirection.BUILD
func ready_for_structural_work() -> bool:
	return not needs_materials() or are_construction_materials_complete()
func work_remaining() -> int:
	return construction_progress if work_direction == WorkDirection.DEMOLISH else definition.construction_work_required-construction_progress
func ready_for_removal() -> bool:
	return _state == State.UNDER_CONSTRUCTION and work_direction == WorkDirection.DEMOLISH and construction_progress == 0
func set_work_direction(direction: WorkDirection) -> bool:
	if removal_started or _state == State.REMOVED or direction not in WorkDirection.values(): return false
	if not is_built() and work_direction == direction: return false
	if is_built():
		if direction != WorkDirection.DEMOLISH: return false
		previously_built = true
		_state = State.UNDER_CONSTRUCTION
		construction_progress = definition.construction_work_required
	work_paused = true
	work_direction = direction
	direction_revision += 1
	_notify_construction_changed()
	return true
func work_status() -> String:
	if work_direction == WorkDirection.DEMOLISH: return "Демонтаж"
	return "Восстановление" if previously_built and not is_built() else ("Готово" if is_built() else "Строительство")

func _init(instance_id: StringName, building_definition: Definition, world_position: Vector2 = Vector2.ZERO, initial_state: State = State.BUILT) -> void:
	id = instance_id
	definition = building_definition
	_stock_targets = definition.initial_stock_targets.duplicate()
	position = world_position
	_state = initial_state
	if definition.animal_capacity>0: animal_housing=preload("res://scripts/animal_housing.gd").new(self)
	previously_built = initial_state == State.BUILT
	for resource in definition.construction_requirements:
		_construction_delivered[resource] = 0
	resources = ResourceContainer.new(id)
	if is_built(): _configure_resource_buffers()
	for recipe in definition.production_recipes:
		_recipe_settings[recipe.id] = {"mode":ProductionMode.UNLIMITED,"target":0,"produced":0,"revision":0,"order":false}
func _configure_resource_buffers() -> void:
	for key in definition.consumable_definitions:
		if consumable_stocks.has(key):continue
		var row: Dictionary=definition.consumable_definitions[key]
		var stock=preload("res://scripts/consumable_stock.gd").new(key,row.label,row.capacity,row.materials)
		consumable_stocks[key]=stock
		consumable_receivers[key]=preload("res://scripts/consumable_receiver.gd").new(id,stock)
		stock.changed.connect(_on_consumables_changed)

	if definition.resource_capacities.is_empty(): return
	resources.set_allowed_resource_types(definition.resource_capacities.keys())
	for resource in definition.resource_capacities:
		resources.set_capacity(resource,definition.resource_capacities[resource])

func prepare_production_batch(worker: String, recipe_id: StringName = &"") -> Batch:
	var selected := select_production_work(worker)
	if worker.is_empty() or selected.is_empty() or selected.kind!=&"START" or (not recipe_id.is_empty() and selected.recipe_id!=recipe_id): return null
	var recipe = definition.get_production_recipe(selected.recipe_id)
	supply.consume_for_start(recipe.id)
	if not can_start_production(recipe.id): return null
	var created := Batch.new(StringName("%s:batch_%04d" % [id,_next_batch_id]),recipe,resources,consumable_stocks)
	created.order_revision = _recipe_settings[recipe.id].revision
	_next_batch_id += 1
	production_revision += 1
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
	if batch not in _production_batches: return
	production_revision += 1
	if not batch.is_terminal(): return
	if batch.state==Batch.State.COMPLETED:
		var settings: Dictionary = _recipe_settings[batch.recipe_id]
		if settings.order and batch.order_revision==settings.revision:
			settings.produced += batch.output_quantity()
			if settings.produced>=settings.target and settings.mode==ProductionMode.ORDER: settings.mode=ProductionMode.OFF
	_production_batches.erase(batch)

func dispose_production() -> void:
	if production_removed: return
	production_removed = true
	production_revision += 1
	supply.clear()
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
	if not is_structural_work() or not needs_materials() or amount <= 0 or amount > get_uncovered_construction_amount(resource): return false
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
	if not is_structural_work() or minutes <= 0 or work_remaining() <= 0: return false
	construction_progress += -mini(minutes,work_remaining()) if work_direction == WorkDirection.DEMOLISH else mini(minutes,work_remaining())
	return true
func has_free_builder_slot() -> bool:
	return is_structural_work() and _active_builder_ids.size() < definition.max_builders
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
	return is_structural_work() and work_direction == WorkDirection.BUILD and ready_for_structural_work() and construction_progress >= definition.construction_work_required
func complete_construction() -> bool:
	if not can_complete_construction(): return false
	if not previously_built: _configure_resource_buffers()
	previously_built = true
	production_removed = false
	_state = State.BUILT
	_active_builder_ids.clear()
	_notify_construction_changed()
	return true

func get_construction_reserved_in(resource: int) -> int:
	return _construction_reserved_in.get(resource, 0)
func get_uncovered_construction_amount(resource: int) -> int:
	return maxi(get_missing_amount(resource) - get_construction_reserved_in(resource), 0)
func reserve_construction_material(resource: int, amount: int) -> bool:
	if not is_structural_work() or not needs_materials() or amount <= 0 or amount > get_uncovered_construction_amount(resource): return false
	_construction_reserved_in[resource] = get_construction_reserved_in(resource) + amount
	_notify_construction_changed()
	return true
func release_construction_material(resource: int, amount: int) -> bool:
	if amount <= 0 or amount > get_construction_reserved_in(resource): return false
	_construction_reserved_in[resource] -= amount
	_notify_construction_changed()
	return true
func deliver_reserved_construction_material(resource: int, amount: int) -> bool:
	if not is_structural_work() or not needs_materials() or amount <= 0 or amount > get_construction_reserved_in(resource) or amount > get_missing_amount(resource): return false
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

# Local recipe settings and selection; neither a world scheduler nor resource stock.
enum ProductionMode { OFF, UNLIMITED, MAINTAIN, ORDER }
signal production_changed
var _recipe_settings: Dictionary = {}
var _recipe_cursors: Dictionary = {}

func get_recipe_settings(recipe_id: StringName) -> Dictionary:
	if production_removed or not _recipe_settings.has(recipe_id): return {}
	var result: Dictionary = _recipe_settings[recipe_id].duplicate()
	result.mode = get_recipe_mode(recipe_id)
	result.remaining = get_order_remaining(recipe_id)
	result.produced = _order_produced(recipe_id)
	result.excess = maxi(0,result.produced-result.target) if result.order else 0
	return result

func get_recipe_mode(recipe_id: StringName) -> int:
	if production_removed or not _recipe_settings.has(recipe_id): return -1
	var settings: Dictionary = _recipe_settings[recipe_id]
	# A completion callback already sees the committed product before retirement.
	if settings.mode == ProductionMode.ORDER and get_order_remaining(recipe_id)==0: return ProductionMode.OFF
	return settings.mode

func get_order_remaining(recipe_id: StringName) -> int:
	if production_removed or not _recipe_settings.has(recipe_id): return -1
	var settings: Dictionary = _recipe_settings[recipe_id]
	return maxi(0,settings.target-_order_produced(recipe_id)) if settings.order else 0

func _order_produced(recipe_id: StringName) -> int:
	var settings: Dictionary = _recipe_settings[recipe_id]
	var produced: int = settings.produced
	if not settings.order: return 0
	for batch in _production_batches:
		if batch.recipe_id==recipe_id and batch.order_revision==settings.revision and batch.state==Batch.State.COMPLETED:
			produced += batch.output_quantity()
	return produced

func set_recipe_mode(recipe_id: StringName, mode: int, amount: int = 0) -> bool:
	var recipe = definition.get_production_recipe(recipe_id)
	if production_removed or not is_built() or recipe==null or not recipe.is_valid() or not _recipe_settings.has(recipe_id) or mode not in ProductionMode.values() or amount<0: return false
	if mode in [ProductionMode.OFF,ProductionMode.UNLIMITED] and amount!=0: return false
	if mode in [ProductionMode.ORDER,ProductionMode.MAINTAIN] and recipe.counted_product()<0: return false
	var revision: int = _recipe_settings[recipe_id].revision+1
	_recipe_settings[recipe_id] = {"mode":mode,"target":amount,"produced":0,"revision":revision,"order":mode==ProductionMode.ORDER}
	# New ORDER replaces the old remainder; only not-yet-completed work joins it.
	if mode==ProductionMode.ORDER:
		for batch in _production_batches:
			if batch.recipe_id==recipe_id and not batch.is_terminal(): batch.order_revision=revision
	_reconcile_preparations(recipe_id)
	production_revision += 1
	supply.reconcile()
	production_changed.emit()
	return true

func set_maintain_target(recipe_id: StringName, amount: int) -> bool:
	return set_recipe_mode(recipe_id,ProductionMode.MAINTAIN,amount)

func set_production_order(recipe_id: StringName, amount: int) -> bool:
	return set_recipe_mode(recipe_id,ProductionMode.ORDER,amount)

func production_capacity() -> int:
	return maxi(0,definition.worker_capacity)

func _active_batch_count() -> int:
	var count := 0
	for batch in _production_batches:
		if not batch.is_terminal(): count += 1
	return count

func _worker_has_batch(worker: String) -> bool:
	return _production_batches.any(func(batch): return not batch.is_terminal() and batch.worker_id==worker)

func _promised_for_recipe(recipe_id: StringName, paid_only: bool = false) -> int:
	var promised := 0
	for batch in _production_batches:
		if batch.recipe_id==recipe_id and not batch.is_terminal() and (not paid_only or batch.inputs_spent): promised += batch.output_quantity()
	return promised

func _maintain_stock(product: int, excluding_prepared: StringName = &"") -> int:
	# reserve_in already contains outputs promised by production AND external hauls.
	var total: int = resources.get_amount(product)+resources.get_reserved_in(product)
	for batch in _production_batches:
		if batch.is_terminal(): continue
		var reserved: int = batch.reserved_output(product)
		if batch.recipe_id==excluding_prepared and not batch.inputs_spent:
			total -= reserved
		else:
			# PREPARING is published before all reserve_in calls can emit callbacks.
			total += maxi(0,int(batch.outputs.get(product,0))-reserved)
	return total

func can_start_production(recipe_id: StringName) -> bool:
	var recipe = definition.get_production_recipe(recipe_id)
	if not is_built() or production_removed or recipe==null or not recipe.is_valid() or not supply.allows(recipe_id): return false
	for key in recipe.consumables:
		if not consumable_stocks.has(key) or consumable_stocks[key].available()<int(recipe.consumables[key]):return false
	for resource in recipe.inputs:
		if resources.get_available_amount(resource)<int(recipe.inputs[resource]): return false
	for resource in recipe.outputs:
		if resources.get_available_free_capacity(resource)<int(recipe.outputs[resource]): return false
	return true

func select_production_work(worker: String = "", source_provider: Callable = Callable(), stock_provider: Callable = Callable()) -> Dictionary:
	if production_removed or not is_built() or (not worker.is_empty() and _worker_has_batch(worker)): return {}
	var paused := resumable_production_batch()
	if paused!=null: return {"kind":&"RESUME","batch":paused,"recipe_id":paused.recipe_id}
	if _active_batch_count()>=production_capacity(): return {}
	var recipes: Array = definition.production_recipes
	for mode in [ProductionMode.ORDER,ProductionMode.MAINTAIN,ProductionMode.UNLIMITED]:
		for offset in range(recipes.size()):
			var index: int = (int(_recipe_cursors.get(mode,0))+offset)%recipes.size()
			var recipe = recipes[index]
			if get_recipe_mode(recipe.id)!=mode: continue
			if can_start_production(recipe.id): return {"kind":&"START","recipe_id":recipe.id}
			if supply.allows(recipe.id) and stock_provider.is_valid():
				for key in recipe.consumables:
					var stock: RefCounted=consumable_stocks.get(key)
					if stock==null or stock.amount!=0 or stock.incoming_units()>0:continue
					var offer: Dictionary=stock_provider.call(key)
					if not offer.is_empty():
						offer.kind=&"SUPPLY";offer.recipe_id=recipe.id
						return offer
			if not source_provider.is_valid(): continue
			var missing: Dictionary = supply.deficits(recipe.id)
			for resource in recipe.inputs:
				if not missing.has(resource) or not supply.input_room(recipe.id,resource): continue
				var source: RefCounted = source_provider.call(resource)
				if source!=null: return {"kind":&"SUPPLY","recipe_id":recipe.id,"resource":resource,"source":source}
	return {}

func claim_production_work(worker: String) -> Batch:
	if worker.is_empty(): return null
	var selected := select_production_work(worker)
	if selected.is_empty(): return null
	if selected.kind==&"RESUME":
		if not selected.batch.claim(worker): return null
		production_revision += 1
		return selected.batch
	return prepare_production_batch(worker,selected.recipe_id)

func accept_production_batch(batch: Batch) -> void:
	# Preparation can still fail to submit a movement intent. Only acceptance rotates.
	if not owns_production_batch(batch) or batch.is_terminal() or batch.selection_accepted: return
	batch.selection_accepted = true
	accept_recipe_task(batch.recipe_id)

func accept_recipe_task(recipe_id: StringName) -> void:
	var mode := get_recipe_mode(recipe_id)
	if mode<=ProductionMode.OFF: return
	for index in range(definition.production_recipes.size()):
		if definition.production_recipes[index].id==recipe_id:
			_recipe_cursors[mode] = (index+1)%definition.production_recipes.size()
			production_revision += 1
			return

func _preparation_allowed(batch: Batch) -> bool:
	if not owns_production_batch(batch) or batch.is_terminal(): return false
	if batch.inputs_spent: return true # Paid WIP is never destroyed by a recipe setting.
	var mode := get_recipe_mode(batch.recipe_id)
	if mode==ProductionMode.UNLIMITED: return true
	if mode<=ProductionMode.OFF: return false
	var budget: int
	if mode==ProductionMode.ORDER:
		budget = get_order_remaining(batch.recipe_id)-_promised_for_recipe(batch.recipe_id,true)
	else:
		var product: int = definition.get_production_recipe(batch.recipe_id).counted_product()
		budget = int(_recipe_settings[batch.recipe_id].target)-_maintain_stock(product,batch.recipe_id)
	for candidate in _production_batches:
		if candidate.recipe_id!=batch.recipe_id or candidate.inputs_spent or candidate.is_terminal(): continue
		# The last indivisible batch may cover a positive remainder smaller than its output.
		if candidate==batch: return budget>0
		budget -= candidate.output_quantity()
	return false

func _reconcile_preparations(recipe_id: StringName) -> void:
	for batch in _production_batches.duplicate():
		if batch.recipe_id==recipe_id and not batch.inputs_spent and not batch.is_terminal() and not _preparation_allowed(batch):
			batch.cancel()
			retire_production_batch(batch)

func validate_production_batch(batch: Batch) -> bool:
	if not owns_production_batch(batch): return false
	var previous_size := _production_batches.size()
	_reconcile_preparations(batch.recipe_id)
	if _production_batches.size()!=previous_size: production_changed.emit()
	return owns_production_batch(batch) and not batch.is_terminal()

func get_stock_target(resource: int) -> int:return int(_stock_targets.get(resource,0))
func stock_targets() -> Dictionary:return _stock_targets.duplicate()
func set_stock_target(resource: int, quantity: int) -> bool:
	if not is_built() or not _stock_targets.has(resource) or quantity<0 or quantity>resources.get_capacity(resource):return false
	if get_stock_target(resource)==quantity:return true
	_stock_targets[resource]=quantity
	production_revision+=1;logistics_policy_changed.emit();production_changed.emit()
	return true
func external_available(resource: int) -> int:
	return maxi(0,resources.get_available_amount(resource)-get_stock_target(resource))
func import_demand(resource: int) -> int:
	var room: int=resources.get_available_free_capacity(resource)
	return mini(room,maxi(0,get_stock_target(resource)-resources.get_amount(resource)-resources.get_reserved_in(resource))) if _stock_targets.has(resource) else room

func _on_consumables_changed() -> void:
	production_revision+=1
	production_changed.emit()
func owns_receiver(receiver: RefCounted) -> bool:
	return receiver==resources or receiver in consumable_receivers.values()
func import_receivers(resource: int, available_only: bool = true) -> Array:
	var result: Array=[]
	if resources.allows_resource(resource) and resources.get_capacity(resource)>0 and (not available_only or import_demand(resource)>0):result.append(resources)
	for receiver in consumable_receivers.values():
		if receiver.allows_resource(resource) and (not available_only or receiver.get_available_free_capacity(resource)>0):result.append(receiver)
	return result
func import_receiver(resource: int) -> RefCounted:
	var receivers:=import_receivers(resource)
	return receivers[0] if not receivers.is_empty() else null
