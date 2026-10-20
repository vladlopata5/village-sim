extends Node
## One animal's event-driven behavior; no resident AI queue or navigation ownership.
const Animal = preload("res://scripts/animal_data.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Clock = preload("res://scripts/game_time.gd")
signal movement_requested(token: int, target: Vector3, prepared: Dictionary)
signal stop_requested
signal behavior_finished(behavior: int, successful: bool)
var data: Animal
var rng := RandomNumberGenerator.new()
var wander_offer: Callable
var token := 0
var choices := 0
var suspended := false
var _clock: Node
var _last_minute := -1
func setup(animal: Animal, clock: Node) -> void:
	data = animal
	_clock = clock
	rng.seed = Balance.SHEEP_SEED ^ String(data.id).hash()
	_last_minute = clock.total_minutes
	clock.minute_changed.connect(_on_minute)
	_choose(clock.total_minutes)
func _choose(now: int) -> void:
	if suspended: return
	choices += 1
	var time_of_day := posmod(now,Clock.MINUTES_PER_DAY)
	if time_of_day >= Balance.SHEEP_SLEEP_AFTER or time_of_day < Balance.SHEEP_WAKE_MIN:
		_begin_sleep(now)
	elif rng.randf() < Balance.SHEEP_WANDER_CHANCE:
		var offer: Dictionary = wander_offer.call(rng) if wander_offer.is_valid() else {}
		if offer.is_empty():
			_retry(now)
		else:
			_set_behavior(Animal.Behavior.WANDER,now,-1)
			movement_requested.emit(token,offer.target,offer.prepared)
	else:
		_begin_graze(now)
func _set_behavior(next: Animal.Behavior, now: int, ends_at: int) -> void:
	token += 1 # Invalidate old completions before stop/changed callbacks.
	stop_requested.emit()
	data.behavior = next
	data.behavior_started_at = now
	data.behavior_ends_at = ends_at
	data.changed.emit()
func _begin_graze(now: int) -> void:
	_set_behavior(Animal.Behavior.GRAZE,now,now+rng.randi_range(Balance.SHEEP_GRAZE_MIN,Balance.SHEEP_GRAZE_MAX))
func _begin_sleep(now: int) -> void:
	var morning := floori(float(now)/Clock.MINUTES_PER_DAY)*Clock.MINUTES_PER_DAY
	if posmod(now,Clock.MINUTES_PER_DAY) >= Balance.SHEEP_SLEEP_AFTER: morning += Clock.MINUTES_PER_DAY
	data.sleep_started_at = now
	data.wake_at = morning+rng.randi_range(Balance.SHEEP_WAKE_MIN,Balance.SHEEP_WAKE_MAX)
	_set_behavior(Animal.Behavior.SLEEP,now,data.wake_at)
func _retry(now: int) -> void:
	# Technical failure backoff, not a successful graze or a third daytime activity.
	_set_behavior(Animal.Behavior.IDLE,now,now+Balance.SHEEP_RETRY_MINUTES)
func finish_wander(completed_token: int, successful: bool) -> void:
	if data == null or data.behavior != Animal.Behavior.WANDER or completed_token != token: return
	var now: int = _clock.total_minutes
	# Detach the completed action before emitting observable results.
	var completed_generation := token+1
	_set_behavior(Animal.Behavior.IDLE,now,-1)
	if token != completed_generation: return
	behavior_finished.emit(Animal.Behavior.WANDER,successful)
	if token != completed_generation: return
	if successful: _choose(now)
	else: _retry(now)
func _on_minute(now: int) -> void:
	if now <= _last_minute: return
	_last_minute = now
	if suspended: return
	# GameTime normally emits every minute; also tolerate a direct larger checkpoint.
	while data.behavior_ends_at >= 0 and data.behavior_ends_at <= now:
		var finished_at := data.behavior_ends_at
		var previous := data.behavior
		var completed_generation := token+1
		_set_behavior(Animal.Behavior.IDLE,finished_at,-1)
		if token != completed_generation: return
		if previous == Animal.Behavior.GRAZE: data.wool_growth += 1
		if token != completed_generation: return
		if previous != Animal.Behavior.IDLE: behavior_finished.emit(previous,true)
		if token != completed_generation: return
		_choose(finished_at)
func cancel_behavior() -> void:
	if data != null: _set_behavior(Animal.Behavior.IDLE,_clock.total_minutes,-1)
func suspend() -> void:
	suspended = true
	cancel_behavior()
func resume() -> void:
	if not suspended: return
	suspended = false
	if is_instance_valid(_clock):
		_last_minute = _clock.total_minutes
		_choose(_clock.total_minutes)
func _exit_tree() -> void:
	if is_instance_valid(_clock) and _clock.minute_changed.is_connected(_on_minute): _clock.minute_changed.disconnect(_on_minute)
