extends RefCounted
## Shared preliminary stock for notifications, never permission to reserve or eat.
## One lazy scan per resource/world change replaces one scan per resident.
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var _buildings: Array
var _locations: RefCounted
var _sources: RefCounted
var _subscriptions: Array = []
var _dirty := true
var _total := 0
var _ground_amount := 0

func setup(buildings: Array, locations: RefCounted) -> void:
	_buildings = buildings
	_locations = locations
	for building in buildings: register_building(building)
	var navigation: RefCounted = locations.get("navigation")
	if navigation != null: navigation.changed.connect(invalidate)
	var uses: RefCounted = locations.get("uses")
	if uses != null: uses.removed.connect(_building_removed)

func register_building(building: RefCounted) -> void:
	if building in _subscriptions: return
	_subscriptions.append(building)
	building.resources.availability_changed.connect(_resource_changed)
	if building.has_signal("construction_changed"): building.construction_changed.connect(invalidate)
	invalidate()

func bind_sources(provider: RefCounted) -> void:
	if _sources == provider: return
	if _sources != null: _sources.changed.disconnect(_world_changed)
	_sources = provider
	_sources.changed.connect(_world_changed)
	_ground_amount = _count_ground()
	invalidate()

func invalidate(_revision: int = 0) -> void:
	_dirty = true

func total() -> int:
	if _dirty:
		_total = _count()
		_dirty = false
	return _total

func _count() -> int:
	var amount := 0
	for building in _buildings:
		if building.is_built() and building.resources.allows_resource(FOOD) and building.resources.get_capacity(FOOD)>0 and _locations.get_position(building.id) is Vector2:
			amount += building.resources.get_available_amount(FOOD)
	return amount + _ground_amount

func _count_ground() -> int:
	var amount := 0
	if _sources != null and is_instance_valid(_sources.ground):
		for drop in _sources.ground.drops:
			if drop.resource_type == FOOD: amount += drop.available_amount()
	return amount

func _resource_changed(resource: int, _amount: int) -> void:
	if resource != FOOD: return
	invalidate() # Runs before Needs subscribers; nested changes invalidate again.

func _world_changed() -> void:
	# Existing ResourceSources notification is already deferred/coalesced.
	for building in _subscriptions.duplicate():
		if building not in _buildings:
			_disconnect_building(building)
			_subscriptions.erase(building)
	_ground_amount = _count_ground()
	invalidate()

func _building_removed(_id: StringName) -> void:
	_world_changed()

func _disconnect_building(building: RefCounted) -> void:
	building.resources.availability_changed.disconnect(_resource_changed)
	if building.has_signal("construction_changed"): building.construction_changed.disconnect(invalidate)

func dispose() -> void:
	for building in _subscriptions: _disconnect_building(building)
	_subscriptions.clear()
	if _sources != null: _sources.changed.disconnect(_world_changed)
	if _locations != null:
		var navigation: RefCounted = _locations.get("navigation")
		if navigation != null: navigation.changed.disconnect(invalidate)
		var uses: RefCounted = _locations.get("uses")
		if uses != null: uses.removed.disconnect(_building_removed)
	_sources = null
	_locations = null
	_buildings = []
