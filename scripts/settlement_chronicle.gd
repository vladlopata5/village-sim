extends RefCounted
## One runtime history of committed events. No trigger subscriptions or personal diaries.
const Facts = preload("res://scripts/event_facts.gd")
const Clock = preload("res://scripts/game_time.gd")
const Season = preload("res://scripts/season.gd")
@warning_ignore("unused_signal") # Published externally after the whole event transaction.
signal changed(occurrence_id: String)
var _entries: Dictionary = {}
var _sequence := 0

func size() -> int: return _entries.size()
func get_entry(occurrence_id: String) -> Dictionary: return _entries.get(occurrence_id, {}).duplicate(true)
func entries() -> Array:
	var result: Array = _entries.values().duplicate(true)
	result.sort_custom(func(a, b): return a.minute < b.minute if a.minute != b.minute else a.sequence < b.sequence)
	return result

func prepare_add(record: Dictionary) -> Dictionary:
	if not Facts.plain(record) or record.size() != 5: return {}
	for key in ["id", "definition_id", "text"]:
		if not record.get(key) is String or record[key].strip_edges().is_empty(): return {}
	if _entries.has(record.id) or not record.get("minute") is int or record.minute < 0: return {}
	if not record.get("participants") is Array: return {}
	var unique := {}
	for participant in record.participants:
		if not Facts.is_ref(participant) or unique.has(Facts.ref_key(participant)): return {}
		unique[Facts.ref_key(participant)] = true
	var prepared := record.duplicate(true)
	prepared.sequence = _sequence + 1
	return prepared

func _apply_event_add(prepared: Dictionary) -> void:
	_sequence = prepared.sequence
	_entries[prepared.id] = prepared.duplicate(true)

static func day_for_minute(minute: int) -> int:
	@warning_ignore("integer_division")
	return minute / Clock.MINUTES_PER_DAY + 1
static func date_text(minute: int) -> String:
	var day := day_for_minute(minute)
	return "День %d · %s" % [day, Season.display_name(Season.for_day(day))]
static func time_text(minute: int) -> String:
	var time := minute % Clock.MINUTES_PER_DAY
	@warning_ignore("integer_division")
	return "%02d:%02d" % [time / 60, time % 60]
