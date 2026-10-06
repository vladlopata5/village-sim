extends Node
## Adds candidates to the existing selector; never schedules or interrupts on enqueue.
const Assignment = preload("res://scripts/resident_assignment.gd")
const Utility = preload("res://scripts/action_utility.gd")
const Balance = preload("res://scripts/balance_config.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const Intent = preload("res://scripts/resident_intent.gd")
var logger: EventLog
var _data: RefCounted
var _needs: Node
var _intents: Node
var _serial := 0
var active_assignment: Assignment
var _owned_intent: Intent

func setup(data: RefCounted, needs: Node, intents: Node) -> void:
	_data = data
	_needs = needs
	_intents = intents
	needs.eat_started.connect(_on_eat_started)
	needs.eat_outcome.connect(_on_eat_outcome)

func add(assignment: Assignment) -> bool:
	if assignment == null or assignment.resident_id != _data.id or assignment.type != Assignment.EAT_AT_TARGET: return false
	if assignment.state != Assignment.State.QUEUED or not assignment.target is StringName: return false
	if _needs.get_food_target(assignment.target) == null: return false
	if assignment.id == &"":
		_serial += 1
		assignment.id = StringName("%s_assignment_%d" % [_data.id, _serial])
	if find(assignment.id) != null: return false
	_data.assignments.append(assignment)
	if logger != null: logger.info(EventLog.PLAYER, "%s: добавлено поручение — Поесть здесь (%s)" % [_data.resident_name, _needs.get_food_target(assignment.target).display_name])
	return true

func find(assignment_id: StringName):
	for assignment in _data.assignments:
		if assignment.id == assignment_id: return assignment
	return null

func collect_actions() -> Array:
	var actions: Array = []
	for assignment in _data.assignments:
		if assignment.state != Assignment.State.QUEUED: continue
		if _needs.get_food_target(assignment.target) == null:
			cancel(assignment.id)
			continue
		if not _needs.has_target_food_action(assignment.target):
			if logger != null: logger.debug(EventLog.ASSIGNMENT, "%s: EAT_AT_TARGET временно недоступно — FOOD, голод или место" % _data.resident_name)
			continue
		actions.append({"id": "ASSIGNMENT:%s" % assignment.id, "priority": Utility.eat(_data.hunger) + Balance.ASSIGNMENT_BONUS})
	# Stable candidate order makes RNG independent of the UI/history list order.
	actions.sort_custom(func(a, b): return a.id < b.id)
	return actions

func start(assignment_id: StringName) -> bool:
	var assignment: Assignment = find(assignment_id)
	if assignment == null or assignment.state != Assignment.State.QUEUED or active_assignment != null: return false
	if not _needs.has_target_food_action(assignment.target): return false
	assignment.state = Assignment.State.ACTIVE
	active_assignment = assignment
	if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: начал поручение — Поесть здесь" % _data.resident_name)

	# Bonus is selector utility only; preserve the existing eat/schedule intent rules.
	var accepted: bool = _needs.try_eat_at(assignment.target, roundi(Utility.eat(_data.hunger)))
	if not accepted and active_assignment == assignment:
		assignment.state = Assignment.State.QUEUED
		active_assignment = null
		_owned_intent = null
	return accepted

func cancel(assignment_id: StringName) -> bool:
	var assignment: Assignment = find(assignment_id)
	if assignment == null or assignment.state in [Assignment.State.COMPLETED, Assignment.State.CANCELLED]: return false
	assignment.state = Assignment.State.CANCELLED
	if active_assignment == assignment:
		var old := _owned_intent
		active_assignment = null
		_owned_intent = null
		_needs.cancel_eat(old)
	if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: поручение отменено — Поесть здесь" % _data.resident_name)
	return true

func _on_eat_started(intent: Intent) -> void:
	if active_assignment != null and _owned_intent == null: _owned_intent = intent

func _on_eat_outcome(intent: Intent, outcome: StringName, target_id: StringName) -> void:
	if active_assignment == null or intent != _owned_intent:
		if outcome == &"completed": _complete_one_waiting_eat(target_id)
		return
	var assignment := active_assignment
	active_assignment = null
	_owned_intent = null
	match outcome:
		&"completed":
			_complete_eat_assignment(assignment, false)
		&"removed":
			assignment.state = Assignment.State.CANCELLED
			if logger != null: logger.info(EventLog.ASSIGNMENT, "%s: поручение отменено — кухня удалена" % _data.resident_name)
		_:
			assignment.state = Assignment.State.QUEUED
			if logger != null and outcome == &"interrupted":
				var reason := "PlayerCommand" if _intents.player_controlled else "смена действия"
				logger.info(EventLog.ASSIGNMENT, "%s: поручение приостановлено — прервано %s" % [_data.resident_name, reason])

func _complete_one_waiting_eat(target_id: StringName) -> void:
	# Chronological order is only a completion tie-break, never action utility/FIFO.
	for assignment in _data.assignments:
		if assignment.type != Assignment.EAT_AT_TARGET or assignment.target != target_id: continue
		if assignment.state not in [Assignment.State.QUEUED, Assignment.State.SUSPENDED]: continue
		_complete_eat_assignment(assignment, true)
		return # One paid, finished meal can satisfy at most one result instance.

func _complete_eat_assignment(assignment: Assignment, independent: bool) -> void:
	assignment.state = Assignment.State.COMPLETED
	if logger != null:
		var message := "поручение выполнено независимо" if independent else "поручение выполнено"
		logger.info(EventLog.ASSIGNMENT, "%s: %s — Поесть здесь" % [_data.resident_name, message])
