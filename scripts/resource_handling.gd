extends RefCounted
## One-shot game-minute timer. Owns no resources, slots or gameplay decisions.
var operation: StringName = &""
var _deadline := 0
func start(kind: StringName, now: int, duration: int) -> bool:
	if is_active(): return false
	operation = kind
	_deadline = now + duration
	return true
func is_active() -> bool: return not operation.is_empty()
func advance(now: int) -> bool:
	if not is_active() or now < _deadline: return false
	cancel() # Consume completion before any synchronous transfer callback.
	return true
func cancel() -> void:
	operation = &""
	_deadline = 0
