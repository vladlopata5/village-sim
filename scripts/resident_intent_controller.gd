extends Node
## The single owner of the current intent; renderers are connected via signals.
const ResidentIntent = preload("res://scripts/resident_intent.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const Activity = preload("res://scripts/resident_activity.gd")
signal intent_completed(intent: ResidentIntent)
var resident_data: ResidentData

func setup(data: ResidentData) -> void:
	resident_data = data

func _set_activity(activity: Activity.Type) -> void:
	if resident_data != null:
		resident_data.activity = activity

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
	_set_activity(Activity.Type.MOVING)
	intent_changed.emit(current_intent)
	return true

func clear_completed(completed_intent: ResidentIntent) -> bool:
	# An old arrival must not clear a newer accepted intention.
	if current_intent.type == ResidentIntent.Type.NONE or completed_intent != current_intent:
		return false
	current_intent = ResidentIntent.new()
	_set_activity(Activity.Type.IDLE)
	intent_changed.emit(current_intent)
	intent_completed.emit(completed_intent)
	return true

func clear_reason(reason_id: StringName) -> void:
	# Cancel only the matching source; NONE also stops its visual execution.
	if current_intent.type != ResidentIntent.Type.NONE and current_intent.reason_id == reason_id:
		current_intent = ResidentIntent.new()
		_set_activity(Activity.Type.IDLE)
		intent_changed.emit(current_intent)
