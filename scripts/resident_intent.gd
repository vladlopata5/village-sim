extends RefCounted
## Intent data contains no resident, scene, UI or movement implementation.
enum Type { NONE, MOVE_TO }

var type: Type
var reason_id: StringName
var target_position: Vector2
var priority: int

func _init(intent_type: Type = Type.NONE, reason: StringName = &"", target: Vector2 = Vector2.ZERO, intent_priority: int = 0) -> void:
	type = intent_type
	reason_id = reason
	target_position = target
	priority = intent_priority
