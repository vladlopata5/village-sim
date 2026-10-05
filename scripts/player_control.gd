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

func setup(population: Array, buildings: Array) -> void:
	for resident in population: _residents[resident.id] = resident
	for building in buildings:
		match building.type:
			BuildingType.Type.STORAGE: _workplaces[Profession.Type.PORTER] = building.id
			BuildingType.Type.GATHERER_HUT: _workplaces[Profession.Type.GATHERER] = building.id

func register_intents(resident_id: String, controller: Node) -> void:
	_intents[resident_id] = controller

func current_intent(resident_id: String):
	var controller: Node = _intents.get(resident_id)
	return controller.current_intent if is_instance_valid(controller) else null

func assign_profession(resident_id: String, profession: Profession.Type) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null or profession not in Profession.Type.values(): return false
	if profession != Profession.Type.NONE and not _workplaces.has(profession): return false
	var location_id: StringName = _workplaces.get(profession, &"")
	if resident.profession == profession and resident.work_location_id == location_id: return true
	resident.profession = profession
	resident.work_location_id = location_id
	# No intent replacement or decision request: finish the committed operation first.
	if logger != null: logger.info(EventLog.AI, "%s: назначение профессии — %s" % [resident.resident_name, Profession.display_name(profession)])
	profession_changed.emit(resident_id)
	return true
