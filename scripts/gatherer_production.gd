extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## One FOOD recipe. Work is summed into building-owned progress, never resident-owned.
const Balance = preload("res://scripts/balance_config.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const WORK_POSITION_TOLERANCE := 8.0
signal changed
var _blocked_buildings: Dictionary = {}
var additional_buildings: Array = []
var building: RefCounted
var residents: Array
var _locations: RefCounted
var _position_provider: Callable
var work_assignment_provider: Callable
func setup(clock: Node, hut: RefCounted, population: Array, locations: RefCounted, position_provider: Callable) -> void:
	building = hut
	residents = population
	_locations = locations
	_position_provider = position_provider
	clock.minute_changed.connect(_on_minute)
func can_work(resident: RefCounted) -> bool:
	for output in [building] + additional_buildings:
		if _can_work_at(resident, output): return true
	return false
func _can_work_at(resident: RefCounted, output: RefCounted) -> bool:
	return output.is_built() and output.type == BuildingType.Type.GATHERER_HUT and resident.profession == Profession.Type.GATHERER and resident.work_location_id == output.id and output.resources.get_available_free_capacity(FOOD) > 0 and _locations.get_position(output.id) is Vector2
func _contributes(resident: RefCounted, output: RefCounted) -> bool:
	var assignment: Dictionary = work_assignment_provider.call(resident.id) if work_assignment_provider.is_valid() else {}
	if assignment.is_empty(): return _can_work_at(resident, output)
	return assignment.profession == Profession.Type.GATHERER and assignment.location_id == output.id

func _on_minute(_minute: int) -> void:
	for output in [building] + additional_buildings: _produce(output)

func _produce(output: RefCounted) -> void:
	if not output.is_built(): return
	# Physical/output capacity is checked before adding even one work minute.
	if output.resources.get_available_free_capacity(FOOD) <= 0:
		if not _blocked_buildings.get(output.id, false) and logger != null: logger.info(EventLog.PRODUCTION, "%s: производство остановлено — выходной контейнер заполнен" % output.display_name)
		_blocked_buildings[output.id] = true
		return
	_blocked_buildings[output.id] = false
	var workers := 0
	var target: Variant = _locations.get_position(output.id)
	for resident in residents:
		if not target is Vector2 or not _contributes(resident, output) or resident.activity != Activity.Type.WORKING: continue
		var position: Variant = _position_provider.call(resident.id)
		if position is Vector2 and position.distance_to(target) <= WORK_POSITION_TOLERANCE: workers += 1
	if workers == 0 and output.production_progress < Balance.GATHERER_WORK_MINUTES_PER_FOOD: return
	output.production_progress += workers
	while output.production_progress >= Balance.GATHERER_WORK_MINUTES_PER_FOOD and output.resources.get_available_free_capacity(FOOD) > 0:
		if not output.resources.add(FOOD, 1): break
		output.production_progress -= Balance.GATHERER_WORK_MINUTES_PER_FOOD
		if logger != null: logger.info(EventLog.PRODUCTION, "%s: произведён 1 FOOD" % output.display_name)
	changed.emit()
