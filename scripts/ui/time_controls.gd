extends PanelContainer
## The existing GameTime is the sole clock; this component only presents it.
var refresh_count := 0
var _clock_pending := false
var clock: Node
@onready var clock_label: Label = $Column/ClockRow/Clock
@onready var day_label: Label = $Column/ClockRow/Day
@onready var pause_button: Button = $Column/ClockRow/Pause
var speed_buttons: Array[Button] = []
func setup(time: Node, pause_action: Callable) -> void:
	clock = time
	pause_button.pressed.connect(pause_action)
	for multiplier in clock.SUPPORTED_SPEEDS:
		var button := Button.new()
		button.text = "x%d" % multiplier
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(clock.set_speed.bind(multiplier))
		$Column/Speeds.add_child(button)
		speed_buttons.append(button)
	# F10 can pause directly. Refresh only the caption, also while paused.
	var timer := Timer.new()
	timer.wait_time = 0.2
	timer.timeout.connect(refresh_pause)
	add_child(timer)
	timer.start()
	refresh_clock()
	refresh_pause()
func request_clock_refresh() -> void:
	if _clock_pending: return
	_clock_pending=true
	_flush_clock.call_deferred()
func _flush_clock() -> void:
	_clock_pending=false
	refresh_clock()
func refresh_clock() -> void:
	refresh_count += 1
	clock_label.text = clock.get_clock_text()
	day_label.text = "День %d" % (floori(float(clock.total_minutes) / 1440.0) + 1)
func refresh_pause() -> void:
	pause_button.text = "Продолжить" if get_tree().paused else "Пауза"
