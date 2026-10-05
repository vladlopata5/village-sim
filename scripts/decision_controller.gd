extends Node
## Event-driven decision points, never a per-frame AI loop.
const NeedType = preload("res://scripts/need_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const NEED_ACTION_THRESHOLD := 1000
const WORK_PRIORITY := 7000
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
var decision_count := 0
var social: Node
var work_available: Callable

func setup(clock: Node, data: RefCounted, intents: Node, needs: Node, schedule: Node) -> void:
	_clock = clock
	_data = data
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
	needs.action_unavailable.connect(request_decision.bind("unavailable"))
	needs.food_available.connect(_on_food_available)
	_next_decision_at = clock.total_minutes + IDLE_MINUTES
	# Startup is an idle segment; first ordinary decision after ten game minutes.
	check_critical()

func check_critical() -> void:
	if _data.hunger < 100: _critical_hunger_attempted = false
	if _deciding:
		_critical_pending = true
		return
	_deciding = true
	if _data.hunger == 100 and not _critical_hunger_attempted and _intents.forced_priority <= CRITICAL_HUNGER:
		_critical_hunger_attempted = true
		_needs.try_eat(_data.get_need(NeedType.Type.HUNGER).get_priority(), CRITICAL_HUNGER)
	if _data.fatigue == 100 and _intents.forced_priority < CRITICAL_FATIGUE:
		_needs.try_rest(0, CRITICAL_FATIGUE)
	_deciding = false
	if _critical_pending:
		_critical_pending = false
		check_critical()

func prepare_for_work() -> bool:
	if _deciding: return not _intents.has_current_action() or _intents.current_intent.reason_id == &"day_work"
	check_critical()
	if _intents.has_current_action():
		# A phase/work source may replace its own route or a manual test command.
		# A rising ordinary need never re-plans an already started route.
		return _intents.forced_priority == 0 and _intents.current_intent.reason_id in [&"day_work", &"manual_move"]
	if _intents.forced_priority > 0 or _data.activity in [Activity.Type.EATING, Activity.Type.RESTING, Activity.Type.SLEEPING]:
		return false
	var available := _has_work()
	return not _choose_need(available) and available

func _choose_need(work_available: bool) -> bool:
	if _deciding: return false
	_deciding = true
	decision_count += 1
	var types: Array = [NeedType.Type.HUNGER, NeedType.Type.FATIGUE, NeedType.Type.SOCIAL, NeedType.Type.LEISURE]
	types.sort_custom(func(a, b):
		var a_priority: int = _data.get_need(a).get_priority()
		var b_priority: int = _data.get_need(b).get_priority()
		return a < b if a_priority == b_priority else a_priority > b_priority)
	var started := false
	for type in types:
		var priority: int = _data.get_need(type).get_priority()
		if priority < NEED_ACTION_THRESHOLD or (work_available and priority <= WORK_PRIORITY): continue
		match type:
			NeedType.Type.HUNGER: started = _needs.try_eat(priority)
			NeedType.Type.FATIGUE: started = _needs.try_rest(priority)
			NeedType.Type.SOCIAL: started = is_instance_valid(social) and social.try_social(priority)
			NeedType.Type.LEISURE: started = is_instance_valid(social) and social.try_leisure(priority)
		if started: break
	_deciding = false
	_critical_pending = false
	check_critical()
	return started

func request_decision(_reason: String = "free") -> void:
	if _deciding: return
	check_critical()
	if _intents.has_current_action() or _data.activity == Activity.Type.SLEEPING: return
	_next_decision_at = _clock.total_minutes + IDLE_MINUTES
	if _clock.get_phase() == "Ночь":
		_schedule.resume_current_phase()
		return
	var available: bool = _clock.get_phase() == "День" and _has_work()
	if _choose_need(available): return
	if available: _schedule.resume_current_phase()
	else: _data.activity = Activity.Type.IDLE

func _on_completed(intent: Intent) -> void:
	_next_decision_at = _clock.total_minutes + IDLE_MINUTES
	if intent.reason_id == &"day_work" or _data.activity == Activity.Type.SLEEPING: return
	request_decision("completed")

func _on_minute(minute: int) -> void:
	if minute >= _next_decision_at and not _intents.has_current_action() and _data.activity in [Activity.Type.IDLE, Activity.Type.WORKING]:
		# Standing work/idle is a ten-minute segment; this is its completion.
		_data.activity = Activity.Type.IDLE
		request_decision("segment_completed")

func _on_phase(_phase: String) -> void:
	request_decision("phase_changed")

func _on_food_available() -> void:
	if _data.hunger == 100 and _intents.forced_priority != CRITICAL_HUNGER:
		_critical_hunger_attempted = false
		check_critical()
	elif not _intents.has_current_action() and _data.activity == Activity.Type.IDLE:
		request_decision("new_food_option")

func _has_work() -> bool:
	if _data.work_location_id.is_empty() or not _needs.has_location(_data.work_location_id): return false
	if work_available.is_valid(): return work_available.call()
	return not _data.work_location_id.is_empty()
