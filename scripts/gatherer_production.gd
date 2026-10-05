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
var _output_blocked := false
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
	return building.type == BuildingType.Type.GATHERER_HUT and resident.profession == Profession.Type.GATHERER and resident.work_location_id == building.id and building.resources.get_available_free_capacity(FOOD) > 0 and _locations.get_position(building.id) is Vector2
func _contributes(resident: RefCounted) -> bool:
	var assignment: Dictionary = work_assignment_provider.call(resident.id) if work_assignment_provider.is_valid() else {}
	if assignment.is_empty(): return can_work(resident)
	# The already-started safe cycle keeps its original role/place until its boundary.
	return assignment.profession == Profession.Type.GATHERER and assignment.location_id == building.id

func _on_minute(_minute: int) -> void:
	# Physical/output capacity is checked before adding even one work minute.
	if building.resources.get_available_free_capacity(FOOD) <= 0:
		if not _output_blocked and logger != null: logger.info(EventLog.PRODUCTION, "%s: производство остановлено — выходной контейнер заполнен" % building.display_name)
		_output_blocked = true
		return
	_output_blocked = false
	var workers := 0
	var target: Variant = _locations.get_position(building.id)
	for resident in residents:
		if not target is Vector2 or not _contributes(resident) or resident.activity != Activity.Type.WORKING: continue
		var position: Variant = _position_provider.call(resident.id)
		if position is Vector2 and position.distance_to(target) <= WORK_POSITION_TOLERANCE: workers += 1
	if workers == 0 and building.production_progress < Balance.GATHERER_WORK_MINUTES_PER_FOOD: return
	building.production_progress += workers
	while building.production_progress >= Balance.GATHERER_WORK_MINUTES_PER_FOOD and building.resources.get_available_free_capacity(FOOD) > 0:
		if not building.resources.add(FOOD, 1): break
		building.production_progress -= Balance.GATHERER_WORK_MINUTES_PER_FOOD
		if logger != null: logger.info(EventLog.PRODUCTION, "%s: произведён 1 FOOD" % building.display_name)
	changed.emit()
