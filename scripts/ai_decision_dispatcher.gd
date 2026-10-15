extends Node
## One ordinary planning queue. Claims/completion/emergency handling stay with controllers.
signal decision_serviced(id: String, wait_usec: int, wait_minutes: int, accepted: bool)
const AGING_USEC := 250000
@export_range(100, 20000, 100) var budget_usec := 1000
var clock: Node
var _queue: Array[Dictionary] = []
var _pending: Dictionary = {}
var _last_frame := -1
var _draining := false
var _sequence := 0
var requests := 0
var duplicates := 0
var executed := 0
var discarded := 0
var cancelled := 0
var peak_pending := 0
var last_processed := 0
var last_elapsed_usec := 0
var budget_overruns := 0
var serviced_frames := 0
var critical_reactions := 0
var max_wait_usec := 0
var max_wait_minutes := 0

func _now_usec() -> int: return Time.get_ticks_usec()
func _minute() -> int: return clock.total_minutes if is_instance_valid(clock) else 0

func request(id: String, receiver: Node, reason: String, context: Dictionary = {}, priority: int = 1) -> bool:
	requests += 1
	if not is_instance_valid(receiver) or not receiver.is_inside_tree() or receiver.is_queued_for_deletion(): return false
	if _pending.has(id):
		var waiting: Dictionary = _pending[id]
		if waiting.receiver.get_ref() == receiver:
			duplicates += 1
			waiting.priority = maxi(waiting.priority, clampi(priority, 0, 2))
			waiting.reasons[reason] = true
			waiting.reason = reason
			waiting.context.merge(context, true)
			return false # Update live context without losing age or FIFO tie-break.
		cancel(id)
	_sequence += 1
	var entry := {"id": id, "receiver": weakref(receiver), "reason": reason,
		"reasons": {reason: true}, "context": context.duplicate(), "priority": clampi(priority, 0, 2),
		"enqueued_usec": _now_usec(), "enqueued_minute": _minute(), "sequence": _sequence}
	_pending[id] = entry
	_queue.append(entry)
	peak_pending = maxi(peak_pending, _queue.size())
	return true

func cancel(id: String, receiver: Node = null) -> void:
	if not _pending.has(id): return
	var entry: Dictionary = _pending[id]
	if receiver != null and entry.receiver.get_ref() != receiver: return
	_pending.erase(id)
	_queue.erase(entry)
	cancelled += 1

func pending_count() -> int: return _queue.size()
func clear() -> void:
	_queue.clear()
	_pending.clear()
func _exit_tree() -> void: clear()

func statistics() -> Dictionary:
	var oldest := 0
	var now := _now_usec()
	for entry in _queue: oldest = maxi(oldest, now - int(entry.enqueued_usec))
	return {"pending": pending_count(), "peak": peak_pending, "processed": last_processed,
		"elapsed_usec": last_elapsed_usec, "budget_usec": budget_usec, "oldest_usec": oldest,
		"merged": duplicates, "discarded": discarded, "cancelled": cancelled,
		"overruns": budget_overruns, "serviced_frames": serviced_frames, "executed": executed,
		"max_wait_usec": max_wait_usec, "max_wait_minutes": max_wait_minutes,
		"critical_reactions": critical_reactions}

func _process(_delta: float) -> void:
	if not is_inside_tree() or get_tree().paused or _draining: return
	var frame := Engine.get_process_frames()
	if _last_frame == frame: return
	_last_frame = frame
	last_processed = 0
	last_elapsed_usec = 0
	if _queue.is_empty(): return
	_draining = true
	var start := _now_usec()
	# priority + waiting/AGING has the same ordering as priority*AGING-enqueue.
	# Older background entries eventually outrank continuously arriving urgent work.
	_queue.sort_custom(func(a, b):
		var left: int = a.priority * AGING_USEC - a.enqueued_usec
		var right: int = b.priority * AGING_USEC - b.enqueued_usec
		return a.sequence < b.sequence if left == right else left > right)
	var eligible := _queue.duplicate()
	var attempted := 0
	for entry in eligible:
		if not is_inside_tree() or get_tree().paused: break
		if attempted > 0 and _now_usec() - start >= maxi(100, budget_usec): break
		if not _pending.has(entry.id) or _pending[entry.id] != entry: continue
		_pending.erase(entry.id)
		_queue.erase(entry)
		attempted += 1
		var receiver: Node = entry.receiver.get_ref()
		if not is_instance_valid(receiver) or not receiver.is_inside_tree() or receiver.is_queued_for_deletion():
			discarded += 1
			continue
		var wait_usec: int = maxi(0, _now_usec() - int(entry.enqueued_usec))
		var wait_minutes: int = maxi(0, _minute() - int(entry.enqueued_minute))
		max_wait_usec = maxi(max_wait_usec, wait_usec)
		max_wait_minutes = maxi(max_wait_minutes, wait_minutes)
		var accepted: bool = receiver.execute_queued_decision(entry.reason, _execution_context(entry))
		if accepted:
			executed += 1
			last_processed += 1
		else: discarded += 1
		decision_serviced.emit(entry.id, wait_usec, wait_minutes, accepted)
		# New requests, including reentrant self-requests, wait for a later frame.
	last_elapsed_usec = _now_usec() - start
	serviced_frames += 1
	if last_elapsed_usec > maxi(100, budget_usec): budget_overruns += 1
	_draining = false

func _execution_context(entry: Dictionary) -> Dictionary:
	var context: Dictionary = entry.context.duplicate()
	context["request_reasons"] = entry.reasons.keys()
	return context
