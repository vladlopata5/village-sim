extends Node
## One current and at most one pending intent; no task queue.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Activity = preload("res://scripts/resident_activity.gd")
signal forced_interrupt(previous: ResidentIntent)
var _forced_intent: ResidentIntent
var forced_priority: int = 0
var player_controlled := false
signal intent_changed(intent: ResidentIntent)
signal intent_arrived(intent: ResidentIntent)
signal intent_completed(intent: ResidentIntent)
var resident_data: ResidentData
var current_intent: ResidentIntent = ResidentIntent.new()
var pending_intent: ResidentIntent = ResidentIntent.new()

func setup(data: ResidentData) -> void:
	resident_data = data

func _set_activity(activity: Activity.Type) -> void:
	if resident_data != null:
		resident_data.activity = activity

func _activate(intent: ResidentIntent) -> void:
	current_intent = intent
	var activity := Activity.Type.IDLE
	if intent.type != ResidentIntent.Type.NONE:
		activity = Activity.Type.MOVING
		if resident_data != null and resident_data.inventory.amount > 0:
			activity = Activity.Type.HAULING
	_set_activity(activity)
	intent_changed.emit(current_intent)

func submit(intent: ResidentIntent) -> bool:
	if _forced_intent != null or intent == null or (intent.type == ResidentIntent.Type.NONE and intent.reason_id.is_empty()):
		return false
	if not has_current_action():
		_activate(intent)
		return true
	var same_source_update := intent.priority == current_intent.priority and intent.reason_id == current_intent.reason_id
	if current_intent.interruptible:
		if intent.priority <= current_intent.priority and not same_source_update:
			return false
		_activate(intent)
		return true
	if intent.priority <= current_intent.priority:
		return false
	if pending_intent.type != ResidentIntent.Type.NONE:
		var pending_update := intent.priority == pending_intent.priority and intent.reason_id == pending_intent.reason_id
		if intent.priority <= pending_intent.priority and not pending_update:
			return false
	pending_intent = intent
	return true

func report_arrival(arrived_intent: ResidentIntent) -> bool:
	if current_intent.type == ResidentIntent.Type.NONE or arrived_intent != current_intent:
		return false
	# The decision source may retain the intent as a noninterruptible action.
	intent_arrived.emit(arrived_intent)
	if current_intent == arrived_intent and arrived_intent.interruptible:
		clear_completed(arrived_intent)
	return true

func clear_completed(completed_intent: ResidentIntent) -> bool:
	if not has_current_action() or completed_intent != current_intent:
		return false
	if completed_intent == _forced_intent:
		_forced_intent = null
		forced_priority = 0
		player_controlled = false
	var next := pending_intent
	pending_intent = ResidentIntent.new()
	_activate(next)
	intent_completed.emit(completed_intent)
	return true

func clear_reason(reason_id: StringName) -> void:
	# Expired phase goals must also be removed from the pending slot.
	if pending_intent.reason_id == reason_id:
		pending_intent = ResidentIntent.new()
	if current_intent.type != ResidentIntent.Type.NONE and current_intent.reason_id == reason_id and current_intent.interruptible and current_intent != _forced_intent:
		var next := pending_intent
		pending_intent = ResidentIntent.new()
		_activate(next)

func continue_intent(previous: ResidentIntent, next: ResidentIntent) -> bool:
	# Same action, next movement stage: preserve its pending higher priority goal.
	if player_controlled: return false
	if previous != current_intent or previous.type == ResidentIntent.Type.NONE or next == null or next.type != ResidentIntent.Type.MOVE_TO:
		return false
	if previous == _forced_intent:
		_forced_intent = next
	_activate(next)
	return true

func begin_player_intent(intent: ResidentIntent) -> bool:
	if intent == null: return false
	player_controlled = true # Lock before any reservation cleanup emits world events.
	return _replace_forced(intent, 0)

func retain_current_as_critical(intent: ResidentIntent, critical_priority: int) -> bool:
	# Protect compatible execution without reactivation, interrupt signals or lost pending.
	if player_controlled or intent == null or intent != current_intent: return false
	if critical_priority < forced_priority or (_forced_intent != null and _forced_intent != intent): return false
	_forced_intent = intent
	forced_priority = critical_priority
	return true

func force_set_intent(intent: ResidentIntent, critical_priority: int = 1) -> bool:
	if player_controlled: return false
	if intent == null or (_forced_intent != null and critical_priority < forced_priority):
		return false
	return _replace_forced(intent, critical_priority)

func _replace_forced(intent: ResidentIntent, critical_priority: int) -> bool:
	var previous := current_intent
	forced_priority = critical_priority
	pending_intent = ResidentIntent.new()
	_forced_intent = intent # Reject ordinary submissions during cleanup too.
	forced_interrupt.emit(previous)
	if _forced_intent != intent:
		return false # A newer critical action won during synchronous cleanup.
	_activate(intent)
	if intent.type == ResidentIntent.Type.NONE and intent.reason_id.is_empty():
		_forced_intent = null
		forced_priority = 0
	return true

func has_current_action() -> bool:
	# NONE with a reason is a stationary action, without adding movement types.
	return current_intent.type != ResidentIntent.Type.NONE or not current_intent.reason_id.is_empty()

func cancel_current(intent: ResidentIntent) -> bool:
	if player_controlled: return false
	if intent != current_intent:
		return false
	if intent == _forced_intent:
		_forced_intent = null
		forced_priority = 0
		player_controlled = false
	var next := pending_intent
	pending_intent = ResidentIntent.new()
	_activate(next)
	return true
