extends RefCounted
## Temporary read-only projections of this pair, not a second resident/state store.
const Facts = preload("res://scripts/event_facts.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")

static func snapshot(first: RefCounted, second: RefCounted, minute: int, social_links: RefCounted = null, maintain: bool = true) -> RefCounted:
	if maintain:
		var stores: Array = [first.memories] if second == null else [first.memories,second.memories]
		preload("res://scripts/memory_store.gd").advance_all(stores,minute)
	var facts := Facts.new()
	var schema := snapshot_schema()
	for key in schema: facts.register_fact(key, "resident", schema[key][0], schema[key][1])
	var people := [first] if second == null or second == first else [first, second]
	for person in people: facts.register_entity({"kind": "resident", "id": person.id})
	for person in people:
		var ref := {"kind": "resident", "id": person.id}
		var traits: Array = []
		for type in person.traits: traits.append(Trait.Type.keys()[type].to_lower())
		facts.set_value(ref, "traits", traits)
		# Reading the ordinary mood property can refresh its cache and emit a signal.
		var mood: float = person.mood if maintain else 0.0
		var active_moodlets: Array = person.moodlets.active(minute)
		if not maintain:
			mood = Modifiers.mood_from_offset(Modifiers.moodlet_numeric_state(active_moodlets, minute).mood_offset)
		facts.set_value(ref, "mood", mood)
		facts.set_value(ref, "moodlets.active", active_moodlets)
		assert(facts.set_collection(ref, "memories", person.memories.find()))
		if social_links != null:
			var counts: Dictionary = social_links.counts_for(person)
			if not counts.is_empty(): facts.set_value(ref, "link.counts", counts)
		for other in people:
			if other == person: continue
			var target := {"kind": "resident", "id": other.id}
			facts.set_value(ref, "opinion", person.get_opinion(other.id), target)
			if social_links != null:
				var link: Dictionary = social_links.get_link(person, other)
				if link.is_empty(): continue
				facts.set_value(ref, "link.level", link.link_level, target)
				facts.set_value(ref, "link.revision", link.revision, target)
				facts.set_value(ref, "link.normal_transition_ready", social_links.normal_transition_ready(person, other, minute), target)
		for type in Skill.Type.values():
			var key: String = Skill.Type.keys()[type].to_lower()
			facts.set_value(ref, "skill.rank", person.get_skill_rank(type), key)
			facts.set_value(ref, "skill.name", Skill.display_name(type), key)
	return facts

static func snapshot_schema() -> Dictionary:
	return {
		"mood": ["number", "none"], "traits": ["array", "none"], "opinion": ["number", "entity"],
		"skill.rank": ["number", "string"], "skill.name": ["string", "string"],
		"moodlets.active": ["array", "none"], "memories": ["collection", "none"],
		"link.level": ["number", "entity"], "link.normal_transition_ready": ["bool", "entity"],
		"link.revision": ["number", "entity"],
		"link.counts": ["record", "none"],
	}
