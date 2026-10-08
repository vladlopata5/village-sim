extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Shared membership and available actions; positions come from an injected world adapter.
const Group = preload("res://scripts/conversation_group.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const BASE_OPTION_WEIGHT := 500.0
const DISTANCE_PENALTY := 0.5
signal conversation_joined(resident_id: String)
signal membership_changing
signal membership_changed
signal availability_changed
var position_provider: Callable
var residents: Dictionary = {}
var groups: Dictionary = {}
var _next_group_id := 1
func register(runtime: Node) -> void:
	residents[runtime.data.id] = runtime
	runtime.intents.intent_changed.connect(_on_action_changed)
	runtime.data.activity_changed.connect(_on_activity_changed)
func unregister(id: String) -> void:
	leave(id)
	residents.erase(id)
	availability_changed.emit()
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
		elif not _idle_available(other): continue
		var distance := position_of(id).distance_to(position_of(other_id))
		options.append({"target_id": other_id, "group_id": group.id if group != null else 0,
			"option_weight": BASE_OPTION_WEIGHT / (1.0 + distance * DISTANCE_PENALTY / BASE_OPTION_WEIGHT)})
	return options
func target_option(id: String, target_id: String) -> Dictionary:
	if id == target_id or not position_provider.is_valid(): return {}
	var target = get_runtime(target_id)
	if target == null or not position_of(target_id).is_finite(): return {}
	var group = group_of(target_id)
	if not _idle_available(target) and not (target.data.activity == Activity.Type.TALKING and group != null): return {}
	return {"target_id": target_id, "group_id": group.id if group != null else 0, "exact_target": true}
func _on_action_changed(_intent: RefCounted) -> void:
	# Notify after synchronous action cleanup/arrival, not while state is half changed.
	call_deferred("_emit_availability")
func _on_activity_changed() -> void:
	call_deferred("_emit_availability")
func _emit_availability() -> void:
	availability_changed.emit()
func _idle_available(runtime: Node) -> bool:
	# A stationary fallback can yield to an invitation, even with SOCIAL=0.
	return runtime.data.activity == Activity.Type.IDLE and (not runtime.intents.has_current_action() or runtime.intents.current_intent.reason_id == &"wander")
func valid_option(option: Dictionary) -> bool:
	if option.get("exact_target", false):
		var exact = get_runtime(option.target_id)
		if exact == null: return false
		if option.group_id != 0:
			return groups.has(option.group_id) and option.target_id in groups[option.group_id].participants and exact.data.activity == Activity.Type.TALKING
	if option.group_id != 0: return groups.has(option.group_id)
	var target = get_runtime(option.target_id)
	return target != null and _idle_available(target)
func option_position(option: Dictionary) -> Vector2:
	if option.group_id != 0 and groups.has(option.group_id):
		return groups[option.group_id].center
	return position_of(option.target_id)
func arrive(id: String, option: Dictionary) -> bool:
	if not valid_option(option): return false
	membership_changing.emit()
	var group
	if option.group_id != 0:
		group = groups[option.group_id]
	else:
		group = Group.new(_next_group_id, position_of(option.target_id))
		_next_group_id += 1
		groups[group.id] = group
		var target = get_runtime(option.target_id)
		if target.intents.current_intent.reason_id == &"wander": target.intents.cancel_current(target.intents.current_intent)
		var target_position: Vector2 = group.add_participant(option.target_id)
		get_runtime(option.target_id).social.begin_talking()
		get_runtime(option.target_id).social.position_in_conversation(target_position)
	var participant_position: Vector2 = group.add_participant(id)
	get_runtime(id).social.begin_talking()
	get_runtime(id).social.position_in_conversation(participant_position)
	membership_changed.emit()
	# Both members exist before start notifications; joining only notifies the newcomer.
	if option.group_id == 0: conversation_joined.emit(option.target_id)
	conversation_joined.emit(id)
	return true
func leave(id: String) -> void:
	var group = group_of(id)
	if group == null: return
	membership_changing.emit()
	group.remove_participant(id)
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

	membership_changed.emit()
