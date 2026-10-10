extends RefCounted
## Local physical occupancy service, never a job/worker scheduler.
const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const Entrance = preload("res://scripts/world_3d/building_entrance_3d.gd")
signal slots_changed(building_id: StringName, purpose: int)
signal removed(building_id: StringName)
var navigation: RefCounted
var _views: Dictionary = {}
func register(building: RefCounted, presentation: Node3D) -> void:
	assert(Layouts.validate(presentation.layout,building.definition),"Authored building slots must match gameplay capacity")
	_views[building.id]=presentation
func unregister(id: StringName) -> void:
	_views.erase(id)
	removed.emit(id)
func view(id: StringName) -> Node3D:
	var found: Node3D = _views.get(id)
	return found if is_instance_valid(found) else null
func entrance(id: StringName) -> Variant:
	var target := view(id)
	if target==null or not target.is_inside_tree(): return null
	var marker: Marker3D = Layouts.markers(target.layout,Entrance)[0]
	if navigation.is_world_walkable(marker.global_position): return marker.global_position
	return null
func choices(id: StringName, purpose: int, origin: Vector3) -> Array:
	var target := view(id)
	if target==null or (purpose==Slot.Purpose.CONSTRUCTION)==target.building_data.is_built(): return []
	var result: Array = []
	for marker in Layouts.markers(target.layout,Slot):
		if marker.purpose!=purpose or not marker.occupant.is_empty(): continue
		if purpose==Slot.Purpose.CONSTRUCTION and not navigation.is_world_walkable(marker.global_position): continue
		result.append(marker)
	result.sort_custom(func(a,b):
		var da: float = origin.distance_squared_to(a.global_position)
		var db: float = origin.distance_squared_to(b.global_position)
		return String(a.local_id)<String(b.local_id) if is_equal_approx(da,db) else da<db)
	return result
func acquire(id: StringName, purpose: int, resident_id: String, origin: Vector3) -> Marker3D:
	var target := view(id)
	if target==null: return null
	if purpose==Slot.Purpose.CONSTRUCTION and resident_id not in target.building_data.active_builder_ids: return null
	var free := choices(id,purpose,origin)
	if free.is_empty(): return null
	var marker: Marker3D = free[0]
	marker.occupant=resident_id
	target.set_inside_count(inside_count(id))
	slots_changed.emit(id,purpose)
	return marker
func release(id: StringName, marker: Marker3D, resident_id: String) -> void:
	if not is_instance_valid(marker) or marker.occupant!=resident_id: return
	marker.occupant=""
	var target := view(id)
	if target!=null: target.set_inside_count(inside_count(id))
	slots_changed.emit(id,marker.purpose)
func inside_count(id: StringName) -> int:
	var target := view(id)
	if target==null: return 0
	return Layouts.markers(target.layout,Slot).filter(func(m): return m.purpose!=Slot.Purpose.CONSTRUCTION and not m.occupant.is_empty()).size()
func occupied_by(id: StringName, resident_id: String, purpose: int) -> bool:
	var target := view(id)
	return target!=null and Layouts.markers(target.layout,Slot).any(func(m): return m.purpose==purpose and m.occupant==resident_id)

var executors: Dictionary = {} # Weak world references, not copied positions.
func resident_position(id: String, fallback: Vector3) -> Vector3:
	var body: Node3D = executors[id].get_ref() if executors.has(id) else null
	return body.global_position if is_instance_valid(body) else fallback
