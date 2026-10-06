extends RefCounted
## UI reads these options; execution belongs to the interaction service.
enum Kind { PLAYER_COMMAND, RESIDENT_ASSIGNMENT, MANAGEMENT_ACTION }
var id: StringName
var label: String
var enabled := true
var disabled_reason := ""
var interaction_kind: Kind
var target_id: StringName
func _init(option_id: StringName, text: String, kind: Kind, target: StringName, available: bool = true, reason: String = "") -> void:
	id = option_id
	label = text
	interaction_kind = kind
	target_id = target
	enabled = available
	disabled_reason = reason
