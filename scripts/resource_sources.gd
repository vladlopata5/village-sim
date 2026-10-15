extends RefCounted
## Source resolution and one-unit reservation adapters, never work assignment/scoring.
const Source = preload("res://scripts/resource_source_ref.gd")
const GroundAreas = preload("res://scripts/ground_search_areas.gd")
signal changed
var buildings: Dictionary = {}
var locations: RefCounted
var ground: Node
var route_available: Callable
var work_object_current: Callable # Existing world registry includes unfinished construction sites.
var _claims: Dictionary = {} # Container reservation ownership, not resource quantities.
var revision := 0 # Availability generation for transient selection reuse.
var _queued := false
func bind_ground(value: Node) -> void:
	ground = value
	if not ground.availability_changed.is_connected(_queue_changed): ground.availability_changed.connect(_queue_changed)
func resolve(source_ref: Source) -> Variant:
	if source_ref == null: return null
	if source_ref.kind == Source.Kind.CONTAINER: return buildings.get(source_ref.id)
	if is_instance_valid(ground):
		return ground.get_by_id(source_ref.id)
	return null
func point(source_ref: Source) -> Variant:
	var entity: Variant = resolve(source_ref)
	if entity == null: return null
	if source_ref.kind == Source.Kind.GROUND: return entity.world_position
	return (locations.get_resource_position(entity.id) if locations.has_method("get_resource_position") else locations.get_position(entity.id)) if locations != null else entity.position
func label(source_ref: Source) -> String:
	var entity: Variant = resolve(source_ref)
	return "земля (%s)" % source_ref.id if source_ref.kind == Source.Kind.GROUND else (entity.display_name if entity != null else String(source_ref.id))
func export_allowed(source_ref: Source, resource: int) -> bool:
	var entity: Variant = resolve(source_ref)
	if entity == null: return false
	if source_ref.kind == Source.Kind.GROUND: return entity.resource_type == resource
	return entity.is_built() and entity.definition.allows_external_export(resource) and entity.resources.allows_resource(resource)
func available(source_ref: Source, resource: int) -> bool:
	if not export_allowed(source_ref,resource) or not point(source_ref) is Vector2: return false
	var entity: Variant = resolve(source_ref)
	return entity.amount > 0 and entity.reservation_owner_id.is_empty() if source_ref.kind == Source.Kind.GROUND else entity.resources.get_available_amount(resource)>0
func reachable(start: Vector2, target: Vector2) -> bool:
	return not route_available.is_valid() or route_available.call(start,target)
func _current_work_object(workplace: RefCounted) -> RefCounted:
	if workplace == null: return null
	if work_object_current.is_valid(): return workplace if work_object_current.call(workplace) else null
	return workplace if buildings.get(workplace.id) == workplace else null
func ground_allowed(source_ref: Source, origin: Variant, workplace: RefCounted = null, area: RefCounted = null) -> bool:
	if source_ref == null: return false
	if source_ref.kind == Source.Kind.CONTAINER: return true
	var target: Variant = point(source_ref)
	# Removed/replaced work objects cannot contribute a stale search circle.
	var live_workplace: RefCounted = _current_work_object(workplace)
	return target is Vector2 and GroundAreas.contains(target,origin,live_workplace,area)
func ground_candidates(resource: int, origin: Variant, workplace: RefCounted = null, area: RefCounted = null) -> Array:
	var result: Array = []
	if not is_instance_valid(ground): return result
	var live_workplace: RefCounted = _current_work_object(workplace)
	for drop in ground.drops:
		if (resource < 0 or drop.resource_type == resource) and drop.amount > 0 and drop.reservation_owner_id.is_empty() and GroundAreas.contains(drop.world_position,origin,live_workplace,area):
			result.append(Source.new(Source.Kind.GROUND,drop.id))
	return result
func find(resource: int, origin: Vector2, destination: Vector2, excluded: StringName = &"", workplace: RefCounted = null, area: RefCounted = null) -> Array:
	var result: Array = []
	for building in buildings.values():
		if building.id != excluded: result.append(Source.new(Source.Kind.CONTAINER,building.id))
	result.append_array(ground_candidates(resource,origin,workplace,area))
	result = result.filter(func(ref): return available(ref,resource) and reachable(origin,point(ref)) and reachable(point(ref),destination))
	result.sort_custom(func(a,b):
		var da: float = origin.distance_to(point(a))+point(a).distance_to(destination)
		var db: float = origin.distance_to(point(b))+point(b).distance_to(destination)
		return da<db or (is_equal_approx(da,db) and a.stable_key()<b.stable_key()))
	return result
