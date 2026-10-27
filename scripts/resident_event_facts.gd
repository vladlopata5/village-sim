extends RefCounted
## Temporary read-only projections of this pair, not a second resident/state store.
const Facts = preload("res://scripts/event_facts.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Trait = preload("res://scripts/trait_type.gd")

static func snapshot(first: RefCounted, second: RefCounted, minute: int) -> RefCounted:
	var facts := Facts.new()
	var schema := snapshot_schema()
	for key in schema: facts.register_fact(key, "resident", schema[key][0], schema[key][1])
	var people := [first, second]
	for person in people: facts.register_entity({"kind": "resident", "id": person.id})
	for person in people:
		var ref := {"kind": "resident", "id": person.id}
		var traits: Array = []
		for type in person.traits: traits.append(Trait.Type.keys()[type].to_lower())
		facts.set_value(ref, "traits", traits)
		facts.set_value(ref, "moodlets.active", person.moodlets.active(minute))
		facts.set_value(ref, "memories", person.memories.find())
		for other in people:
			if other != person: facts.set_value(ref, "opinion", person.get_opinion(other.id), {"kind": "resident", "id": other.id})
		for type in Skill.Type.values():
			var key: String = Skill.Type.keys()[type].to_lower()
			facts.set_value(ref, "skill.level", person.get_skill_level(type), key)
			facts.set_value(ref, "skill.name", Skill.display_name(type), key)
	return facts

static func snapshot_schema() -> Dictionary:
	return {"traits": ["array", "none"], "opinion": ["number", "entity"], "skill.level": ["number", "string"], "skill.name": ["string", "string"], "moodlets.active": ["array", "none"], "memories": ["array", "none"]}
