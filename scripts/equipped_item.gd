extends RefCounted
## One concrete worn item. Remaining game minutes avoid integer-percent wear steps.
const Balance=preload("res://scripts/balance_config.gd")
var _resource: int
var _remaining: float
var resource_type: int:
	get:return _resource
var remaining_minutes: float:
	get:return _remaining
var durability: float:
	get:return _remaining/Balance.CLOTHING_LIFETIME_MINUTES
func _init(resource: int, remaining: float=Balance.CLOTHING_LIFETIME_MINUTES) -> void:
	_resource=resource
	_remaining=clampf(remaining,0.0,Balance.CLOTHING_LIFETIME_MINUTES) if is_finite(remaining) else 0.0
func wear(minutes: int) -> void:
	_remaining=maxf(_remaining-maxi(minutes,0),0.0)
