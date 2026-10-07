extends RefCounted
## One resident's subjective opinion of another, identified by stable data ID.
## Future directed metadata can live here; pair compatibility/events/kinship stay separate.
const Balance = preload("res://scripts/balance_config.gd")
signal opinion_changed
var other_resident_id: StringName
var opinion: int = Balance.OPINION_NEUTRAL:
	set(value):
		var bounded := clampi(value, Balance.OPINION_MIN, Balance.OPINION_MAX)
		if opinion == bounded: return
		opinion = bounded
		opinion_changed.emit()
func _init(other_id: StringName) -> void:
	other_resident_id = other_id
