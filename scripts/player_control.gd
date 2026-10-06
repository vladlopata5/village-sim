extends RefCounted
## Player management API: assignment is data, never a forced action.
const Profession = preload("res://scripts/resident_profession.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
signal profession_changed(resident_id: String)
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
	for resident in population: _residents[resident.id] = resident
	for building in buildings:
		match building.type:
			BuildingType.Type.STORAGE:
				_workplaces[Profession.Type.PORTER] = building.id
				_workplace_professions[building.id] = Profession.Type.PORTER
			BuildingType.Type.GATHERER_HUT:
				_workplaces[Profession.Type.GATHERER] = building.id
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
	if profession != Profession.Type.NONE and not _workplaces.has(profession): return false
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
