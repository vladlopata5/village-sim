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
	var capabilities: Array = []
	var profession := -1
	match building.type:
		BuildingType.Type.FOOD: capabilities.append(&"food")
		BuildingType.Type.STORAGE:
			capabilities.append(&"employment")
			profession = Profession.Type.PORTER
		BuildingType.Type.GATHERER_HUT:
			capabilities.append(&"employment")
			profession = Profession.Type.GATHERER
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
			&"food":
				options.append(Option.new(&"eat", "Поесть здесь", Option.Kind.RESIDENT_ASSIGNMENT, target_id))
			&"employment":
				var already: bool = data.profession == target.profession and data.work_location_id == target_id
				options.append(Option.new(&"employment", "Устроиться на работу", Option.Kind.MANAGEMENT_ACTION, target_id, not already, "Уже работает здесь" if already else ""))
			&"ground_resource":
				for action in [[&"pick_up", "Поднять"], [&"haul", "Отнести на склад"]]:
					options.append(Option.new(action[0], action[1], Option.Kind.RESIDENT_ASSIGNMENT, target_id, false, "Поручения будут добавлены следующим этапом"))
	return options
func execute(resident_ids: Array, option: Option) -> bool:
	# Revalidate at click time: a drop/place or availability may have changed.
	var actual := get_interactions(resident_ids, option.target_id)
	if not actual.any(func(row): return row.id == option.id and row.enabled): return false
	for resident_id in resident_ids:
		match option.id:
			&"go_to":
				var point: Variant = _targets[option.target_id].position.call()
				if not point is Vector2 or not control.move_to(resident_id, point): return false
			&"eat":
				var assignment := Assignment.new(&"", resident_id, Assignment.EAT_AT_TARGET, option.target_id)
				if not control.add_assignment(resident_id, assignment): return false
			&"employment":
				if not control.assign_workplace(resident_id, option.target_id): return false
			_: return false
	return true
