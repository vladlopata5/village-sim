extends RefCounted
## Player management API: assignment is data, never a forced action.
const Profession = preload("res://scripts/resident_profession.gd")
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
signal profession_changed(resident_id: String)
signal home_changed(resident_id: String, previous: StringName, current: StringName)
var _buildings: Array = [] # Shared world collection, not a separate housing registry.
var _residents: Dictionary = {}
var _intents: Dictionary = {}
var _workplaces: Dictionary = {}
var _commands: Dictionary = {}
var _assignments: Dictionary = {}
var _workplace_professions: Dictionary = {}
const Assignment = preload("res://scripts/resident_assignment.gd")

func register_assignments(resident_id: String, controller: Node) -> void:
	_assignments[resident_id] = controller

func add_assignment(resident_id: String, assignment: Assignment) -> bool:
	var controller: Node = _assignments.get(resident_id)
	return is_instance_valid(controller) and controller.add(assignment)

func cancel_assignment(resident_id: String, assignment_id: StringName) -> bool:
	var controller: Node = _assignments.get(resident_id)
	return is_instance_valid(controller) and controller.cancel(assignment_id)

func describe_assignment(resident_id: String, assignment_id: StringName) -> String:
	var controller: Node = _assignments.get(resident_id)
	return controller.describe_assignment(assignment_id) if is_instance_valid(controller) else ""

func setup(population: Array, buildings: Array) -> void:
	_buildings = buildings
	for resident in population:
		_residents[resident.id] = resident
		var callback := _on_resident_home_changed.bind(resident.id)
		if not resident.home_changed.is_connected(callback): resident.home_changed.connect(callback)
	for building in buildings: register_building(building)

func register_building(building: RefCounted) -> void:
	if building not in _buildings: _buildings.append(building)
	if not building.is_built(): return
	match building.type:
		BuildingType.Type.STORAGE:
			if not _workplaces.has(Profession.Type.PORTER): _workplaces[Profession.Type.PORTER] = building.id
			_workplace_professions[building.id] = Profession.Type.PORTER
		BuildingType.Type.GATHERER_HUT:
			if not _workplaces.has(Profession.Type.GATHERER): _workplaces[Profession.Type.GATHERER] = building.id
			_workplace_professions[building.id] = Profession.Type.GATHERER

func register_commands(resident_id: String, controller: Node) -> void:
	_commands[resident_id] = controller

func get_resident(resident_id: String): return _residents.get(resident_id)

func move_to(resident_id: String, destination: Vector2) -> bool:
	var controller: Node = _commands.get(resident_id)
	return is_instance_valid(controller) and controller.move_to(destination)

func assign_workplace(resident_id: String, location_id: StringName) -> bool:
	if not _workplace_professions.has(location_id): return false
	return _assign(resident_id, _workplace_professions[location_id], location_id)

func register_intents(resident_id: String, controller: Node) -> void:
	_intents[resident_id] = controller

func current_intent(resident_id: String):
	var controller: Node = _intents.get(resident_id)
	return controller.current_intent if is_instance_valid(controller) else null

func assign_profession(resident_id: String, profession: Profession.Type) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null or profession not in Profession.Type.values(): return false
	if profession not in [Profession.Type.NONE, Profession.Type.BUILDER] and not _workplaces.has(profession): return false
	return _assign(resident_id, profession, _workplaces.get(profession, &""))

func _assign(resident_id: String, profession: Profession.Type, location_id: StringName) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null: return false
	if resident.profession == profession and resident.work_location_id == location_id: return true
	resident.profession = profession
	resident.work_location_id = location_id
	# No intent replacement or decision request: finish the committed operation first.
	if logger != null: logger.info(EventLog.AI, "%s: назначение профессии — %s" % [resident.resident_name, Profession.display_name(profession)])
	profession_changed.emit(resident_id)
	return true


func get_building(building_id: StringName) -> RefCounted:
	for building in _buildings:
		if building.id == building_id: return building
	return null

func is_housing_target(building: RefCounted) -> bool:
	return building is BuildingInstance and building.is_built() and building.type == BuildingType.Type.HOME and building.definition.housing_capacity > 0

func get_home(resident_id: String) -> RefCounted:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null or resident.home_location_id.is_empty(): return null
	var building := get_building(resident.home_location_id)
	return building if is_housing_target(building) else null

func get_home_occupants(building_id: StringName) -> Array:
	# Query only: there is no mutable occupant list in a house.
	return _residents.values().filter(func(resident): return resident.home_location_id == building_id)

func assign_home(resident_id: String, building_id: StringName) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	var building := get_building(building_id)
	if resident == null or not is_housing_target(building) or resident.home_location_id == building_id: return false
	if get_home_occupants(building_id).size() >= building.definition.housing_capacity: return false
	# Validate the new home before replacing the old relationship.
	var previous: StringName = resident.home_location_id
	resident.home_location_id = building_id
	if logger != null:
		var message := "%s: назначен дом — %s" % [resident.resident_name, building_id] if previous.is_empty() else "%s: сменил дом %s → %s" % [resident.resident_name, previous, building_id]
		logger.info(EventLog.PLAYER, message)
	return true

func clear_home(resident_id: String) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null or resident.home_location_id.is_empty(): return false
	resident.home_location_id = &""
	if logger != null: logger.info(EventLog.PLAYER, "%s: больше не имеет назначенного дома" % resident.resident_name)
	return true

func _on_resident_home_changed(previous: StringName, current: StringName, resident_id: String) -> void:
	home_changed.emit(resident_id, previous, current)
