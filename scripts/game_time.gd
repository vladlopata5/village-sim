extends Node
## Simulation time has no dependencies on the visual world.
const SUPPORTED_SPEEDS := [1, 2, 4, 10, 20]
signal minute_changed(total_minutes: int)
signal phase_changed(phase: String)
signal speed_changed(multiplier: int)

@export_range(0.1, 60.0) var game_minutes_per_second: float = 1.0
var total_minutes: int = 360
var speed_multiplier: int = 1
var _fractional_minutes: float = 0.0
var _last_tick_usec: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick_usec = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	# Monotonic time includes long frames without the engine's delta clamping.
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _last_tick_usec) / 1000000.0
	_last_tick_usec = now
	advance(elapsed)

func advance(real_seconds: float) -> void:
	if get_tree().paused or real_seconds <= 0.0:
		return
	_fractional_minutes += real_seconds * game_minutes_per_second * speed_multiplier
	var whole_minutes := int(floor(_fractional_minutes))
	_fractional_minutes -= whole_minutes
	_advance_game_minutes(whole_minutes)

func _advance_game_minutes(whole_minutes: int) -> void:
	# Emit every crossed phase, even when a long frame spans several phases.
	for _minute in range(whole_minutes):
		var previous_phase := get_phase()
		total_minutes += 1
		minute_changed.emit(total_minutes)
		var current_phase := get_phase()
		if current_phase != previous_phase:
			phase_changed.emit(current_phase)

# Temporary developer controls: explicit jumps work even while paused.
func debug_skip_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	if is_processing():
		_process(0.0)
	_advance_game_minutes(minutes)
	_last_tick_usec = Time.get_ticks_usec()

func debug_next_phase() -> void:
	if is_processing():
		_process(0.0)
	var minute_of_day := total_minutes % 1440
	var next_boundary := 1440 + 360
	for boundary in [360, 420, 1020, 1380]:
		if boundary > minute_of_day:
			next_boundary = boundary
			break
	_fractional_minutes = 0.0
	_advance_game_minutes(next_boundary - minute_of_day)
	_last_tick_usec = Time.get_ticks_usec()

func set_speed(multiplier: int) -> void:
	if multiplier not in SUPPORTED_SPEEDS:
		return
	if is_processing():
		_process(0.0)
	speed_multiplier = multiplier
	speed_changed.emit(multiplier)

func toggle_pause() -> void:
	_process(0.0)
	get_tree().paused = not get_tree().paused
	_last_tick_usec = Time.get_ticks_usec()

func get_clock_text() -> String:
	var minute_of_day := total_minutes % 1440
	return "%02d:%02d" % [int(minute_of_day / 60.0), minute_of_day % 60]

func get_phase() -> String:
	var minute_of_day := total_minutes % 1440
	if minute_of_day >= 360 and minute_of_day < 420:
		return "Утро"
	if minute_of_day >= 420 and minute_of_day < 1020:
		return "День"
	if minute_of_day >= 1020 and minute_of_day < 1380:
		return "Вечер"
	return "Ночь"
