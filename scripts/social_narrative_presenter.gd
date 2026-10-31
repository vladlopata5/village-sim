extends RefCounted
## Optional legacy story selection and output. Never calculates social reactions.
const Event = preload("res://scripts/social_event.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
const Diary = preload("res://scripts/diary_entry.gd")
const Balance = preload("res://scripts/balance_config.gd")
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
signal feed_message(text: String)
var enabled := true
var rng: RefCounted = RandomNumberGenerator.new()
var entries: Array = []
var diary_chance: float = Balance.SOCIAL_EVENT_DIARY_CHANCE

func _init() -> void:
	rng.randomize()
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/social_events/entries.json"))
	for value in values: entries.append(Entry.new(value))

func matching_entries(result: Event, a: RefCounted, b: RefCounted, tags_a: Array, tags_b: Array) -> Array:
	var matches: Array = []
	for entry in entries:
		var orientations: Array = []
		if entry.matches(result.context, a, b, result.reaction_1, result.reaction_2, tags_a, tags_b): orientations.append(false)
		if entry.matches(result.context, b, a, result.reaction_2, result.reaction_1, tags_b, tags_a): orientations.append(true)
		# One ticket per entry, even if both orientations match.
		if not orientations.is_empty(): matches.append({"entry": entry, "orientations": orientations})
	return matches
func present(result: Event, a: RefCounted, b: RefCounted, tags_a: Array, tags_b: Array, clock: Node = null) -> Dictionary:
	var output := {"feed": 0, "diary": 0}
	if not enabled: return output
	var matches := matching_entries(result, a, b, tags_a, tags_b)
	if matches.is_empty():
		output.feed = _fallback_feed(result, a, b)
		return output
	var selected: Dictionary = matches[rng.randi_range(0, matches.size() - 1)]
	var entry: RefCounted = selected.entry
	var reverse: bool = selected.orientations[rng.randi_range(0, selected.orientations.size() - 1)]
	result.selected_entry_id = entry.id
	result.reversed_orientation = reverse
	var first: RefCounted = b if reverse else a
	var second: RefCounted = a if reverse else b
	for template in [entry.feed_text_a, entry.feed_text_b]:
		var text: String = entry.render(template, first, second)
		if not text.strip_edges().is_empty():
			feed_message.emit(text)
			output.feed += 1
	if output.feed == 0: output.feed = _fallback_feed(result, a, b)
	if entry.diary_importance == Diary.Importance.NONE: return output
	var minute: int = clock.total_minutes if is_instance_valid(clock) else 0
	for diary_output in [[first, entry.diary_text_a], [second, entry.diary_text_b]]:
		if not diary_output[1].is_empty() and rng.randf() < diary_chance:
			diary_output[0].add_diary_entry(Diary.new(entry.render(diary_output[1], first, second), entry.diary_importance, minute))
			output.diary += 1
	return output
func _fallback_feed(result: Event, a: RefCounted, b: RefCounted) -> int:
	feed_message.emit(_fallback_text(a, b, result.reaction_1))
	feed_message.emit(_fallback_text(b, a, result.reaction_2))
	return 2
func _fallback_text(resident: RefCounted, other: RefCounted, response: Event.Reaction) -> String:
	var template: String
	match response:
		Event.Reaction.POSITIVE: template = "{resident.name}: «Приятно провёл время с {other.name}»."
		Event.Reaction.NEGATIVE: template = "{resident.name}: «Общение с {other.name} меня раздражает»."
		_: template = "{resident.name}: «Провёл время с {other.name} — ничего особенного»."
	return TextRenderer.render(template, {"resident": {"name": resident.resident_name}, "other": {"name": other.resident_name}}).text
