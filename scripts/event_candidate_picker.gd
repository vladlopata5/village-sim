extends RefCounted
## Generic one-shot resident choice for world facts. No story eligibility tests here.
const Facts = preload("res://scripts/event_facts.gd")
var rng: RefCounted = RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize() # Independent from AI, social events, selector and effects.

func choose(candidates: Array, control: RefCounted, active_guard: Callable) -> Dictionary:
	var available: Array = []
	var seen: Dictionary = {}
	for candidate in candidates:
		if not Facts.is_ref(candidate) or candidate.kind != "resident" or seen.has(candidate.id): continue
		seen[candidate.id] = true
		var person: RefCounted = control.get_resident(candidate.id)
		if person != null and active_guard.is_valid() and active_guard.call(person): available.append(person)
	if available.is_empty(): return {"status": "no_candidates"}
	var roll: float = rng.randf() # Exactly one draw, even with a single candidate.
	if not is_finite(roll) or roll < 0 or roll > 1: return {"status": "invalid_candidate_rng"}
	var selected: RefCounted = available[mini(floori(roll * available.size()), available.size() - 1)]
	return {"status": "chosen", "person": selected, "reference": {"kind": "resident", "id": selected.id}, "candidate_count": available.size()}
