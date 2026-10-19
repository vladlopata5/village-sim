extends Node
## One bounded night schedule, consumed chronologically; no per-cell timers/scans.
const Balance = preload("res://scripts/balance_config.gd")
signal attempted(source: Vector2i, minute: int, result: Dictionary)
var land: RefCounted
var clock: Node
var _random := RandomNumberGenerator.new()
var _window := Vector2i.ZERO
var _events: Array[Dictionary]=[]
var _cursor:=0
var _scheduled:=false
var _last_minute:=0
var _advancing:=false
func setup(model: RefCounted, time: Node, seed_value: int) -> void:
	land=model;clock=time;_random.seed=seed_value
	_last_minute=clock.total_minutes
	_window=clock.night_interval_at_or_after(_last_minute)
	clock.minute_changed.connect(_on_minute)
func pending_count() -> int: return _events.size()-_cursor
func _schedule() -> void:
	_events.clear();_cursor=0;_scheduled=true
	var attempts: int=Balance.MUSHROOM_ATTEMPTS_PER_NIGHT
	var duration:=_window.y-_window.x
	for cell in land.cells():
		for slot in range(attempts):
			# Distinct stratified minutes; different cells draw independently.
			var low:=_window.x+floori(float(slot*duration)/attempts)
			var high:=_window.x+floori(float((slot+1)*duration)/attempts)-1
			_events.append({"minute":_random.randi_range(low,high),"cell":cell})
	_events.sort_custom(func(a,b):
		if a.minute!=b.minute:return a.minute<b.minute
		return a.cell.y<b.cell.y or (a.cell.y==b.cell.y and a.cell.x<b.cell.x))
func _on_minute(now: int) -> void:
	if now<=_last_minute or _advancing:return
	_advancing=true
	while _window.x<=now:
		if not _scheduled:_schedule()
		while _cursor<_events.size() and _events[_cursor].minute<=now:
			var event: Dictionary=_events[_cursor]
			_cursor+=1 # Consume before observers can repeat the time notification.
			if event.minute>_last_minute:
				attempted.emit(event.cell,event.minute,land.attempt(event.cell,_random))
		if now<_window.y:break
		_events.clear();_cursor=0;_scheduled=false
		_window=clock.night_interval_at_or_after(_window.y)
	_last_minute=now
	_advancing=false
