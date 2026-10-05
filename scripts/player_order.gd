extends RefCounted
## Persistent player task foundation, separate from Profession and utility scores.
## Concrete types, execution and suspend/resume rules belong to a later step.
enum State { PENDING, ACTIVE, SUSPENDED, COMPLETED, CANCELLED }
var id: StringName
var resident_id: String
var type: StringName
# Semantic target (e.g. location/entity ID); never a visual Node reference.
var target: Variant
var state: State = State.PENDING

func _init(order_id: StringName, owner_id: String, order_type: StringName = &"", order_target: Variant = null) -> void:
	id = order_id
	resident_id = owner_id
	type = order_type
	target = order_target
