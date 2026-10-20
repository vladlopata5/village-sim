extends RefCounted
## Permanent membership and future capture holds; independent from physical slots.
const Animal = preload("res://scripts/animal_data.gd")
signal changed
signal closing
var _building: WeakRef
var _members: Dictionary = {}
var _holds: Dictionary = {} # Owner -> animal ID. Idempotent, one place per animal.
var _closing := false
func _init(building: RefCounted) -> void:
	_building = weakref(building)
	building.construction_changed.connect(_state_changed)
func count() -> int: return _members.size()
func reserved_count() -> int: return _holds.size()
func has_member(id: StringName) -> bool: return _members.has(id)
func available() -> int:
	var building = _building.get_ref()
	return maxi(building.definition.animal_capacity-count()-reserved_count(),0) if building != null and building.is_built() and not _closing else 0
func reserve(requester: StringName, animal_id: StringName) -> bool:
	if requester.is_empty() or animal_id.is_empty() or _members.has(animal_id): return false
	if _holds.has(requester): return _holds[requester]==animal_id
	if animal_id in _holds.values() or available()==0: return false
	_holds[requester]=animal_id
	changed.emit()
	return true
func release_reservation(requester: StringName) -> void:
	if _holds.erase(requester): changed.emit()
func assign(animal: Animal, requester: StringName = &"") -> bool:
	var building = _building.get_ref()
	if building==null or not building.is_built() or _closing: return false
	if animal.id.is_empty(): return false
	if _members.has(animal.id): return _members[animal.id]==animal
	if animal.status!=Animal.Status.WILD or not animal.home_id.is_empty(): return false
	var held: bool = not requester.is_empty() and _holds.get(requester)==animal.id
	if not requester.is_empty() and not held: return false
	if not held and (available()==0 or animal.id in _holds.values()): return false
	if held: _holds.erase(requester)
	_members[animal.id]=animal # Publish before callbacks.
	animal.home_id=building.id
	animal.status=Animal.Status.DOMESTIC
	animal.changed.emit()
	changed.emit()
	return _members.get(animal.id)==animal
func release(animal: Animal) -> void:
	if _members.get(animal.id)!=animal: return
	_members.erase(animal.id)
	animal.home_id=&""
	animal.status=Animal.Status.WILD
	animal.habitat_center=animal.position
	animal.habitat_radius=preload("res://scripts/balance_config.gd").SHEEP_HABITAT_RADIUS
	animal.changed.emit()
	changed.emit()
func _state_changed() -> void:
	var building = _building.get_ref()
	if building!=null and building.is_built(): return
	if _closing: return
	_closing=true
	closing.emit() # Physical owners exit through the portal before changing wild anchors.
	for animal in _members.values(): release(animal)
	_holds.clear()
	_closing=false
	changed.emit()
