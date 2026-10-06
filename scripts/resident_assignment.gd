extends RefCounted
## Persistent request. List order is history, never execution priority.
const EAT_AT_TARGET := &"eat_at_target"
const TALK_TO := &"talk_to"
enum Importance { LOW, NORMAL, HIGH }
var importance: Importance = Importance.NORMAL
enum State { QUEUED, ACTIVE, SUSPENDED, COMPLETED, CANCELLED }
var id: StringName
var resident_id: String
var type: StringName
var target: Variant
var state: State = State.QUEUED
func _init(assignment_id: StringName, owner_id: String, assignment_type: StringName = &"", assignment_target: Variant = null) -> void:
	id = assignment_id
	resident_id = owner_id
	type = assignment_type
	target = assignment_target
