extends RefCounted
## Transient mechanical result. Narrative orientation never changes these directions.
enum Context { CONVERSATION, MEAL, WORK }
enum Reaction { NEGATIVE, NEUTRAL, POSITIVE }
var context: Context
var resident_1_id: StringName
var resident_2_id: StringName
var attitude_1_to_2: int
var attitude_2_to_1: int
var roll_1: int
var roll_2: int
var reaction_1: Reaction
var reaction_2: Reaction
var opinion_delta_1: int
var opinion_delta_2: int
var selected_entry_id: String = ""
var reversed_orientation := false
var _confirmed_context: Dictionary = {}
var _participant_sources: Array = [] # Weak data identities, never retained runtimes.

func confirmed_context() -> Dictionary:
	return _confirmed_context.duplicate(true)

func has_participants(first: RefCounted, second: RefCounted) -> bool:
	return _participant_sources.size() == 2 and _participant_sources[0].get_ref() == first and _participant_sources[1].get_ref() == second
