extends RefCounted
## Player management API: assignment is data, never a forced action.
const Profession = preload("res://scripts/resident_profession.gd")
const BuildingInstance = preload("res://scripts/building_instance.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
signal building_unregistered(building_id: StringName)
signal resident_unregistered(resident_id: String)
signal residents_changed
signal profession_changed(resident_id: String)
signal work_assignment_changed(resident_id: String)
var work_areas: RefCounted
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
	var population_changed := false
	for resident in population:
		population_changed = population_changed or _residents.get(resident.id) != resident
		_residents[resident.id] = resident
		var callback := _on_resident_home_changed.bind(resident.id)
		if not resident.home_changed.is_connected(callback): resident.home_changed.connect(callback)
	for building in buildings: register_building(building)
	normalize_porter_assignments()
	if population_changed: residents_changed.emit()

func register_building(building: RefCounted) -> void:
	if building not in _buildings: _buildings.append(building)
	if not building.is_built(): return
	var primary := _default_profession(building)
	if primary != Profession.Type.NONE:
		_workplace_professions[building.id] = primary # Registered primary role, never personnel membership.
		if not _workplaces.has(primary): _workplaces[primary] = building.id
	var preferred := get_building(_workplaces.get(Profession.Type.PORTER,&""))
	if building.definition.porter_capacity > 0 and (preferred == null or (building.definition.is_storage and not preferred.definition.is_storage)):
		_workplaces[Profession.Type.PORTER] = building.id

func _default_profession(building: RefCounted) -> int:
	if building == null: return Profession.Type.NONE
	if building.definition.worker_profession != Profession.Type.NONE: return building.definition.worker_profession
	return Profession.Type.PORTER if building.definition.porter_capacity > 0 else Profession.Type.NONE

func unregister_building(building_id: StringName) -> void:
	var building := get_building(building_id)
	if building == null and not _workplace_professions.has(building_id): return
	if building != null: _buildings.erase(building)
	_workplace_professions.erase(building_id)
	for role in _workplaces.keys():
		if _workplaces[role] == building_id: _workplaces.erase(role)
	# Assignment invalidation is management, not a second haul cancellation path.
	for resident in _residents.values():
		if resident.work_location_id == building_id: clear_work_assignment(resident.id)
	building_unregistered.emit(building_id)

func register_commands(resident_id: String, controller: Node) -> void:
	_commands[resident_id] = controller

func get_resident(resident_id: String): return _residents.get(resident_id)
func get_residents() -> Array: return _residents.values()

func move_to(resident_id: String, destination: Vector2) -> bool:
	var controller: Node = _commands.get(resident_id)
	return is_instance_valid(controller) and controller.move_to(destination)

func assign_workplace(resident_id: String, location_id: StringName, profession: int = -1) -> bool:
	var role := _default_profession(get_building(location_id)) if profession == -1 else profession
	if not can_assign_workplace(resident_id,location_id,role): return false
	return _assign(resident_id,role,location_id)

func register_intents(resident_id: String, controller: Node) -> void:
	_intents[resident_id] = controller

func current_intent(resident_id: String):
	var controller: Node = _intents.get(resident_id)
	return controller.current_intent if is_instance_valid(controller) else null

func assign_profession(resident_id: String, profession: Profession.Type) -> bool:
	# True means the profession was accepted; workplace may remain empty for Porter.
	var resident: RefCounted = _residents.get(resident_id)
	if not profession_eligibility_error(resident_id,profession).is_empty(): return false
	if profession in [Profession.Type.LUMBERJACK,Profession.Type.MINER] and resident.profession == profession and not resident.work_area_id.is_empty(): return true
	if profession in [Profession.Type.NONE,Profession.Type.BUILDER]: return _assign(resident_id,profession,&"")
	if resident.profession == profession and can_assign_workplace(resident_id,resident.work_location_id,profession): return true
	var preferred: StringName = _workplaces.get(profession,&"")
	if can_assign_workplace(resident_id,preferred,profession): return _assign(resident_id,profession,preferred)
	var ids: Array = _buildings.map(func(building): return building.id)
	ids.sort_custom(func(a,b): return String(a)<String(b))
	for location in ids:
		if can_assign_workplace(resident_id,location,profession): return _assign(resident_id,profession,location)
	if profession in [Profession.Type.PORTER,Profession.Type.LUMBERJACK,Profession.Type.MINER]: return _assign(resident_id,profession,&"")
	return false

func _assign(resident_id: String, profession: Profession.Type, location_id: StringName) -> bool:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null: return false
	if resident.profession == profession and resident.work_location_id == location_id and resident.work_area_id.is_empty(): return true
	resident.profession = profession
	resident.work_location_id = location_id
	resident.work_area_id = &""
	# No intent replacement or decision request: finish the committed operation first.
	if logger != null: logger.info(EventLog.AI, "%s: назначение профессии — %s" % [resident.resident_name, Profession.display_name(profession)])
	profession_changed.emit(resident_id)
	work_assignment_changed.emit(resident_id)
	return true


func get_building(building_id: StringName) -> RefCounted:
	for building in _buildings:
		if building.id == building_id: return building
	return null

func _is_housing_definition(building: RefCounted) -> bool:
	return building is BuildingInstance and building.type == BuildingType.Type.HOME and building.definition.housing_capacity > 0
func is_housing_target(building: RefCounted) -> bool:
	return _is_housing_definition(building) and building.is_built()
func has_housing_role(building_id: StringName) -> bool:
	return _is_housing_definition(get_building(building_id))
func get_workplace_roles(building_id: StringName) -> Array[int]:
	var building := get_building(building_id)
	var roles: Array[int] = []
	if building == null: return roles
	if building.definition.worker_profession != Profession.Type.NONE: roles.append(building.definition.worker_profession)
	if building.definition.porter_capacity > 0: roles.append(Profession.Type.PORTER)
	return roles # Applicability is known even while construction blocks admission.
func profession_eligibility_error(resident_id: String, profession: int) -> String:
	if get_resident(resident_id) == null: return "Житель не найден"
	if profession not in Profession.Type.values(): return "Профессия недоступна"
	return "" # No age/skill/building/vacancy requirement exists for eligibility.
func home_assignment_error(resident_id: String, building_id: StringName) -> String:
	var resident = get_resident(resident_id)
	var building := get_building(building_id)
	if resident == null: return "Житель не найден"
	if building == null: return "Здание недоступно"
	if not building.is_built(): return "Здание ещё строится"
	if not is_housing_target(building): return "Здание не предназначено для заселения"
	if resident.home_location_id == building_id: return "Житель уже живёт здесь"
	if get_home_occupants(building_id).size() >= building.definition.housing_capacity: return "В доме нет свободных мест"
	return ""

func get_home(resident_id: String) -> RefCounted:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null or resident.home_location_id.is_empty(): return null
	var building := get_building(resident.home_location_id)
	return building if is_housing_target(building) else null

func get_home_occupants(building_id: StringName) -> Array:
	# Query only: there is no mutable occupant list in a house.
	return _residents.values().filter(func(resident): return resident.home_location_id == building_id)

func assign_home(resident_id: String, building_id: StringName) -> bool:
	if not home_assignment_error(resident_id,building_id).is_empty(): return false
	var resident: RefCounted = _residents.get(resident_id)
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

func get_production_workers(location_id: StringName) -> Array:
	var building := get_building(location_id)
	if building == null or building.definition.worker_profession == Profession.Type.NONE: return []
	return _residents.values().filter(func(resident): return resident.work_location_id == location_id and resident.profession == building.definition.worker_profession)

func get_porters(location_id: StringName) -> Array:
	return _residents.values().filter(func(resident): return not location_id.is_empty() and resident.work_location_id == location_id and resident.profession == Profession.Type.PORTER)

func get_workplace_workers(location_id: StringName) -> Array:
	# Compatibility: primary production role at huts; Porter at non-production buildings.
	var building := get_building(location_id)
	return get_production_workers(location_id) if building != null and building.definition.worker_profession != Profession.Type.NONE else get_porters(location_id)

func get_staff_capacity(location_id: StringName, profession: int) -> int:
	var building := get_building(location_id)
	if building == null: return 0
	if profession == Profession.Type.PORTER: return building.definition.porter_capacity
	return building.definition.worker_capacity if profession != Profession.Type.NONE and building.definition.worker_profession == profession else 0

func get_free_staff_places(location_id: StringName, profession: int) -> int:
	var capacity := get_staff_capacity(location_id,profession)
	var workers := get_porters(location_id) if profession == Profession.Type.PORTER else get_production_workers(location_id)
	if profession != Profession.Type.PORTER and capacity == 0:
		var building := get_building(location_id)
		if building != null and profession != Profession.Type.NONE and building.definition.worker_profession == profession: return -1 # Existing unlimited production capacity.
	return maxi(0,capacity-workers.size())

func workplace_assignment_error(resident_id: String, location_id: StringName, profession: int = -1) -> String:
	var resident = _residents.get(resident_id)
	var building = get_building(location_id)
	if resident == null: return "Житель не найден"
	if building == null: return "Здание недоступно"
	if not building.is_built(): return "Здание ещё строится"
	var role := _default_profession(building) if profession == -1 else profession
	if role == Profession.Type.PORTER:
		if building.definition.porter_capacity <= 0: return "Здание не поддерживает назначение носильщиков"
	elif role == Profession.Type.NONE or role != building.definition.worker_profession:
		return "Здание не поддерживает эту профессию"
	if resident.work_location_id == location_id and resident.profession == role: return ""
	var capacity := get_staff_capacity(location_id,role)
	var workers := get_porters(location_id) if role == Profession.Type.PORTER else get_production_workers(location_id)
	if (role == Profession.Type.PORTER or capacity > 0) and workers.size() >= capacity:
		return ("Места носильщиков заняты: %d/%d" if role == Profession.Type.PORTER else "Рабочие места заняты: %d/%d") % [workers.size(),capacity]
	return ""

func can_assign_workplace(resident_id: String, location_id: StringName, profession: int = -1) -> bool:
	return workplace_assignment_error(resident_id,location_id,profession).is_empty()

func normalize_porter_assignments() -> Array[String]:
	# Admission of pre-existing data only. New assignment attempts never evict anyone.
	var unassigned: Array[String] = []
	var changed_ids: Array[String] = []
	var used: Dictionary = {}
	var ids: Array = _residents.keys()
	ids.sort()
	for id in ids:
		var resident = _residents[id]
		if resident.profession != Profession.Type.PORTER: continue
		var building := get_building(resident.work_location_id)
		var count: int = used.get(resident.work_location_id,0)
		var invalid: bool = not resident.work_location_id.is_empty() and (building == null or not building.is_built() or count >= building.definition.porter_capacity)
		if invalid:
			resident.work_location_id = &""
			unassigned.append(id)
		elif building != null: used[building.id] = count+1
		if invalid or not resident.work_area_id.is_empty():
			resident.work_area_id = &""
			changed_ids.append(id)
	# Publish only after every normalized relationship is consistent, including callbacks.
	for id in changed_ids:
		var resident = _residents.get(id)
		if resident == null: continue
		var label: String = resident.resident_name
		work_assignment_changed.emit(id)
		if id in unassigned and logger != null: logger.info(EventLog.PLAYER,"%s: носильщик без рабочего места — нормализация назначения" % label)
	return unassigned

func register_resident(resident: RefCounted) -> void:
	if _residents.has(resident.id): return
	_residents[resident.id] = resident
	normalize_porter_assignments()
	resident.home_changed.connect(_on_resident_home_changed.bind(resident.id))
	residents_changed.emit()
func unregister_resident(resident_id: String) -> void:
	var resident: RefCounted = _residents.get(resident_id)
	if resident == null: return
	clear_work_assignment(resident_id)
	resident.home_changed.disconnect(_on_resident_home_changed.bind(resident_id))
	_residents.erase(resident_id)
	for registry in [_intents,_commands,_assignments]: registry.erase(resident_id)
	resident_unregistered.emit(resident_id)
	residents_changed.emit()

func assign_work_area(resident_id: String, area_id: StringName) -> bool:
	var resident: RefCounted = get_resident(resident_id)
	if resident == null or resident.profession not in [Profession.Type.LUMBERJACK,Profession.Type.MINER] or work_areas == null or work_areas.get_area(area_id) == null: return false
	resident.work_location_id = &""
	resident.work_area_id = area_id
	work_assignment_changed.emit(resident_id)
	return true
func clear_work_assignment(resident_id: String) -> bool:
	var resident: RefCounted = get_resident(resident_id)
	if resident == null: return false
	resident.work_location_id = &""
	resident.work_area_id = &""
	work_assignment_changed.emit(resident_id)
	return true
