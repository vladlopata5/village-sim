extends RefCounted
## One executor's domestic binding. Movement/positions still belong to that executor.
const Animal = preload("res://scripts/animal_data.gd")
const BuildingArea = preload("res://scripts/building_work_area.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var building: RefCounted
var _body: WeakRef
var _uses: RefCounted
var _areas: RefCounted
var _slot: Marker3D
var _entry := Vector3.ZERO
var _releasing := false
func assign(body: Node3D, hut: RefCounted, uses: RefCounted, areas: RefCounted, requester: StringName) -> bool:
	if uses==null or areas==null or uses.view(hut.id)==null or not hut.is_built(): return false
	_body=weakref(body); building=hut; _uses=uses; _areas=areas
	building.animal_housing.closing.connect(release)
	_uses.removed.connect(_removed)
	if not building.animal_housing.assign(body.data,requester):
		_disconnect()
		return false
	if body.home!=self or not building.animal_housing.has_member(body.data.id): return false
	body.behavior.sleep_offer=request_sleep
	body.behavior.waking.connect(wake)
	body.behavior.suspend()
	body.behavior.resume()
	return body.home==self
func is_inside() -> bool: return is_instance_valid(_slot)
func area() -> RefCounted: return BuildingArea.resolve(building,_areas)
func area_center() -> Vector3:
	return Coordinates.to_world(area().center)
func area_radius() -> float:
	return Coordinates.length_to_world(area().radius)
func contains(point: Vector3) -> bool:
	var region: RefCounted=area()
	return region!=null and region.contains(Coordinates.to_sim(point))
func request_sleep(now: int) -> void:
	var body = _body.get_ref()
	if body==null or body.home!=self: return
	var entrance: Variant=_uses.entrance(building.id)
	if not entrance is Vector3:
		body.behavior._retry(now)
		return
	_entry=entrance
	body.behavior._set_behavior(Animal.Behavior.RETURN_HOME,now,-1)
	if body.home==self: body.behavior.movement_requested.emit(body.behavior.token,_entry,{})
func arrive(expected: int) -> void:
	var body = _body.get_ref()
	if body==null or body.home!=self or expected!=body.behavior.token or body.data.behavior!=Animal.Behavior.RETURN_HOME: return
	if not building.is_built() or body.global_position.distance_to(_entry)>0.001:
		body.behavior._retry(body.behavior._clock.total_minutes)
		return
	var identity: StringName=body.data.id
	var acquired: Marker3D=_uses.acquire_animal(building.id,identity,body.global_position)
	if not is_instance_valid(body) or body.home!=self:
		_uses.release_animal(building.id,acquired,identity)
		return # Occupancy notification may synchronously close the hut.
	_slot=acquired
	if not is_instance_valid(_slot):
		body.behavior._retry(body.behavior._clock.total_minutes)
		return
	body.global_position=_slot.global_position # Portal only after actual outside arrival.
	body.data.position=body.global_position
	body.movement.reset_physical_origin()
	body.set_indoor(true)
	body.behavior._begin_sleep(body.behavior._clock.total_minutes)
func wake() -> void:
	_exit()
func enter_service(identity: StringName) -> bool:
	var body = _body.get_ref()
	if body==null or body.data.operation_id!=identity or is_inside() or not building.is_built(): return false
	var entrance: Variant=_uses.entrance(building.id)
	if not entrance is Vector3 or body.global_position.distance_to(entrance)>0.001: return false
	_entry=entrance
	var animal_id: StringName=body.data.id
	var acquired: Marker3D=_uses.acquire_animal(building.id,animal_id,body.global_position,preload("res://scripts/building_slot_purpose.gd").Type.ANIMAL_SERVICE)
	if not is_instance_valid(body) or body.home!=self or body.data.operation_id!=identity or not building.is_built():
		_uses.release_animal(building.id,acquired,animal_id)
		return false
	if acquired==null: return false
	_slot=acquired
	body.global_position=_slot.global_position
	body.data.position=body.global_position
	body.movement.reset_physical_origin()
	body.set_indoor(true)
	return true
func leave_service(identity: StringName) -> void:
	var body = _body.get_ref()
	if body!=null and body.data.operation_id==identity: _exit()
func owns_service(identity: StringName) -> bool:
	var body = _body.get_ref()
	return body!=null and body.data.operation_id==identity and is_instance_valid(_slot) and _slot.purpose==preload("res://scripts/building_slot_purpose.gd").Type.ANIMAL_SERVICE and _slot.occupant=="animal:"+String(body.data.id)
func _exit() -> void:
	var body = _body.get_ref()
	if not is_instance_valid(_slot): return
	var old_slot := _slot
	_slot=null # Clear membership before synchronous release callbacks.
	if body!=null:
		body.global_position=_entry
		body.data.position=body.global_position
		body.movement.reset_physical_origin()
		body.set_indoor(false)
		_uses.release_animal(building.id,old_slot,body.data.id)
func _disconnect() -> void:
	if building.animal_housing.closing.is_connected(release): building.animal_housing.closing.disconnect(release)
	if _uses.removed.is_connected(_removed): _uses.removed.disconnect(_removed)
func release(resume: bool = true) -> void:
	if _releasing: return
	_releasing=true
	var body = _body.get_ref()
	_disconnect()
	if body!=null:
		body.interrupt_movement()
		body.behavior.suspend()
		_exit()
		body.behavior.sleep_offer=Callable()
		if body.behavior.waking.is_connected(wake): body.behavior.waking.disconnect(wake)
		body.home=null
		building.animal_housing.release(body.data)
		if resume: body.behavior.resume()
func _removed(id: StringName) -> void:
	if building.id==id: release()
