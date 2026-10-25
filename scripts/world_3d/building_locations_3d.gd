extends RefCounted
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
## Authored entrance/action bridge for the canonical 3D scene.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var uses: RefCounted
var navigation: RefCounted
var _locations: Dictionary = {}
var _views: Dictionary = {}
func register(location: RefCounted, view: Node) -> void:
	_locations[location.id] = location
	_views[location.id] = view
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
	return null

func resolve_sleep_position(building: RefCounted) -> Variant:
	# An inhabited B2 still uses the original entrance, never a builder's approach.
	if uses==null or not building.is_housing_usable():return null
	var entry: Variant=uses.entrance(building.id)
	if entry is Vector3:return Coordinates.to_sim(entry)
	return null
func unregister(id: StringName) -> void:
	_locations.erase(id)
	_views.erase(id)

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
func at_action(resident_id: String, building_id: StringName, purpose: int, _point: Vector2, _tolerance: float) -> bool:
	if uses!=null:
		var presentation = get_view(building_id)
		var building = presentation.building_data if presentation!=null else null
		if purpose==Purpose.COURIER and building!=null and not building.is_built(): purpose=Purpose.CONSTRUCTION
		return uses.occupied_by(building_id,resident_id,purpose)
	return false

func get_resource_position(id: StringName) -> Variant:
	if uses==null: return null
	var point: Variant = uses.courier_position(id)
	if point is Vector3: return Coordinates.to_sim(point)
	return null
