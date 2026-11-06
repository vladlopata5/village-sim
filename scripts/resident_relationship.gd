extends RefCounted
## One resident's subjective opinion of another, identified by stable data ID.
## Future directed metadata can live here; pair compatibility/events/kinship stay separate.
const Balance = preload("res://scripts/balance_config.gd")
signal opinion_changed
var other_resident_id: StringName
var _opinion: int = Balance.OPINION_NEUTRAL
var opinion: int:
	get: return _opinion

# ResidentData validates the pair and bounds before committing a directed change.
func _commit_opinion(value: int) -> void:
	if _opinion == value: return
	_opinion = value
	opinion_changed.emit()
func _init(other_id: StringName) -> void:
	other_resident_id = other_id
