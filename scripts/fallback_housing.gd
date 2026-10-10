extends RefCounted
## Transient committed sleep claims, never home ownership or beds.
signal claim_invalidated(resident_id: String)
signal changed
var _buildings: Array
var _locations: RefCounted
var _claims: Dictionary = {} # resident ID -> building ID, only during a sleep action.
func setup(buildings: Array, locations: RefCounted) -> void:
	_buildings = buildings
	_locations = locations
func target(building_id: StringName) -> Variant:
	for building in _buildings:
		if building.id != building_id or not building.is_built() or building.definition.fallback_housing_capacity <= 0: continue
		return _locations.resolve_action_position(building) if _locations.has_method("resolve_action_position") else _locations.get_position(building.id)
	return null
func validate() -> void:
	for resident_id in _claims.keys():
		if not target(_claims[resident_id]) is Vector2:
			_claims.erase(resident_id)
			claim_invalidated.emit(resident_id)
			changed.emit()
func claim(resident_id: String) -> StringName:
	validate()
	if _claims.has(resident_id): return _claims[resident_id]
	var candidates := _buildings.duplicate()
	candidates.sort_custom(func(a,b): return String(a.id)<String(b.id))
	for building in candidates:
		if target(building.id) is Vector2 and count(building.id)<building.definition.fallback_housing_capacity:
			_claims[resident_id] = building.id
			changed.emit()
			return building.id
	return &""
func count(building_id: StringName) -> int:
	return _claims.values().count(building_id)
func owns(resident_id: String, building_id: StringName) -> bool:
	return _claims.get(resident_id,&"")==building_id and not building_id.is_empty()
func release(resident_id: String) -> void:
	if _claims.erase(resident_id): changed.emit()
