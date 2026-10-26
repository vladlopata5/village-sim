extends RefCounted
## Optional filters and presentation strings, never mechanical effects.
const Event = preload("res://scripts/social_event.gd")
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
var id: String
var conditions: Dictionary = {}
var feed_text_a := ""
var feed_text_b := ""
var diary_text_a := ""
var diary_text_b := ""
var diary_importance := 0
func _init(values: Dictionary = {}) -> void:
	id = values.get("id", "")
	conditions = values.get("conditions", {})
	feed_text_a = values.get("feed_text_a", "")
	feed_text_b = values.get("feed_text_b", "")
	diary_text_a = values.get("diary_text_a", "")
	diary_text_b = values.get("diary_text_b", "")
	diary_importance = values.get("diary_importance", 0)
func matches(context: int, a: RefCounted, b: RefCounted, reaction_a: int, reaction_b: int, tags_a: Array, tags_b: Array) -> bool:
	var contexts: Array = conditions.get("allowed_contexts", [])
	if not contexts.is_empty() and Event.Context.keys()[context] not in contexts: return false
	if conditions.has("reaction_a") and conditions.reaction_a != Event.Reaction.keys()[reaction_a]: return false
	if conditions.has("reaction_b") and conditions.reaction_b != Event.Reaction.keys()[reaction_b]: return false
	return _includes(a.traits, conditions.get("required_traits_a", [])) and _includes(b.traits, conditions.get("required_traits_b", [])) and _includes(tags_a, conditions.get("participant_state_tags_a", [])) and _includes(tags_b, conditions.get("participant_state_tags_b", []))
func _includes(actual: Array, required: Array) -> bool:
	for value in required:
		if value not in actual: return false
	return true
func render(template: String, a: RefCounted, b: RefCounted) -> String:
	return TextRenderer.render(template, {"a": {"name": a.resident_name}, "b": {"name": b.resident_name}}, true).text
