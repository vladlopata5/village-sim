extends RefCounted
## Source resolution and one-unit reservation adapters, never work assignment/scoring.
const Source = preload("res://scripts/resource_source_ref.gd")
signal changed
var buildings: Dictionary = {}
var locations: RefCounted
var ground: Node
var route_available: Callable
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
		for drop in ground.drops:
			if drop.id == source_ref.id: return drop
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
func find(resource: int, origin: Vector2, destination: Vector2, excluded: StringName = &"") -> Array:
	var result: Array = []
	for building in buildings.values():
		if building.id != excluded: result.append(Source.new(Source.Kind.CONTAINER,building.id))
	if is_instance_valid(ground):
		for drop in ground.drops: result.append(Source.new(Source.Kind.GROUND,drop.id))
	result = result.filter(func(ref): return available(ref,resource) and reachable(origin,point(ref)) and reachable(point(ref),destination))
	result.sort_custom(func(a,b):
		var da: float = origin.distance_to(point(a))+point(a).distance_to(destination)
		var db: float = origin.distance_to(point(b))+point(b).distance_to(destination)
		return da<db or (is_equal_approx(da,db) and a.stable_key()<b.stable_key()))
	return result
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
func release(source_ref: Source, resource: int, owner: StringName) -> void:
	var entity: Variant = resolve(source_ref)
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

func find_ground_in_area(resource: int, area: RefCounted, origin: Vector2, destination: Vector2) -> Array:
	# Rank cheaply first, then stop at first reachable: same selected result, fewer paths.
	var result: Array = []
	if not is_instance_valid(ground): return result
	for drop in ground.drops:
		if drop.resource_type!=resource or drop.amount<1 or not drop.reservation_owner_id.is_empty() or not area.contains(drop.world_position): continue
		result.append(Source.new(Source.Kind.GROUND,drop.id))
	result.sort_custom(func(a,b):
		var da: float = origin.distance_to(point(a))+point(a).distance_to(destination)
		var db: float = origin.distance_to(point(b))+point(b).distance_to(destination)
		return da<db or (is_equal_approx(da,db) and a.stable_key()<b.stable_key()))
	for source_ref in result:
		var target: Vector2 = point(source_ref)
		if reachable(origin,target) and reachable(target,destination): return [source_ref]
	return []
