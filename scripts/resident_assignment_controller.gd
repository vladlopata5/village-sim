extends Node
## Adds candidates to the existing selector; never schedules or interrupts on enqueue.
const Assignment = preload("res://scripts/resident_assignment.gd")
const Utility = preload("res://scripts/action_utility.gd")
const Balance = preload("res://scripts/balance_config.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const NeedType = preload("res://scripts/need_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
var logger: EventLog
var _data: RefCounted
var _needs: Node
var _intents: Node
var _social: Node
var _clock: Node
var _conversation_id := 0
var _shared_since: Dictionary = {}
var _conversation_result_used := false
var _serial := 0
var active_assignment: Assignment
var _owned_intent: Intent

func setup(data: RefCounted, needs: Node, intents: Node, social: Node = null, clock: Node = null) -> void:
	_data = data
	_needs = needs
	_intents = intents
	_social = social
	_clock = clock
	if social != null:
		social.social_started.connect(_on_social_started)
		social.social_ended.connect(_on_social_ended)
		clock.minute_changed.connect(_check_talk_result)
	needs.eat_started.connect(_on_eat_started)
	needs.eat_outcome.connect(_on_eat_outcome)

func add(assignment: Assignment) -> bool:
	if assignment == null or assignment.resident_id != _data.id or assignment.type not in [Assignment.EAT_AT_TARGET, Assignment.TALK_TO]: return false
	if assignment.state != Assignment.State.QUEUED or not assignment.target is StringName: return false
	if not _target_exists(assignment): return false
	if assignment.id == &"":
		_serial += 1
		assignment.id = StringName("%s_assignment_%d" % [_data.id, _serial])
	if find(assignment.id) != null: return false
	_data.assignments.append(assignment)
	_data.notify_assignments_changed()
	if logger != null: logger.info(EventLog.PLAYER, "%s: добавлено поручение — %s" % [_data.resident_name, _label(assignment)])
	return true

func find(assignment_id: StringName):
	for assignment in _data.assignments:
		if assignment.id == assignment_id: return assignment
	return null

func collect_actions() -> Array:
	var actions: Array = []
	for assignment in _data.assignments:
		if assignment.state != Assignment.State.QUEUED: continue
		if not _target_exists(assignment):
			cancel(assignment.id)
			continue
		if not _available(assignment):
			if logger != null: logger.debug(EventLog.ASSIGNMENT, "%s: %s временно недоступно" % [_data.resident_name, assignment.type])
			continue
		actions.append({"id": "ASSIGNMENT:%s" % assignment.id, "priority": _base_utility(assignment) + Balance.ASSIGNMENT_BONUS})
	# Stable candidate order makes RNG independent of the UI/history list order.
	actions.sort_custom(func(a, b): return a.id < b.id)
	return actions

func start(assignment_id: StringName) -> bool:
	var assignment: Assignment = find(assignment_id)
	if assignment == null or assignment.state != Assignment.State.QUEUED or active_assignment != null: return false
	if not _available(assignment): return false
	_change_state(assignment, Assignment.State.ACTIVE)
	if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: начал поручение — %s" % [_data.resident_name, _label(assignment)])

	# Bonus is selector utility only; preserve the existing eat/schedule intent rules.
	var accepted := false
	if assignment.type == Assignment.TALK_TO:
		accepted = _social.try_social_at(assignment.target, roundi(_base_utility(assignment)))
	else:
		accepted = _needs.try_eat_at(assignment.target, roundi(_base_utility(assignment)))
	if not accepted and active_assignment == assignment:
		_requeue_assignment(assignment)
	return accepted

func cancel(assignment_id: StringName) -> bool:
	var assignment: Assignment = find(assignment_id)
	if assignment == null or assignment.state in [Assignment.State.COMPLETED, Assignment.State.CANCELLED]: return false
	var owns_execution := active_assignment == assignment
	var old := _owned_intent
	# Detach before executor cleanup emits callbacks or availability changes.
	_change_state(assignment, Assignment.State.CANCELLED)
	if owns_execution:
		if assignment.type == Assignment.TALK_TO: _social.cancel_social()
		else: _needs.cancel_eat(old)
	if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: поручение отменено — %s" % [_data.resident_name, _label(assignment)])
	return true

func _on_eat_started(intent: Intent) -> void:
	if active_assignment != null and active_assignment.type == Assignment.EAT_AT_TARGET and _owned_intent == null: _owned_intent = intent

func _on_eat_outcome(intent: Intent, outcome: StringName, target_id: StringName) -> void:
	if active_assignment == null or intent != _owned_intent:
		if outcome == &"completed": _complete_one_waiting_eat(target_id)
		return
	var assignment := active_assignment
	match outcome:
		&"completed":
			_complete_assignment(assignment, false)
		&"removed":
			_change_state(assignment, Assignment.State.CANCELLED)
			if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: поручение отменено — кухня удалена" % _data.resident_name)
		_:
			var message := ""
			if outcome == &"interrupted":
				var reason := "PlayerCommand" if _intents.player_controlled else "смена действия"
				message = "поручение приостановлено — прервано %s" % reason
			_requeue_assignment(assignment, message)

func _complete_one_waiting_eat(target_id: StringName) -> void:
	var assignment := _first_waiting_match(Assignment.EAT_AT_TARGET,
		func(task: Assignment): return task.target == target_id)
	if assignment != null: _complete_assignment(assignment, true)

func _first_waiting_match(type: StringName, matches: Callable) -> Assignment:
	# Chronological order is only a completion tie-break, never utility/FIFO.
	for assignment in _data.assignments:
		if assignment.type != type or assignment.state not in [Assignment.State.QUEUED, Assignment.State.SUSPENDED]: continue
		if matches.call(assignment): return assignment
	return null # Caller completes at most this one result instance.

func _change_state(assignment: Assignment, state: Assignment.State) -> void:
	assignment.state = state
	if state == Assignment.State.ACTIVE:
		active_assignment = assignment
		_owned_intent = null
	elif active_assignment == assignment:
		active_assignment = null
		_owned_intent = null
	_data.notify_assignments_changed()

func _requeue_assignment(assignment: Assignment, message: String = "") -> void:
	_change_state(assignment, Assignment.State.QUEUED)
	if logger != null and not message.is_empty():
		logger.info(EventLog.ASSIGNMENT, "%s: %s" % [_data.resident_name, message])

func _complete_assignment(assignment: Assignment, independent: bool) -> void:
	_change_state(assignment, Assignment.State.COMPLETED)
	if logger != null:
		var message := "поручение выполнено независимо" if independent else "поручение выполнено"
		logger.info(EventLog.ASSIGNMENT, "%s: %s — %s" % [_data.resident_name, message, _label(assignment)])

func _target_exists(assignment: Assignment) -> bool:
	if assignment.type == Assignment.EAT_AT_TARGET: return _needs.get_food_target(assignment.target) != null
	return is_instance_valid(_social) and is_instance_valid(_social.world) and String(assignment.target) != _data.id and _social.world.get_runtime(String(assignment.target)) != null

func _available(assignment: Assignment) -> bool:
	if not _target_exists(assignment): return false
	if assignment.type == Assignment.TALK_TO: return _social.has_target_action(assignment.target)
	return _needs.has_target_food_action(assignment.target)

func _base_utility(assignment: Assignment) -> float:
	if assignment.type == Assignment.TALK_TO: return float(_data.get_need(NeedType.Type.SOCIAL).get_priority())
	return Utility.eat(_data.hunger)

func _label(assignment: Assignment) -> String:
	if assignment.type == Assignment.TALK_TO:
		var target = _social.world.get_runtime(String(assignment.target)) if is_instance_valid(_social.world) else null
		return "Поговорить с %s" % (target.data.resident_name if target != null else String(assignment.target))
	return "Поесть здесь"

func bind_social_world() -> void:
	_social.world.membership_changing.connect(_check_talk_result)
	_social.world.membership_changed.connect(_sync_membership)
	_social.world.availability_changed.connect(_on_social_available)

func _on_social_started(intent: Intent) -> void:
	if active_assignment != null and active_assignment.type == Assignment.TALK_TO: _owned_intent = intent

func _on_social_ended() -> void:
	if active_assignment != null and active_assignment.type == Assignment.TALK_TO:
		_return_talk_to_waiting()
	_sync_membership()

func _return_talk_to_waiting() -> void:
	var assignment := active_assignment
	if _target_exists(assignment):
		_requeue_assignment(assignment, "поручение приостановлено — %s" % _label(assignment))
	else:
		_change_state(assignment, Assignment.State.CANCELLED)
		if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: поручение отменено — %s" % [_data.resident_name, _label(assignment)])

func _sync_membership() -> void:
	if not is_instance_valid(_social.world): return
	var group = _social.world.group_of(_data.id)
	var group_id: int = group.id if group != null else 0
	if group_id != _conversation_id:
		_conversation_id = group_id
		_shared_since.clear()
		_conversation_result_used = false
	var participants: Array = group.participants if group != null else []
	for id in _shared_since.keys():
		if id not in participants: _shared_since.erase(id)
	for id in participants:
		if id != _data.id and not _shared_since.has(id): _shared_since[id] = _clock.total_minutes
	if active_assignment != null and active_assignment.type == Assignment.TALK_TO and _data.activity == Activity.Type.TALKING:
		if String(active_assignment.target) not in participants: _return_talk_to_waiting()

func _check_talk_result(_minute: int = 0) -> void:
	if _conversation_id == 0 or _conversation_result_used: return
	# Membership-changing checkpoints run before departure, including the 15-minute boundary.
	if active_assignment != null and active_assignment.type == Assignment.TALK_TO:
		if _shared_long_enough(active_assignment):
			var assignment := active_assignment
			_conversation_result_used = true
			_complete_assignment(assignment, false)
		return
	var waiting_assignment := _first_waiting_match(Assignment.TALK_TO, _shared_long_enough)
	if waiting_assignment != null:
		_conversation_result_used = true
		_complete_assignment(waiting_assignment, true)

func _shared_long_enough(assignment: Assignment) -> bool:
	var id := String(assignment.target)
	return _target_exists(assignment) and _shared_since.has(id) and _clock.total_minutes - int(_shared_since[id]) >= Balance.MIN_CONVERSATION_MINUTES

func _on_social_available() -> void:
	for assignment in _data.assignments:
		if assignment.type == Assignment.TALK_TO and assignment.state not in [Assignment.State.COMPLETED, Assignment.State.CANCELLED] and not _target_exists(assignment):
			cancel(assignment.id)
	# World changes unlock a future normal choice, never interrupt committed activity.
	if _intents.has_current_action() or _data.activity != Activity.Type.IDLE: return
	for assignment in _data.assignments:
		if assignment.type == Assignment.TALK_TO and assignment.state == Assignment.State.QUEUED and _available(assignment):
			_social.runtime.decision.request_decision("social_available")
			return

func describe_assignment(assignment_id: StringName) -> String:
	var assignment: Assignment = find(assignment_id)
	if assignment == null: return ""
	if assignment.type == Assignment.EAT_AT_TARGET:
		var kitchen = _needs.get_food_target(assignment.target)
		return "Поесть — %s" % (kitchen.display_name if kitchen != null else "Место недоступно")
	return _label(assignment)
