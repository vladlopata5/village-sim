extends RefCounted
## Persistent domain state. Reservation is temporary; work belongs to the tree.
const Balance = preload("res://scripts/balance_config.gd")
enum State { STANDING, DEPLETED, SAPLING }
const KIND := &"TREE"
signal changed
var id: StringName
var position: Vector2
var physical_radius := Balance.TREE_PHYSICAL_RADIUS
var work_required := Balance.TREE_WORK_MINUTES
var yield_resource_type := preload("res://scripts/resource_type.gd").Type.LOG
var yield_amount := Balance.TREE_LOG_YIELD
var state := State.STANDING
var growth_required := Balance.TREE_GROWTH_MINUTES
var growth_progress := 0
var work_done := 0
var reservation_owner_id := &""
func _init(entity_id: StringName, simulation_position: Vector2) -> void:
	id = entity_id
	position = simulation_position
func claim(worker: StringName) -> bool:
	if worker.is_empty() or state != State.STANDING or not reservation_owner_id.is_empty(): return false
	reservation_owner_id = worker
	changed.emit()
	return true
func release(worker: StringName) -> void:
	if reservation_owner_id != worker: return
	reservation_owner_id = &""
	changed.emit()
func add_work(worker: StringName, minutes: int) -> bool:
	if worker.is_empty() or state != State.STANDING or reservation_owner_id != worker or minutes <= 0: return false
	work_done = mini(work_done + minutes,work_required)
	if work_done >= work_required:
		state = State.DEPLETED
		reservation_owner_id = &""
	changed.emit()
	return true

func make_sapling() -> void:
	state = State.SAPLING
	physical_radius = Balance.SAPLING_PHYSICAL_RADIUS
	growth_progress = 0
	changed.emit()
func grow(minutes: int) -> bool:
	if state != State.SAPLING: return false
	growth_progress = mini(growth_required,growth_progress+maxi(minutes,0))
	if growth_progress < growth_required: return false
	state = State.STANDING
	physical_radius = Balance.TREE_PHYSICAL_RADIUS
	changed.emit()
	return true
