extends Node
## Natural one-unit gathering proposals. Execution belongs to the existing HaulExecutor.
const Area = preload("res://scripts/building_work_area.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Types = preload("res://scripts/building_type.gd").Type
const Source = preload("res://scripts/resource_source_ref.gd")
const MUSHROOM = preload("res://scripts/resource_type.gd").Type.MUSHROOM
var logger: RefCounted
var building: RefCounted
var additional_buildings: Array=[]
var _locations: RefCounted
var _position_provider: Callable
var _service: RefCounted
var _areas: RefCounted
var _nature: RefCounted
var _offers: Dictionary={}
func setup(_clock: Node, hut: RefCounted, _population: Array, locations: RefCounted, position_provider: Callable) -> void:
	building=hut;_locations=locations;_position_provider=position_provider
func bind_nature(model: RefCounted, areas: RefCounted, logistics: RefCounted) -> void:
	_nature=model;_areas=areas;_service=logistics
	_service.sources.bind_nature(model)
	model.availability_changed.connect(_validate_jobs)
func _exit_tree() -> void:
	if _service!=null: _service.sources.bind_nature(null)
func _validate_jobs() -> void:
	if _service!=null: _service.recalculate() # Owned tasks only; no idle-worker wakeup.
func workplace(data: RefCounted) -> RefCounted:
	if data.profession!=Profession.GATHERER or not data.work_area_id.is_empty(): return null
	for hut in [building]+additional_buildings:
		if hut!=null and hut.id==data.work_location_id and hut.type==Types.GATHERER_HUT and hut.is_built() and _locations.get_position(hut.id) is Vector2: return hut
	return null
func context(data: RefCounted) -> Array:
	var hut:=workplace(data)
	if hut==null: return []
	var area: RefCounted=Area.resolve(hut,_areas)
	return [data.work_assignment_revision,hut.get_instance_id(),area.id,area.revision,area.center,area.radius]
func valid(data: RefCounted, identity: Array) -> bool:
	return not identity.is_empty() and context(data)==identity
func find_source(data: RefCounted) -> RefCounted:
	var hut:=workplace(data)
	if _nature==null or hut==null or hut.resources.get_available_free_capacity(MUSHROOM)<1: return null
	var origin: Variant=_position_provider.call(data.id)
	if not origin is Vector2: return null
	var stamp: Array=context(data)+[origin,_nature.revision,_locations.navigation.revision, hut.resources.get_available_free_capacity(MUSHROOM)]
	var previous: Dictionary=_offers.get(data.id,{})
	if previous.get("stamp",[])==stamp: return previous.source
	var area: RefCounted=Area.resolve(hut,_areas)
	var candidates: Array=[]
	for cell in _nature.mushroom_cells():
		var id: StringName=_nature.source_id(cell)
		var point: Vector2=_nature.position(id)
		if _nature.available_amount(id)>0 and area.contains(point): candidates.append({"id":id,"point":point,"distance":origin.distance_squared_to(point)})
	candidates.sort_custom(func(a,b):return a.distance<b.distance or (a.distance==b.distance and String(a.id)<String(b.id)))
	var found: RefCounted
	for candidate in candidates:
		if _service.sources.reachable(origin,candidate.point) and _service.sources.reachable(candidate.point,_service._point(hut)):
			found=Source.new(Source.Kind.NATURAL_MUSHROOM,candidate.id);break
	# Including misses avoids rescanning unchanged unreachable sources at every probe.
	_offers[data.id]={"stamp":stamp,"source":found}
	return found
func can_work(data: RefCounted) -> bool: return find_source(data)!=null
