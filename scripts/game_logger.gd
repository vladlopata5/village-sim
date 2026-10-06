extends RefCounted
## Shared event output. It observes simulation state and never changes it.
const Activity = preload("res://scripts/resident_activity.gd")
const DEFAULT_DEBUG_ENABLED := false
const PLAYER := &"PLAYER"
const ASSIGNMENT := &"ASSIGNMENT"
const AI := &"AI"
const NEED := &"NEED"
const LOGISTICS := &"LOGISTICS"
const PRODUCTION := &"PRODUCTION"
const LEISURE := &"LEISURE"
const SOCIAL := &"SOCIAL"
const SCHEDULE := &"SCHEDULE"
const RESOURCE := &"RESOURCE"
enum Level { INFO, DEBUG }
signal line_logged(line: String, level: Level)
var debug_enabled := DEFAULT_DEBUG_ENABLED
var console_enabled := true
var _clock: Node
var _activities: Dictionary = {}

func setup(game_time: Node) -> void:
	_clock = game_time

func format_line(category: StringName, message: String, level: Level = Level.INFO) -> String:
	var time_text: String = _clock.get_clock_text() if is_instance_valid(_clock) else "00:00"
	var level_text := "[DEBUG]" if level == Level.DEBUG else ""
	return "[%s][%s]%s %s" % [time_text, category, level_text, message]

func info(category: StringName, message: String) -> void:
	_write(category, message, Level.INFO)

func debug(category: StringName, message: String) -> void:
	if debug_enabled: _write(category, message, Level.DEBUG)

func _write(category: StringName, message: String, level: Level) -> void:
	var line := format_line(category, message, level)
	if console_enabled: print(line)
	line_logged.emit(line, level)

func sync_activity(data: RefCounted) -> void:
	# Cache only for logging: continuous ten-minute work segments are one event.
	var previous: int = _activities.get(data.id, Activity.Type.IDLE)
	var current: int = data.activity
	if previous == current: return
	_activities[data.id] = current
	if previous == Activity.Type.WORKING:
		var finished := "завершил рабочий цикл" if is_instance_valid(_clock) and _clock.get_phase() == "День" else "закончил работу"
		info(SCHEDULE, "%s: %s" % [data.resident_name, finished])
	elif previous == Activity.Type.SLEEPING:
		info(SCHEDULE, "%s: проснулся" % data.resident_name)
	if current == Activity.Type.WORKING:
		info(SCHEDULE, "%s: начал работать" % data.resident_name)
	elif current == Activity.Type.SLEEPING:
		info(SCHEDULE, "%s: начал спать" % data.resident_name)

func was_working(data: RefCounted) -> bool:
	return _activities.get(data.id, Activity.Type.IDLE) == Activity.Type.WORKING
