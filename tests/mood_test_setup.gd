extends RefCounted
## Explicit test effects replace the retired writable initial-mood field.
static var _sequence := 0
static func set_value(person: RefCounted, value: float) -> bool:
	person.moodlets.remove("test_mood")
	var offset: float = value - (50.0 + person.moodlets.mood_offset())
	_sequence += 1
	return person.moodlets.add({"id":"test_mood", "type":"test_mood", "created_minute":person.moodlets.current_minute(), "source_occurrence_id":"test/mood/%d" % _sequence, "modifiers":[{"channel":"mood.offset","value":offset}]})
static func expected(person: RefCounted) -> float:
	var offset := 0.0
	for entry: Dictionary in person.moodlets.active(person.moodlets.current_minute()):
		for modifier: Dictionary in entry.modifiers:
			if modifier.get("channel") == "mood.offset": offset += modifier.value
	return clampf(50.0 + offset,0.0,100.0)
