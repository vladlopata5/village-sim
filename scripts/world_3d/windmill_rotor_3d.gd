extends Node3D
## Decorative only: real seconds, inherited game pause, no simulation callbacks.
const ANGULAR_SPEED := PI / 6.0
func _process(delta: float) -> void:
	rotation.z = fposmod(rotation.z + ANGULAR_SPEED * delta, TAU)
