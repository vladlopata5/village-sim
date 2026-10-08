extends Node
signal work_cycle_started(building_id: StringName)
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Event-driven decision points, never a per-frame AI loop.
const NeedType = preload("res://scripts/need_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Selector = preload("res://scripts/utility_selector.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Balance = preload("res://scripts/balance_config.gd")
const NEED_ACTION_THRESHOLD := Balance.NEED_ACTION_THRESHOLD
const WORK_PRIORITY := Balance.WORK_PRIORITY
const CRITICAL_HUNGER := 200
const CRITICAL_FATIGUE := 100
const IDLE_MINUTES := 10
var _data: RefCounted
var _clock: Node
var _intents: Node
var _needs: Node
var _schedule: Node
var _deciding := false
var _critical_pending := false
var _critical_hunger_attempted := false
var _next_decision_at := 0
var _work_cycle_active := false
var _work_cycle_ends_at := 0
var _work_assignment: Dictionary = {}
var decision_count := 0
var assignments: Node
var social: Node
var wander: Node
var rng := RandomNumberGenerator.new()
var last_selection: Dictionary = {}
var _work_selected := false
var work_available: Callable
var work_request: Callable

func setup(clock: Node, data: RefCounted, intents: Node, needs: Node, schedule: Node) -> void:
	_clock = clock
	_data = data
	rng.seed = data.id.hash()
	_intents = intents
	_needs = needs
	_schedule = schedule
	needs.decision = self
	schedule.before_work = prepare_for_work
	data.hunger_changed.connect(check_critical)
	data.fatigue_changed.connect(check_critical)
	clock.minute_changed.connect(_on_minute)
	clock.phase_changed.connect(_on_phase)
	intents.intent_completed.connect(_on_completed)
	intents.intent_changed.connect(_on_intent_changed)
	needs.action_unavailable.connect(request_decision.bind("unavailable"))
	needs.food_available.connect(_on_food_available)
	_next_decision_at = clock.total_minutes + IDLE_MINUTES
	# Startup is an idle segment; first ordinary decision after ten game minutes.
	check_critical()

func check_critical() -> void:
	if _intents.player_controlled: return
	if _data.hunger < 100: _critical_hunger_attempted = false
	if _deciding:
		_critical_pending = true
		return
	_deciding = true
	if _data.hunger == 100 and not _critical_hunger_attempted and _intents.forced_priority <= CRITICAL_HUNGER:
		_critical_hunger_attempted = true
		if logger != null: logger.info(EventLog.NEED, "%s: критический голод — принудительное действие" % _data.resident_name)
		_needs.try_eat(_data.get_need(NeedType.Type.HUNGER).get_priority(), CRITICAL_HUNGER)
	if _data.fatigue == 100 and _intents.forced_priority < CRITICAL_FATIGUE:
		if logger != null: logger.info(EventLog.NEED, "%s: критическая усталость — принудительный сон" % _data.resident_name)
		_needs.try_rest(0, CRITICAL_FATIGUE)
	_deciding = false
	if _critical_pending:
		_critical_pending = false
		check_critical()

func prepare_for_work() -> bool:
	# The normal selector already chose WORK; do not draw again while starting it.
	if _work_selected:
		_work_selected = false
		check_critical()
		return _intents.forced_priority == 0 and not _intents.has_current_action()
	if _deciding: return not _intents.has_current_action() or _intents.current_intent.reason_id == &"day_work"
	check_critical()
	if _intents.has_current_action():
		# A phase/work source may replace its own route or a manual test command.
		# A rising ordinary need never re-plans an already started route.
		return _intents.forced_priority == 0 and _intents.current_intent.reason_id in [&"day_work", &"manual_move"]
	if _intents.forced_priority > 0 or _data.activity in [Activity.Type.EATING, Activity.Type.RESTING, Activity.Type.SLEEPING]:
		return false
	var available := _has_work()
	var personal_started := _choose_need(available)
	_work_selected = false
	return not personal_started and available

func collect_actions(has_available_work: bool) -> Array:
	# Read-only availability. No resource reservations or job claims here.
	var actions: Array = []
	if has_available_work: actions.append({"id": "WORK", "priority": Modifiers.action_utility(_data, Modifiers.Action.WORK, WORK_PRIORITY)})
	for type in [NeedType.Type.HUNGER, NeedType.Type.FATIGUE, NeedType.Type.SOCIAL, NeedType.Type.LEISURE]:
		var priority: int = _data.get_need(type).get_priority()
		if priority < NEED_ACTION_THRESHOLD: continue
		var id := ""
		match type:
			NeedType.Type.HUNGER:
				if _needs.has_food_action():
					id = "EAT"
			NeedType.Type.FATIGUE: id = "REST"
			NeedType.Type.SOCIAL:
				if is_instance_valid(social) and social.has_social_action(): id = "SOCIAL"
			NeedType.Type.LEISURE:
				if is_instance_valid(social): id = "LEISURE"
		if not id.is_empty():
			var effective: float = Modifiers.eat_utility(_data) if id == "EAT" else float(priority)
			if id == "SOCIAL": effective = Modifiers.action_utility(_data, Modifiers.Action.SOCIAL, effective)
			actions.append({"id": id, "priority": effective})
	if is_instance_valid(wander) and wander.has_action(): actions.append({"id": "WANDER", "priority": Balance.WANDER_PRIORITY})
	if is_instance_valid(assignments): actions.append_array(assignments.collect_actions())
	return actions

func _choose_need(has_available_work: bool) -> bool:
	if _deciding: return false
	_deciding = true
	_work_selected = false
	decision_count += 1
	# Preserve one event-driven failure report, but never put unavailable EAT in the pool.
	if _needs.can_try_eat() and not _needs.has_food_action():
		_needs.try_eat(_data.get_need(NeedType.Type.HUNGER).get_priority())
	var actions := collect_actions(has_available_work)
	var started := false
	while not actions.is_empty():
		last_selection = Selector.evaluate(actions, Modifiers.selector_candidate_ratio(_data), Modifiers.selector_random_exponent(_data))
		var selected: Dictionary = Selector.pick(last_selection, rng)
		var unavailable: Array = []
		for id in ["WORK", "EAT", "REST", "SOCIAL", "LEISURE", "WANDER"]:
			if not actions.any(func(row): return row.id == id): unavailable.append(id)
		if logger != null and logger.debug_enabled: logger.debug(EventLog.AI, _decision_debug_text(selected.id, unavailable))
		var priority := roundi(selected.priority)
		match selected.id:
			"WORK":
				_work_selected = true
				if logger != null: logger.info(EventLog.AI, "%s: выбрал работу (priority=%d)" % [_data.resident_name, priority])
				break
			"EAT": started = _needs.try_eat(priority)
			"REST": started = _needs.try_rest(priority)
			"SOCIAL": started = social.try_social(priority)
			"LEISURE": started = social.try_leisure(priority)
			"WANDER": started = wander.try_wander(priority)
			_:
				if selected.id.begins_with("ASSIGNMENT:"):
					started = assignments.start(StringName(selected.id.trim_prefix("ASSIGNMENT:")))
		if started: break
		# A synchronous world change can invalidate an action between check and start.
		actions = actions.filter(func(row): return row.id != selected.id)
	if actions.is_empty():
		last_selection = Selector.evaluate([], Modifiers.selector_candidate_ratio(_data), Modifiers.selector_random_exponent(_data))
		if logger != null and logger.debug_enabled: logger.debug(EventLog.AI, _decision_debug_text("IDLE", ["WORK", "EAT", "REST", "SOCIAL", "LEISURE", "WANDER"]))
	_deciding = false
	_critical_pending = false
	check_critical()
	return started

func _decision_debug_text(selected: String, unavailable: Array) -> String:
	var text: String = Selector.debug_text(_data.resident_name, last_selection, selected, unavailable)
	return text.replace("EAT priority=", "EAT hunger=%d utility=" % _data.hunger)

func request_decision(_reason: String = "free") -> void:
	if _intents.player_controlled: return
	if _deciding: return
	if _work_cycle_active and _data.activity == Activity.Type.WORKING: return
	if not _intents.has_current_action() and _data.hunger == 100 and _needs.has_food_action():
		_critical_hunger_attempted = false
	check_critical()
	if _intents.has_current_action() or _data.activity == Activity.Type.SLEEPING: return
	if _clock.get_phase() != _schedule.get_phase(): return # phase_changed owns this boundary.
	_next_decision_at = _clock.total_minutes + IDLE_MINUTES
	if _clock.get_phase() == "Ночь":
		_schedule.resume_current_phase()
		return
	var available: bool = _clock.get_phase() == "День" and _has_work()
	if _choose_need(available) or _intents.has_current_action(): return
	if available:
		if work_request.is_valid():
			_deciding = true
			_work_selected = false
			var started: bool = work_request.call()
			_deciding = false
			check_critical()
			if started and logger != null: logger.info(EventLog.AI, "%s: выбрал рабочую задачу" % _data.resident_name)
			if started or _intents.has_current_action(): return
			# A job may have been claimed by someone else since availability was checked.
			if _choose_need(false) or _intents.has_current_action(): return
		else:
			_schedule.resume_current_phase()
			return
	_data.activity = Activity.Type.IDLE
	if logger != null: logger.sync_activity(_data)

func _on_completed(intent: Intent) -> void:
	if intent.reason_id == &"player_move": _critical_hunger_attempted = false
	_next_decision_at = _clock.total_minutes + IDLE_MINUTES
	if intent.reason_id == &"day_work" and _data.activity == Activity.Type.WORKING:
		if not _work_assignment.is_empty() and (_work_assignment.profession != _data.profession or _work_assignment.location_id != _data.work_location_id):
			_data.activity = Activity.Type.IDLE
			_work_assignment = {}
			request_decision("work_assignment_changed_during_route")
			return
		_work_cycle_active = true
		_work_cycle_ends_at = _clock.total_minutes + Balance.WORK_CYCLE_MINUTES
		work_cycle_started.emit(_work_assignment.get("location_id", _data.work_location_id))
		if logger != null: logger.info(EventLog.AI, "%s: начал рабочий цикл (%d мин)" % [_data.resident_name, Balance.WORK_CYCLE_MINUTES])
		return
	if _data.activity == Activity.Type.SLEEPING: return
	request_decision("completed")

func _end_work_cycle(reason: String) -> void:
	if not _work_cycle_active: return
	_work_cycle_active = false
	if logger != null: logger.info(EventLog.AI, "%s: завершил рабочий цикл — %s" % [_data.resident_name, reason])

func get_committed_work_assignment() -> Dictionary:
	return _work_assignment if _work_cycle_active and _data.activity == Activity.Type.WORKING else {}

func _on_intent_changed(_intent: Intent) -> void:
	if _data.activity != Activity.Type.WORKING: _end_work_cycle("смена действия")

func capture_work_assignment(intent: Intent, resident: RefCounted) -> void:
	# Run before the executor: a resident already at the goal can arrive synchronously.
	if intent.reason_id == &"day_work":
		_work_assignment = {"profession": resident.profession, "location_id": resident.work_location_id}

func _on_minute(minute: int) -> void:
	if _clock.get_phase() != _schedule.get_phase(): return # Await the phase source, not an old schedule.
	if _work_cycle_active:
		if _data.activity != Activity.Type.WORKING:
			_end_work_cycle("перерыв или смена расписания")
		elif minute >= _work_cycle_ends_at:
			var gathering_cycle: bool = _work_assignment.get("profession", Profession.Type.NONE) == Profession.Type.GATHERER
			_end_work_cycle("%d минут фактической работы" % Balance.WORK_CYCLE_MINUTES)
			_data.activity = Activity.Type.IDLE
			if gathering_cycle: _data.add_skill_xp(Skill.Type.GATHERING, 1)
			request_decision("work_cycle_completed")
		return
	if minute >= _next_decision_at and not _intents.has_current_action() and _data.activity == Activity.Type.IDLE:
		request_decision("idle_completed")

func _on_phase(phase: String) -> void:
	if phase != "День": _end_work_cycle("смена распорядка")
	request_decision("phase_changed")

func _on_food_available() -> void:
	if not _needs.has_food_action(): return
	# A changed world is an option for the next normal boundary, not a forced event.
	if _deciding or _intents.has_current_action() or _data.activity != Activity.Type.IDLE: return
	if _data.get_need(NeedType.Type.HUNGER).get_priority() < NEED_ACTION_THRESHOLD: return
	if logger != null: logger.info(EventLog.NEED, "%s: FOOD стала доступна — новая decision point" % _data.resident_name)
	request_decision("food_available")

func has_more_important_action(current_priority: int) -> bool:
	# Read-only availability comparison; it never starts an action or claims a job.
	if _intents.pending_intent.reason_id != &"" and _intents.pending_intent.priority > current_priority: return true
	if _clock.get_phase() == "День" and _has_work() and Modifiers.action_utility(_data, Modifiers.Action.WORK, WORK_PRIORITY) > current_priority: return true
	for type in [NeedType.Type.HUNGER, NeedType.Type.FATIGUE, NeedType.Type.LEISURE]:
		var priority: float = Modifiers.eat_utility(_data) if type == NeedType.Type.HUNGER else _data.get_need(type).get_priority()
		if priority <= current_priority: continue
		if type != NeedType.Type.HUNGER and priority < NEED_ACTION_THRESHOLD: continue
		if type != NeedType.Type.HUNGER or _needs.has_food_action(): return true
	return false

func _has_work() -> bool:
	if _data.profession == preload("res://scripts/resident_profession.gd").Type.BUILDER:
		return work_available.is_valid() and work_available.call()
	if _data.work_location_id.is_empty() or not _needs.has_location(_data.work_location_id): return false
	if work_available.is_valid(): return work_available.call()
	return not _data.work_location_id.is_empty()
