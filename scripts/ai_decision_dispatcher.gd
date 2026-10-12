extends Node
## Ordinary decisions only. Receivers retain all gameplay guards and read the world on execution.
var decisions_per_frame := 1
var _queue: Array[Dictionary] = []
var _pending: Dictionary = {}
var _last_frame := -1
var _draining := false
var _executing: Node
var requests := 0
var duplicates := 0
var executed := 0
var discarded := 0
var peak_pending := 0

func request(id: String, receiver: Node, reason: String, context: Dictionary = {}) -> bool:
	requests += 1
	if not is_instance_valid(receiver) or not receiver.is_inside_tree(): return false
	if receiver == _executing:
		duplicates += 1
		return false
	if _pending.has(id):
		if _pending[id].receiver.get_ref() == receiver:
			duplicates += 1
			return false # Repeated notifications retain the original FIFO position.
		cancel(id) # Same ID, new runtime: never deliver an old request to it.
	var entry := {"id": id, "receiver": weakref(receiver), "reason": reason, "context": context.duplicate()}
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

func pending_count() -> int: return _queue.size()

func clear() -> void:
	_queue.clear()
	_pending.clear()

func _exit_tree() -> void: clear()

func _process(_delta: float) -> void:
	# GameTime can advance many minutes in one frame; it never spends this budget.
	if not is_inside_tree() or get_tree().paused or _draining: return
	var frame := Engine.get_process_frames()
	if _last_frame == frame: return
	_last_frame = frame
	_draining = true
	var count := mini(maxi(1, decisions_per_frame), _queue.size())
	for index in count:
		if _queue.is_empty() or not is_inside_tree() or get_tree().paused: break
		var entry: Dictionary = _queue.pop_front()
		_pending.erase(entry.id)
		var receiver: Node = entry.receiver.get_ref()
		if not is_instance_valid(receiver) or not receiver.is_inside_tree() or receiver.is_queued_for_deletion():
			discarded += 1
			continue
		_executing = receiver
		if receiver.execute_queued_decision(entry.reason, entry.context): executed += 1
		else: discarded += 1
		_executing = null
	_draining = false
