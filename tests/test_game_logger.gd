extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const Data = preload("res://scripts/resident_data.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
var failures := 0
var entries: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	var event_log = EventLog.new()
	event_log.setup(clock)
	event_log.console_enabled = false
	event_log.line_logged.connect(func(line: String, _level: EventLog.Level): entries.append(line))
	clock.total_minutes = 495
	check(event_log.format_line(EventLog.NEED, "Фёдор: начал есть") == "[08:15][NEED] Фёдор: начал есть", "INFO uses game HH:MM and category")
	event_log.info(EventLog.NEED, "Фёдор: начал есть")
	event_log.debug(EventLog.AI, "priority=8000")
	check(entries.size() == 1, "DEBUG disabled by default, INFO enabled")
	event_log.debug_enabled = true
	event_log.debug(EventLog.AI, "priority=8000")
	check(entries[-1] == "[08:15][AI][DEBUG] priority=8000", "DEBUG is identifiable and can be enabled")
	paused = true
	clock.set_speed(4)
	clock.advance(100)
	event_log.info(EventLog.RESOURCE, "test")
	check(entries[-1] == "[08:15][RESOURCE] test", "Pause does not substitute wall time")
	clock.debug_skip_minutes(1440)
	check(event_log.format_line(EventLog.SCHEDULE, "test") == "[08:15][SCHEDULE] test", "Game time wraps over days, including paused debug skip")
	paused = false
	var resident = Data.new("r", "Степан", 30)
	resident.activity = Activity.WORKING
	event_log.sync_activity(resident)
	var count := entries.size()
	event_log.sync_activity(resident)
	check(entries.size() == count, "Repeated state is not logged again")
	resident.activity = Activity.SLEEPING
	event_log.sync_activity(resident)
	check(entries[-2].ends_with("закончил работу") and entries[-1].ends_with("начал спать"), "Work exit and sleep entry are meaningful events")
	resident.activity = Activity.IDLE
	event_log.sync_activity(resident)
	check(entries[-1].ends_with("проснулся"), "Wake-up event")
	for category in [EventLog.AI, EventLog.NEED, EventLog.LOGISTICS, EventLog.PRODUCTION, EventLog.SOCIAL, EventLog.SCHEDULE, EventLog.RESOURCE]:
		check(event_log.format_line(category, "test").contains("[%s]" % category), "All event categories available")
	var hut = preload("res://scripts/building_data.gd").new(&"hut", "Хижина", preload("res://scripts/building_type.gd").Type.GATHERER_HUT)
	var food = preload("res://scripts/resource_type.gd").Type.FOOD
	hut.resources.set_capacity(food, 5)
	hut.resources.add(food, 5)
	var production = preload("res://scripts/gatherer_production.gd").new()
	root.add_child(production)
	production.logger = event_log
	production.setup(clock, hut, [], preload("res://scripts/world_locations_2d.gd").new(), Callable())
	count = entries.size()
	clock.debug_skip_minutes(20)
	check(entries.size() == count + 1 and entries[-1].contains("контейнер заполнен"), "Full output logged once, not every minute")
	production.free()
	clock.free()
	print("Game logger checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
