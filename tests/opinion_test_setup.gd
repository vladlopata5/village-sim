extends RefCounted
## Seeds a historical opinion for tests that exercise readers or a prior state.
## Ordinary game writes go through ResidentData.set_opinion/apply_opinion_change.
static func seed(person: RefCounted, other_id: StringName, value: int) -> void:
	assert(value >= -100 and value <= 100 and not other_id.is_empty() and other_id != StringName(person.id))
	person._write_opinion(other_id, value)
