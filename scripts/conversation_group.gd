extends RefCounted
## Stable membership and formation data for the temporary world adapter; no visual nodes.
const Balance = preload("res://scripts/balance_config.gd")
var id: int
var participants: Array[String] = []
var center := Vector2.ZERO
var positions: Dictionary = {}
var _slots: Dictionary = {}
func _init(group_id: int, world_center: Vector2 = Vector2.ZERO) -> void:
	id = group_id
	center = world_center
func add_participant(resident_id: String) -> Vector2:
	if positions.has(resident_id): return positions[resident_id]
	var slot := 0
	while slot in _slots.values(): slot += 1
	_slots[resident_id] = slot
	# More rings allow unlimited members without moving existing slots.
	var ring := floori(float(slot) / 8.0)
	var angle := (slot % 8) * TAU / 8.0
	var position := center + Vector2.from_angle(angle) * Balance.CONVERSATION_POSITION_RADIUS * (ring + 1)
	positions[resident_id] = position
	participants.append(resident_id)
	return position
func remove_participant(resident_id: String) -> void:
	participants.erase(resident_id)
	positions.erase(resident_id)
	_slots.erase(resident_id)