# Builder-only query. Rank cheap lower bounds, validate raw routes, never smooth here.
# The slack bounds the unexamined raw-route alternatives, not resource admission.
const CONSTRUCTION_SEARCH_SLACK := 1.25
func find_construction_trip(resource: int, origin: Vector2, destination: Vector2, excluded: StringName, planner: Callable, lower_bound: Callable, slack: float = CONSTRUCTION_SEARCH_SLACK, workplace: RefCounted = null, area: RefCounted = null) -> Dictionary:
	var references: Array = []
	for building in buildings.values():
		if building.id != excluded: references.append(Source.new(Source.Kind.CONTAINER,building.id))
	references.append_array(ground_candidates(resource,origin,workplace,area))
	var candidates: Array[Dictionary] = []
	for source_ref in references:
		if not available(source_ref,resource): continue
		var access: Vector2 = point(source_ref)
		candidates.append({"reference":source_ref,"point":access,"bound":float(lower_bound.call(origin,access,destination)),"key":source_ref.stable_key()})
	candidates.sort_custom(func(a,b): return a.bound < b.bound or (a.bound == b.bound and a.key < b.key))
	var best: Dictionary = {}
	for candidate in candidates:
		# No fixed candidate cap: unreachable prefixes never mean "no work".
		if not best.is_empty() and best.cost <= maxf(1.0,slack)*candidate.bound: break
		var plan: Dictionary = planner.call(origin,candidate.point,destination)
		if plan.is_empty(): continue
		if best.is_empty() or plan.cost < best.cost or (plan.cost == best.cost and candidate.key < best.reference.stable_key()):
			best = plan.duplicate()
			best["reference"] = candidate.reference
	return best

func reserve(source_ref: Source, resource: int, owner: StringName) -> bool:
	if owner.is_empty() or _claims.has(owner) or not available(source_ref,resource): return false
	var entity: Variant = resolve(source_ref)
	if source_ref.kind == Source.Kind.GROUND: return entity.reserve(owner)
	# Record ownership before synchronous reserve callbacks observe the ledger.
	_claims[owner] = {"source":source_ref,"resource":resource}
	if not entity.resources.reserve_out(resource,1):
		_claims.erase(owner)
		return false
	_queue_changed()
	return true
func reserved(source_ref: Source, resource: int, owner: StringName) -> bool:
	var entity: Variant = resolve(source_ref)
	if entity == null or not export_allowed(source_ref,resource): return false
	if source_ref.kind == Source.Kind.GROUND: return entity.amount>0 and entity.reservation_owner_id==owner
	var claim: Dictionary = _claims.get(owner,{})
	if claim.is_empty() or claim.source.stable_key()!=source_ref.stable_key() or claim.resource!=resource: return false
	var managed := 0
	for row in _claims.values():
		if row.source.stable_key()==source_ref.stable_key() and row.resource==resource: managed += 1
	return entity.resources.get_reserved_out(resource)>=managed
func pickup(source_ref: Source, resource: int, owner: StringName) -> bool:
	if not reserved(source_ref,resource,owner): return false
	var entity: Variant = resolve(source_ref)
	if source_ref.kind == Source.Kind.GROUND: return ground.take_reserved(entity,owner)
	var claim: Dictionary = _claims[owner]
	_claims.erase(owner)
	if not entity.resources.take_reserved(resource,1):
		_claims[owner] = claim
		return false
	_queue_changed()
	return true
func release(source_ref: Source, resource: int, owner: StringName, reserved_entity: Variant = null) -> void:
	# A claim transaction may lose registry access inside reserve callbacks.
	# The caller retains the original object only until owned rollback completes.
	var entity: Variant = reserved_entity if reserved_entity != null else resolve(source_ref)
	if source_ref == null: return
	if source_ref.kind == Source.Kind.GROUND:
		if entity != null: entity.release(owner)
	else:
		var claim: Dictionary = _claims.get(owner,{})
		if not claim.is_empty() and claim.source.stable_key()==source_ref.stable_key() and claim.resource==resource:
			_claims.erase(owner)
			if entity != null: entity.resources.release_out(resource,1)
	_queue_changed()
func storage_destinations(source: Source, resource: int, origin: Vector2) -> Array:
	var result: Array = []
	for building in buildings.values():
		if building.id==source.id or not building.is_built() or not building.definition.is_storage: continue
		if not building.definition.allows_external_import(resource) or building.resources.get_available_free_capacity(resource)<1: continue
		var target: Variant = point(Source.new(Source.Kind.CONTAINER,building.id))
		if target is Vector2 and reachable(origin,target): result.append(building)
	result.sort_custom(func(a,b):
		var pa: Vector2 = point(Source.new(Source.Kind.CONTAINER,a.id))
		var pb: Vector2 = point(Source.new(Source.Kind.CONTAINER,b.id))
		var da := origin.distance_squared_to(pa)
		var db := origin.distance_squared_to(pb)
		return da<db or (is_equal_approx(da,db) and String(a.id)<String(b.id)))
	return result
func _queue_changed() -> void:
	revision += 1
	if _queued: return
	_queued = true
	call_deferred("_emit_changed")
func _emit_changed() -> void:
	_queued = false
	changed.emit()

func find_ground_in_area(resource: int, area: RefCounted, origin: Vector2, destination: Vector2, workplace: RefCounted = null) -> Array:
	# Rank cheaply first, then stop at first reachable: same selected result, fewer paths.
	var result: Array = ground_candidates(resource,origin,workplace,area)
	result.sort_custom(func(a,b):
		var da: float = origin.distance_to(point(a))+point(a).distance_to(destination)
		var db: float = origin.distance_to(point(b))+point(b).distance_to(destination)
		return da<db or (is_equal_approx(da,db) and a.stable_key()<b.stable_key()))
	for source_ref in result:
		var target: Vector2 = point(source_ref)
		if reachable(origin,target) and reachable(target,destination): return [source_ref]
	return []
