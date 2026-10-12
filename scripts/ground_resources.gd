extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Physical drops: lifetime and generic reserved pickup; no automatic transport.
const Drop = preload("res://scripts/ground_resource.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
signal availability_changed
signal added(drop: Drop)
signal removed(drop: Drop)
var drops: Array[Drop] = [] # Ordered enumeration; mutate through this owner's APIs.
var _by_id: Dictionary = {} # References only; quantities/claims remain on Drop.
var _next_id := 1
var _clock: Node

func setup(clock: Node) -> void:
	_clock = clock
	_clock.minute_changed.connect(_on_minute)

func create_drop(resource: ResourceType.Type, amount: int, position: Vector2) -> Drop:
	if amount <= 0:
		return null
	var drop = Drop.new(resource, amount, position, _clock.total_minutes)
	while _by_id.has(StringName("ground_%d" % _next_id)): _next_id += 1
	drop.id = StringName("ground_%d" % _next_id)
	_next_id += 1
	return drop if register_drop(drop) else null

func get_by_id(id: StringName) -> Drop:
	return _by_id.get(id)

func register_drop(drop: Drop) -> bool:
	if drop == null or drop.id.is_empty() or drop.amount <= 0 or _by_id.has(drop.id): return false
	if not drop.availability_changed.is_connected(availability_changed.emit): drop.availability_changed.connect(availability_changed.emit)
	drops.append(drop)
	_by_id[drop.id] = drop
	if logger != null: logger.info(EventLog.RESOURCE, "GroundResource создан: %d %s на земле; срок 3 игровых дня" % [drop.amount, ResourceType.Type.keys()[drop.resource_type]])
	added.emit(drop)
	availability_changed.emit()
	return true

func _forget(drop: Drop) -> bool:
	if drop == null or get_by_id(drop.id) != drop: return false
	drops.erase(drop)
	_by_id.erase(drop.id)
	return true

func remove_drop(drop: Drop) -> bool:
	if not _forget(drop): return false
	drop.release(drop.reservation_owner_id)
	removed.emit(drop)
	availability_changed.emit()
	return true

func _on_minute(now: int) -> void:
	for drop in drops.duplicate():
		if drop.age_minutes(now) >= drop.lifetime and _forget(drop):
			drop.release(drop.reservation_owner_id)
			if logger != null: logger.info(EventLog.RESOURCE, "GroundResource исчез: истёк срок 3 игровых дня")
			removed.emit(drop)
			availability_changed.emit()

func take_reserved(drop: Drop, worker_id: StringName) -> bool:
	if drop == null or get_by_id(drop.id) != drop or drop.reservation_owner_id != worker_id or worker_id.is_empty() or drop.amount < 1: return false
	drop.amount -= 1
	drop.release(worker_id)
	if drop.amount == 0 and _forget(drop):
		removed.emit(drop)
	availability_changed.emit()
	return true
