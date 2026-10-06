extends RefCounted
## Immediate command; no queue and no suspension. Independent of the renderer.
enum Type { MOVE_TO }
enum State { ACTIVE, COMPLETED, CANCELLED }
var id: StringName
var resident_id: String
var type: Type = Type.MOVE_TO
var target: Variant
var state: State = State.ACTIVE
func _init(command_id: StringName, owner_id: String, destination: Variant) -> void:
	id = command_id
	resident_id = owner_id
	target = destination
