extends RefCounted
signal changed
var base_weight: int = 100
var value: int = 0:
	set(next):
		var bounded := clampi(next, 0, 100)
		if value != bounded:
			value = bounded
			changed.emit()
func _init(initial_value: int = 0, weight: int = 100) -> void:
	value = initial_value
	base_weight = weight
func get_effective_weight() -> int:
	# Need state retains its base weight; action attractiveness is resolved separately.
	return base_weight
func get_priority() -> int:
	return value * get_effective_weight()
