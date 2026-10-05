extends Node
## One short walk and stay, independent of the source of the candidate position.
const Intent = preload("res://scripts/resident_intent.gd")
const Balance = preload("res://scripts/balance_config.gd")
var target_provider: Callable
var target_available: Callable
var runtime: Node
var clock: Node
var rng := RandomNumberGenerator.new()
var _active: Intent
var _stay_ends_at := 0
func setup(owner_runtime: Node, game_clock: Node) -> void:
	runtime = owner_runtime
	clock = game_clock
	rng.seed = runtime.data.id.hash() ^ 0x57414e44
	clock.minute_changed.connect(_on_minute)
	runtime.intents.intent_arrived.connect(_on_arrival)
	runtime.intents.intent_changed.connect(_on_intent_changed)
func has_action() -> bool:
	return target_provider.is_valid() and target_available.is_valid() and target_available.call()
func try_wander(priority: int) -> bool:
	if not has_action(): return false
	var target = target_provider.call(rng)
	if target == null: return false
	_active = Intent.new(Intent.Type.MOVE_TO, &"wander", target.position, priority, true)
	_stay_ends_at = 0
	if runtime.intents.submit(_active): return true
	_active = null
	return false
func _on_arrival(intent: Intent) -> void:
	if intent != _active: return
	# Retain a stationary, interruptible stay rather than completing the whole walk.
	_active = Intent.new(Intent.Type.NONE, &"wander", Vector2.ZERO, intent.priority, true)
	_stay_ends_at = clock.total_minutes + Balance.WANDER_STAY_MINUTES
	if not runtime.intents.submit(_active):
		_active = null
		_stay_ends_at = 0
func _on_minute(minute: int) -> void:
	if _active == null or _stay_ends_at == 0 or minute < _stay_ends_at: return
	var completed := _active
	_active = null
	_stay_ends_at = 0
	runtime.intents.clear_completed(completed)
func _on_intent_changed(intent: Intent) -> void:
	if _active != null and intent != _active:
		_active = null
		_stay_ends_at = 0
