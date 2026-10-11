extends RefCounted
## Domain truth. A completion receipt is unique even across reentrant signals.
const Balance = preload("res://scripts/balance_config.gd")
signal changed
var id: StringName
var position: Vector2
var physical_radius := Balance.ROCK_PHYSICAL_RADIUS
var initial_stock := Balance.ROCK_STONE_STOCK
var stock := Balance.ROCK_STONE_STOCK
var work_required := Balance.ROCK_WORK_MINUTES
var work_done := 0
var completed_cycles := 0
var reservation_owner_id := &""
func _init(entity_id: StringName, simulation_position: Vector2) -> void:
	id = entity_id
	position = simulation_position
func claim(worker: StringName) -> bool:
	if worker.is_empty() or stock <= 0 or not reservation_owner_id.is_empty(): return false
	reservation_owner_id = worker
	changed.emit()
	return true
func release(worker: StringName) -> void:
	if worker.is_empty() or reservation_owner_id != worker: return
	reservation_owner_id = &""
	changed.emit()
func add_work(worker: StringName, minutes: int) -> int:
	if worker.is_empty() or reservation_owner_id != worker or stock <= 0 or minutes <= 0: return 0
	work_done = mini(work_required,work_done+minutes)
	var receipt := 0
	if work_done == work_required:
		stock -= 1
		work_done = 0
		completed_cycles += 1
		receipt = completed_cycles
		reservation_owner_id = &""
	changed.emit()
	return receipt
