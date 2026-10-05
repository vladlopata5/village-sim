extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Shared membership and available actions; positions come from an injected world adapter.
const Group = preload("res://scripts/conversation_group.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const BASE_OPTION_WEIGHT := 500.0
const DISTANCE_PENALTY := 0.5
var position_provider: Callable
var residents: Dictionary = {}
var groups: Dictionary = {}
var _next_group_id := 1
func register(runtime: Node) -> void:
	residents[runtime.data.id] = runtime
func get_runtime(id: String):
	var runtime = residents.get(id)
	return runtime if is_instance_valid(runtime) and not runtime.is_queued_for_deletion() else null
func position_of(id: String) -> Vector2:
	return position_provider.call(id) if position_provider.is_valid() else Vector2.ZERO
func group_of(id: String):
	for group in groups.values():
		if id in group.participants: return group
	return null
func options_for(id: String) -> Array:
	var options: Array = []
	var seen_groups: Array = []
	for other_id in residents:
		if other_id == id: continue
		var other = get_runtime(other_id)
		if other == null: continue
		if other.social == null or not is_instance_valid(other.social): continue
		var group = group_of(other_id)
		if other.data.activity == Activity.Type.TALKING and group != null:
			if group.id in seen_groups: continue
			seen_groups.append(group.id)
		elif other.data.activity != Activity.Type.IDLE or other.intents.has_current_action(): continue
		var distance := position_of(id).distance_to(position_of(other_id))
		options.append({"target_id": other_id, "group_id": group.id if group != null else 0,
			"option_weight": BASE_OPTION_WEIGHT / (1.0 + distance * DISTANCE_PENALTY / BASE_OPTION_WEIGHT)})
	return options
func valid_option(option: Dictionary) -> bool:
	if option.group_id != 0: return groups.has(option.group_id)
	var target = get_runtime(option.target_id)
	return target != null and target.data.activity == Activity.Type.IDLE and not target.intents.has_current_action()
func option_position(option: Dictionary) -> Vector2:
	if option.group_id != 0 and groups.has(option.group_id):
		return position_of(groups[option.group_id].participants[0])
	return position_of(option.target_id)
func arrive(id: String, option: Dictionary) -> bool:
	if not valid_option(option): return false
	var group
	if option.group_id != 0:
		group = groups[option.group_id]
	else:
		group = Group.new(_next_group_id)
		_next_group_id += 1
		groups[group.id] = group
		group.participants.append(option.target_id)
		get_runtime(option.target_id).social.begin_talking()
	group.participants.append(id)
	get_runtime(id).social.begin_talking()
	return true
func leave(id: String) -> void:
	var group = group_of(id)
	if group == null: return
	group.participants.erase(id)
	var departing = get_runtime(id)
	if logger != null and departing != null: logger.info(EventLog.SOCIAL, "%s: вышел из разговора" % departing.data.resident_name)
	if group.participants.size() < 2:
		groups.erase(group.id)
		for remaining in group.participants.duplicate():
			var runtime = get_runtime(remaining)
			if runtime != null:
				if logger != null: logger.info(EventLog.SOCIAL, "%s: разговор закончился — группа распалась" % runtime.data.resident_name)
				runtime.social.call_deferred("group_dissolved")
		group.participants.clear()
