extends RefCounted
## Future persistent AI task: queued after current action, can suspend/resume.
## This step adds data only, no concrete types, queue or executor.
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
