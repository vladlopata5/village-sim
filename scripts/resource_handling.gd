extends RefCounted
## One-shot active work stage. Completion is consumed before transfer callbacks.
const Work = preload("res://scripts/work_progress.gd")
const Balance = preload("res://scripts/balance_config.gd")
var operation: StringName = &""
var progress := 0.0
var _required := 0.0
var _last_minute := 0
var _rate := 1.0
func start(kind: StringName, now: int, duration: int, rate: float = 1.0) -> bool:
	var maximum := 1.5 * (Balance.HASTY_WORK_RATE_MULTIPLIER if kind==&"gather_loading" else 1.0)
	if is_active() or kind.is_empty() or duration <= 0 or not is_finite(rate) or rate < 1.0 or rate > maximum: return false
	operation = kind
	progress = 0.0
	_required = duration
	_last_minute = now
	_rate = rate
	return true
func is_active() -> bool: return not operation.is_empty()
func advance(now: int, active: bool = true) -> bool:
	if not is_active() or now <= _last_minute: return false
	var elapsed := now - _last_minute
	_last_minute = now
	if not active: return false
	progress = Work.advance(progress, elapsed * _rate, _required)
	if not Work.reached(progress, _required): return false
	cancel() # Consume completion before any synchronous transfer callback.
	return true
func cancel() -> void:
	operation = &""
	progress = 0.0
	_required = 0.0
	_rate = 1.0
