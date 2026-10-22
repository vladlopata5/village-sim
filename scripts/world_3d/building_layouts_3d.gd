extends RefCounted
## Small authored-layout catalog; geometry and gameplay capacities remain separate.
const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
const Entrance = preload("res://scripts/world_3d/building_entrance_3d.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
static func create(definition: RefCounted) -> Node3D:
	return load("res://scenes/building_layouts/%s.tscn" % definition.id).instantiate()
static func markers(layout: Node, script: Script) -> Array:
	var found: Array = []
	for node in layout.get_children():
		if node.get_script()==script: found.append(node)
		found.append_array(markers(node,script))
	return found
static func validate(layout: Node, definition: RefCounted) -> bool:
	var entrances := markers(layout,Entrance)
	if entrances.size()!=1: return false
	var slots := markers(layout,Slot).filter(func(marker):return marker.minimum_level<=definition.development_level)
	var physical := Rect2(-Vector2(definition.footprint_cells)*0.25,Vector2(definition.footprint_cells)*0.5)
	for marker in slots:
		if marker.purpose!=Slot.Purpose.COURIER: continue
		if not physical.has_point(Coordinates.world_plane(marker.position)): return false
		if slots.any(func(other): return other!=marker and marker.position.distance_to(other.position)<2.0*Geometry.RESIDENT_RADIUS): return false
	var ids: Dictionary = {}
	var counts: Dictionary = {}
	for marker in slots:
		if marker.local_id.is_empty() or ids.has(marker.local_id): return false
		ids[marker.local_id]=true
		counts[marker.purpose]=counts.get(marker.purpose,0)+1
	if counts.get(Slot.Purpose.ANIMAL_SLEEP,0)!=definition.animal_capacity: return false
	if counts.get(Slot.Purpose.ANIMAL_SERVICE,0)!=(1 if definition.animal_capacity>0 else 0): return false
	return counts.get(Slot.Purpose.WORKER,0)==definition.worker_capacity and counts.get(Slot.Purpose.SLEEP,0)==maxi(definition.housing_capacity,definition.fallback_housing_capacity) and counts.get(Slot.Purpose.COURIER,0)==(1 if not definition.logistics_flow.is_empty() or definition.max_builders>0 else 0) and counts.get(Slot.Purpose.VISITOR,0)==definition.visitor_capacity and counts.get(Slot.Purpose.CONSTRUCTION,0)>=definition.max_builders
static var _entrance_data: Dictionary = {}
static func entrance_zone(definition: RefCounted, center: Vector3, turns: int) -> Rect2:
	if not _entrance_data.has(definition.id):
		var layout := create(definition)
		var entry: Marker3D = markers(layout,Entrance)[0]
		_entrance_data[definition.id]={"position":entry.position,"size":entry.zone_size}
		layout.free()
	var data: Dictionary = _entrance_data[definition.id]
	var basis := Basis(Vector3.UP,turns*PI/2.0)
	var point: Vector3 = center+basis*data.position
	var size: Vector2 = data.size
	if turns%2==1: size=Vector2(size.y,size.x)
	return Rect2(Coordinates.world_plane(point)-size/2,size)
