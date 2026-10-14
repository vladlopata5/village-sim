extends PanelContainer
## The existing GameTime is the sole clock; this component only presents it.
var refresh_count := 0
var _clock_pending := false
var clock: Node
@onready var clock_label: Label = $Column/ClockRow/Clock
@onready var pause_button: Button = $Column/Speeds/Pause
var speed_buttons: Array[Button] = []
func setup(time: Node, pause_action: Callable) -> void:
	clock = time
	var symbols := SystemFont.new()
	symbols.font_names=PackedStringArray(["Segoe UI Symbol","Noto Sans Symbols 2","DejaVu Sans"])
	if symbols.has_char(0x23f8): pause_button.add_theme_font_override("font",symbols)
	pause_button.pressed.connect(pause_action)
	for multiplier in [1,2,4]:
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
	clock.minute_changed.connect(func(_minute): request_clock_refresh())
	clock.speed_changed.connect(refresh_speed)
	refresh_speed(clock.speed_multiplier)
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
func refresh_pause() -> void:
	pause_button.text = "▶" if get_tree().paused else "⏸"

func refresh_speed(multiplier: int) -> void:
	for index in range(speed_buttons.size()):
		speed_buttons[index].set_pressed_no_signal([1,2,4][index]==multiplier)
