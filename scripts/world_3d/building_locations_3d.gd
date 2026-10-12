extends RefCounted
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
## Authored entrance/action bridge. Derived access retained only for legacy reference fixtures.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
var uses: RefCounted
var navigation: RefCounted
var _locations: Dictionary = {}
var _views: Dictionary = {}
var _access: Dictionary = {}
func register(location: RefCounted, view: Node) -> void:
	_locations[location.id] = location
	_views[location.id] = view
	_access.erase(location.id)
func get_location(id: StringName) -> RefCounted: return _locations.get(id)
func get_view(id: StringName) -> Node:
	var view = _views.get(id)
	return view if is_instance_valid(view) else null
func get_position(id: StringName) -> Variant:
	var view = get_view(id)
	return resolve_action_position(view.building_data) if view != null else null
func resolve_action_position(building: RefCounted) -> Variant:
	if uses != null:
		var entry: Variant = uses.entrance(building.id)
		if not building.is_built():
			var target_view = uses.view(building.id)
			if target_view==null: return null
			for marker in target_view.get_markers(preload("res://scripts/world_3d/building_slot_3d.gd")):
				if marker.purpose==Purpose.CONSTRUCTION and navigation.is_world_walkable(marker.global_position): return Coordinates.to_sim(marker.global_position)
		if entry is Vector3: return Coordinates.to_sim(entry)
		return null
	if navigation == null: return null
	var cached: Dictionary = _access.get(building.id,{})
	if cached.get("revision",-1) == navigation.revision: return cached.point
	var bounds := Geometry.footprint(building)
	var center := bounds.get_center()
	var distance: float = navigation.clearance + navigation.CELL_SIZE/2.0
	var origins := [Vector2(center.x,bounds.end.y),Vector2(bounds.end.x,center.y),Vector2(center.x,bounds.position.y),Vector2(bounds.position.x,center.y)]
	var directions := [Vector2.DOWN,Vector2.RIGHT,Vector2.UP,Vector2.LEFT]
	# One point: fixed +Z,+X,-Z,-X order, up to two extra cells outward per side.
	for index in range(origins.size()):
		var side: int = posmod(index + building.quarter_turns, 4)
		for offset in range(3):
			var candidate: Vector2 = origins[side]+directions[side]*(distance+offset*navigation.CELL_SIZE)
			var cell: Vector2i = navigation.world_to_cell(Coordinates.from_plane(candidate))
			var point: Vector3 = navigation.cell_to_world(cell)
			if navigation.is_world_walkable(point):
				var sim := Coordinates.to_sim(point)
				_access[building.id] = {"revision":navigation.revision,"point":sim}
				return sim
	_access[building.id] = {"revision":navigation.revision,"point":null}
	return null

func unregister(id: StringName) -> void:
	_locations.erase(id)
	_views.erase(id)
	_access.erase(id)

func configure_intent(intent: RefCounted, building_id: StringName, purpose: int, resident_id: String) -> void:
	if uses==null: return
	intent.building_id=building_id
	var presentation = get_view(building_id)
	var building = presentation.building_data if presentation!=null else null
	if purpose==Purpose.COURIER and building!=null and not building.is_built(): purpose=Purpose.CONSTRUCTION
	intent.slot_purpose=purpose
	if purpose==Purpose.COURIER:
		var courier: Variant = uses.courier_position(building_id)
		if courier is Vector3: intent.target_position=Coordinates.to_sim(courier)
	elif purpose==Purpose.CONSTRUCTION:
		var view = get_view(building_id)
		if view==null: return
		var free: Array = uses.choices(building_id,purpose,uses.resident_position(resident_id,view.global_position))
		if not free.is_empty(): intent.target_position=Coordinates.to_sim(free[0].global_position)
func at_action(resident_id: String, building_id: StringName, purpose: int, point: Vector2, tolerance: float) -> bool:
	if uses!=null:
		var presentation = get_view(building_id)
		var building = presentation.building_data if presentation!=null else null
		if purpose==Purpose.COURIER and building!=null and not building.is_built(): purpose=Purpose.CONSTRUCTION
		return uses.occupied_by(building_id,resident_id,purpose)
	var target: Variant = get_position(building_id)
	return target is Vector2 and point.distance_to(target)<=tolerance

func get_resource_position(id: StringName) -> Variant:
	if uses==null: return get_position(id)
	var point: Variant = uses.courier_position(id)
	return Coordinates.to_sim(point) if point is Vector3 else null
