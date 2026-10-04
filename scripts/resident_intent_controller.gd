extends Node
## The single owner of the current intent; renderers are connected via signals.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
signal intent_changed(intent: ResidentIntent)
var current_intent: ResidentIntent = ResidentIntent.new()

func submit(intent: ResidentIntent) -> bool:
	if intent == null or intent.type != ResidentIntent.Type.MOVE_TO:
		return false
	if current_intent.type != ResidentIntent.Type.NONE:
		# Same-source retargeting preserves repeated manual right clicks.
		var same_source_update := intent.priority == current_intent.priority and intent.reason_id == current_intent.reason_id
		if intent.priority <= current_intent.priority and not same_source_update:
			return false
	current_intent = intent
	intent_changed.emit(current_intent)
	return true

func clear_completed(completed_intent: ResidentIntent) -> bool:
	# An old arrival must not clear a newer accepted intention.
	if current_intent.type == ResidentIntent.Type.NONE or completed_intent != current_intent:
		return false
	current_intent = ResidentIntent.new()
	intent_changed.emit(current_intent)
	return true

func clear_reason(reason_id: StringName) -> void:
	# Cancel only the matching source; NONE also stops its visual execution.
	if current_intent.type != ResidentIntent.Type.NONE and current_intent.reason_id == reason_id:
		clear_completed(current_intent)
