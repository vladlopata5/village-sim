extends RefCounted
## Intent data contains no resident, scene, UI or movement implementation.
enum Type { NONE, MOVE_TO }

var building_id: StringName = &""
var slot_purpose := -1
var courier_outside := false # Ground surplus unload: keep the acquired source slot at its exterior.
# Optional one-use Builder route hint. Geometry only; no resource ownership.
var prepared_path: Dictionary = {}
var resource_handling: StringName = &"" # Committed stationary resource operation.
var type: Type
var reason_id: StringName
var target_position: Vector2
var priority: int
var interruptible: bool

func _init(intent_type: Type = Type.NONE, reason: StringName = &"", target: Vector2 = Vector2.ZERO, intent_priority: int = 0, can_interrupt: bool = true) -> void:
	type = intent_type
	reason_id = reason
	target_position = target
	priority = intent_priority
	interruptible = can_interrupt
