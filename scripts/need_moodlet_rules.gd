extends RefCounted
## Guaranteed need-state descriptors, separate from randomly selected stories.
const Need = preload("res://scripts/need_type.gd")
const Trait = preload("res://scripts/trait_type.gd")
const DEFINITIONS = {
	Need.Type.HUNGER: {"id":"hungry", "names":["Голодный","Голодная"]},
	Need.Type.FATIGUE: {"id":"exhausted", "names":["Измотанный","Измотанная"]},
	Need.Type.SOCIAL: {"id":"lonely", "names":["Одинокий","Одинокая"]},
	Need.Type.LEISURE: {"id":"bored", "names":["Скучающий","Скучающая"]}
}
static func desired(value: int, active: bool) -> bool:
	if value > 90: return true
	if value < 40: return false
	return active
static func display_name(id: String, gender: int) -> String:
	for definition in DEFINITIONS.values():
		if definition.id == id: return definition.names[1 if gender == Trait.GrammaticalGender.FEMININE else 0]
	return ""
static func record(type: int, minute: int, occurrence_id: String) -> Dictionary:
	var id: String = DEFINITIONS[type].id
	return {"id":id, "type":id, "created_minute":minute, "expires_at_minute":null, "source_occurrence_id":occurrence_id, "tags":["need_state"], "context":{"need":Need.Type.keys()[type].to_lower()}, "modifiers":[{"channel":"mood.offset","value":-10}]}
