extends RefCounted
## Capability registry. No visual nodes and no simulation rules inside menu UI.
const Assignment = preload("res://scripts/resident_assignment.gd")
const Option = preload("res://scripts/interaction_option.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
var control: RefCounted
var _targets: Dictionary = {}
func register_target(id: StringName, label: String, data: RefCounted, position: Callable, capabilities: Array = [], profession: int = -1) -> void:
	_targets[id] = {"label": label, "data": data, "position": position, "capabilities": capabilities, "profession": profession}
func register_building(building: RefCounted, position: Callable) -> void:
	if not building.is_built(): return
	var capabilities: Array = []
	var profession := -1
	if building.definition.is_storage:
		capabilities.append(&"employment")
		profession = Profession.Type.PORTER
	match building.type:
		BuildingType.Type.HOME: capabilities.append(&"housing")
		BuildingType.Type.FOOD:
			capabilities.append_array([&"food",&"employment"])
			profession = Profession.Type.COOK
		BuildingType.Type.LUMBERJACK_HUT:
			capabilities.append(&"employment")
			profession = Profession.Type.LUMBERJACK
		BuildingType.Type.QUARRY:
			capabilities.append(&"employment")
			profession = Profession.Type.MINER
		BuildingType.Type.SAWMILL:
			capabilities.append(&"employment")
			profession = Profession.Type.SAWYER
		BuildingType.Type.WEAVER_WORKSHOP, BuildingType.Type.TAILOR_WORKSHOP:
			capabilities.append(&"employment")
			profession = building.definition.worker_profession
		BuildingType.Type.SHEPHERD_HUT:
			capabilities.append(&"employment")
			profession = Profession.Type.SHEPHERD
		BuildingType.Type.GATHERER_HUT:
			capabilities.append(&"employment")
			profession = Profession.Type.GATHERER
	if building.definition.porter_capacity > 0 and profession != Profession.Type.PORTER: capabilities.append(&"porter_employment")
	register_target(building.id, building.display_name, building, position, capabilities, profession)
func remove_target(id: StringName) -> void: _targets.erase(id)
func get_interactions(resident_ids: Array, target_id: StringName) -> Array:
	# Current UI passes one ID. Future group UI intersects by option ID and enablement.
	if resident_ids.is_empty() or not _targets.has(target_id): return []
	var common: Array = _for_resident(resident_ids[0], target_id)
	for resident_id in resident_ids.slice(1):
		var options := _for_resident(resident_id, target_id)
		common = common.filter(func(option): return options.any(func(other): return other.id == option.id))
		for option in common:
			for other in options:
				if other.id == option.id and not other.enabled:
					option.enabled = false
					option.disabled_reason = other.disabled_reason
	return common
func _for_resident(resident_id: String, target_id: StringName) -> Array:
	var data = control.get_resident(resident_id)
	if data == null: return []
	var target: Dictionary = _targets[target_id]
	var point: Variant = target.position.call()
	var options: Array = [Option.new(&"go_to", "Идти к", Option.Kind.PLAYER_COMMAND, target_id, point is Vector2, "Место недоступно" if not point is Vector2 else "")]
	for capability in target.capabilities:
		match capability:
			&"animal":
				if data.profession==Profession.Type.SHEPHERD:
					var wild: bool=target.data.status==preload("res://scripts/animal_data.gd").Status.WILD
					var free: bool=target.data.operation_id.is_empty()
					options.append(Option.new(&"capture_sheep","Поймать овцу",Option.Kind.RESIDENT_ASSIGNMENT,target_id,wild and free,"Овца домашняя" if not wild else ("Овца уже закреплена" if not free else "")))
			&"resident":
				if String(target_id) != resident_id:
					options.append(Option.new(&"talk", "Поговорить с %s" % target.label, Option.Kind.RESIDENT_ASSIGNMENT, target_id))
			&"food":
				options.append(Option.new(&"eat", "Поесть здесь", Option.Kind.RESIDENT_ASSIGNMENT, target_id))
			&"housing":
				if not control.is_housing_target(target.data): continue
				if data.home_location_id == target_id:
					options.append(Option.new(&"clear_home", "Выселиться", Option.Kind.MANAGEMENT_ACTION, target_id))
				else:
					var full: bool = control.get_home_occupants(target_id).size() >= target.data.definition.housing_capacity
					options.append(Option.new(&"assign_home", "Назначить дом", Option.Kind.MANAGEMENT_ACTION, target_id, not full, "Дом заполнен" if full else ""))
			&"employment", &"porter_employment":
				var role: int = Profession.Type.PORTER if capability == &"porter_employment" else target.profession
				var already: bool = data.profession == role and data.work_location_id == target_id
				var error: String = control.workplace_assignment_error(resident_id,target_id,role)
				var label := "Назначить носильщиком здесь" if role == Profession.Type.PORTER else "Работать: " + Profession.display_name(role)
				options.append(Option.new(capability,label,Option.Kind.MANAGEMENT_ACTION,target_id,not already and error.is_empty(),"Уже работает здесь" if already else error))
			&"ground_resource":
				for action in [[&"pick_up", "Поднять"], [&"haul", "Отнести на склад"]]:
					options.append(Option.new(action[0], action[1], Option.Kind.RESIDENT_ASSIGNMENT, target_id, false, "Поручения будут добавлены следующим этапом"))
	return options
func execute(resident_ids: Array, option: Option) -> bool:
	# Capture validates its live animal/workplace in the assignment controller and
	# reports a stale menu refusal through the character feed, rather than silently hiding it.
	if option.id==&"capture_sheep":
		if resident_ids.is_empty(): return false
		for resident_id in resident_ids:
			if not control.add_assignment(resident_id,Assignment.new(&"",resident_id,Assignment.CAPTURE_SHEEP,option.target_id)): return false
		return true
	# Revalidate at click time: a drop/place or availability may have changed.
	var actual := get_interactions(resident_ids, option.target_id)
	if not actual.any(func(row): return row.id == option.id and row.enabled): return false
	for resident_id in resident_ids:
		match option.id:
			&"go_to":
				var point: Variant = _targets[option.target_id].position.call()
				if not point is Vector2 or not control.move_to(resident_id, point): return false
			&"talk":
				var assignment := Assignment.new(&"", resident_id, Assignment.TALK_TO, option.target_id)
				if not control.add_assignment(resident_id, assignment): return false
			&"eat":
				var assignment := Assignment.new(&"", resident_id, Assignment.EAT_AT_TARGET, option.target_id)
				if not control.add_assignment(resident_id, assignment): return false
			&"assign_home":
				if not control.assign_home(resident_id, option.target_id): return false
			&"clear_home":
				if not control.clear_home(resident_id): return false
			&"employment":
				if not control.assign_workplace(resident_id, option.target_id): return false
			&"porter_employment":
				if not control.assign_workplace(resident_id,option.target_id,Profession.Type.PORTER): return false
			_: return false
	return true
