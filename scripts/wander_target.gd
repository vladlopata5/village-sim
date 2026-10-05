extends RefCounted
## Replaceable candidate: a later POI provider can supply an ID and position instead.
const Balance = preload("res://scripts/balance_config.gd")
var id: StringName
var position: Vector2
func _init(target_id: StringName, world_position: Vector2) -> void:
	id = target_id
	position = world_position
static func nearby(origin: Vector2, rng: RandomNumberGenerator, bounds: Rect2):
	if not bounds.has_point(origin): return null
	for attempt in range(8):
		var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(Balance.WANDER_RADIUS * 0.3, Balance.WANDER_RADIUS)
		var target := (origin + offset).clamp(bounds.position, bounds.end - Vector2.ONE)
		if origin.distance_to(target) > 1.0: return load("res://scripts/wander_target.gd").new(&"random_nearby", target)
	return null
