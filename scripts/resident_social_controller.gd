extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Concrete SOCIAL and LEISURE actions, separate from selection of a need.
const Activity = preload("res://scripts/resident_activity.gd")
const NeedType = preload("res://scripts/need_type.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Choice = preload("res://scripts/weighted_choice.gd")
const Balance = preload("res://scripts/balance_config.gd")
signal conversation_position_requested(position: Vector2)
var world: Node
var runtime: Node
var clock: Node
var rng := RandomNumberGenerator.new()
var _active: Intent
var _option: Dictionary = {}
var _started_at := 0
var _next_conversation_recheck := 0
func setup(owner_runtime: Node, game_clock: Node) -> void:
	runtime = owner_runtime
	clock = game_clock
	rng.seed = runtime.data.id.hash()
	clock.minute_changed.connect(_on_minute)
	runtime.intents.intent_arrived.connect(_on_arrival)
	runtime.intents.intent_changed.connect(_on_intent_changed)
func position_in_conversation(position: Vector2) -> void:
	conversation_position_requested.emit(position)
func has_social_action() -> bool:
	return is_instance_valid(world) and not world.options_for(runtime.data.id).is_empty()
func try_social(priority: int) -> bool:
	if world == null: return false
	var option = Choice.pick(world.options_for(runtime.data.id), rng)
	if option == null: return false
	_option = option
	_active = Intent.new(Intent.Type.MOVE_TO, &"social", world.option_position(option), priority, true)
	if not runtime.intents.submit(_active):
		_active = null
		_option = {}
		return false
	if logger != null: logger.sync_activity(runtime.data)
	return true
func try_leisure(priority: int) -> bool:
	_active = Intent.new(Intent.Type.NONE, &"leisure", Vector2.ZERO, priority, false)
	if not runtime.intents.submit(_active):
		_active = null
		return false
	_started_at = clock.total_minutes
	runtime.data.activity = Activity.Type.RELAXING
	if logger != null:
		logger.sync_activity(runtime.data)
		logger.info(EventLog.LEISURE, "%s: начал отдыхать (LEISURE=%d, priority=%d)" % [runtime.data.resident_name, runtime.data.get_need(NeedType.Type.LEISURE).value, runtime.data.get_need(NeedType.Type.LEISURE).get_priority()])
	return true
func begin_talking() -> void:
	# The waiting IDLE participant also owns an independent current action.
	if _active == null:
		_active = Intent.new(Intent.Type.NONE, &"social", Vector2.ZERO,
			runtime.data.get_need(NeedType.Type.SOCIAL).get_priority(), false)
		runtime.intents.submit(_active)
	_active.interruptible = false
	_started_at = clock.total_minutes
	_next_conversation_recheck = _started_at + Balance.MIN_CONVERSATION_MINUTES
	runtime.data.activity = Activity.Type.TALKING
	if logger != null:
		logger.sync_activity(runtime.data)
		logger.info(EventLog.SOCIAL, "%s: начал разговор (SOCIAL=%d, priority=%d)" % [runtime.data.resident_name, runtime.data.get_need(NeedType.Type.SOCIAL).value, runtime.data.get_need(NeedType.Type.SOCIAL).get_priority()])
func _on_arrival(intent: Intent) -> void:
	if intent != _active or intent.reason_id != &"social": return
	if not world.arrive(runtime.data.id, _option): _finish()
func _on_minute(minute: int) -> void:
	if _active == null: return
	var activity = runtime.data.activity
	if activity == Activity.Type.MOVING:
		if not world.valid_option(_option): _finish()
	elif activity == Activity.Type.TALKING:
		_recheck_conversation(minute)
	elif activity == Activity.Type.RELAXING:
		if minute - _started_at >= Balance.RELAX_DURATION_MINUTES: _finish()
func _on_intent_changed(intent: Intent) -> void:
	if _active != null and intent != _active:
		_log_relax_end(_active, true)
		_active = null
		_option = {}
		if world != null: world.leave(runtime.data.id)
func _finish() -> void:
	var previous = _active
	_log_relax_end(previous, false)
	_active = null
	_option = {}
	if world != null: world.leave(runtime.data.id)
	if previous != null: runtime.intents.clear_completed(previous)
func _log_relax_end(intent: Intent, interrupted: bool) -> void:
	if intent != null and intent.reason_id == &"leisure" and logger != null:
		logger.info(EventLog.LEISURE, "%s: закончил отдыхать%s" % [runtime.data.resident_name, " (прервано)" if interrupted else ""])
func group_dissolved() -> void:
	if runtime.data.activity == Activity.Type.TALKING and world.group_of(runtime.data.id) == null: _finish()
func _exit_tree() -> void:
	if is_instance_valid(world): world.leave(runtime.data.id)

func _recheck_conversation(minute: int) -> void:
	var elapsed := minute - _started_at
	if elapsed >= Balance.MAX_CONVERSATION_MINUTES:
		if logger != null: logger.debug(EventLog.SOCIAL, "%s: выходит — максимальная длительность" % runtime.data.resident_name)
		_finish()
		return
	if minute < _next_conversation_recheck: return
	_next_conversation_recheck = minute + Balance.CONVERSATION_RECHECK_MINUTES
	var current_priority: int = runtime.data.get_need(NeedType.Type.SOCIAL).get_priority()
	var important: bool = runtime.decision.has_more_important_action(current_priority)
	var satisfied := current_priority < Balance.NEED_ACTION_THRESHOLD
	var voluntary := satisfied and rng.randf() < Balance.CONVERSATION_EXIT_CHANCE
	if logger != null:
		logger.debug(EventLog.SOCIAL, "%s: %s разговор (%d мин); более важное действие=%s; случайный выход=%s" % [runtime.data.resident_name, "завершает" if important or voluntary else "продолжает", elapsed, important, voluntary])
	if important or voluntary: _finish()
