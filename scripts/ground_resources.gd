extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Physical drops: lifetime and generic reserved pickup; no automatic transport.
const Drop = preload("res://scripts/ground_resource.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
signal added(drop: Drop)
signal removed(drop: Drop)
var drops: Array[Drop] = []
var _next_id := 1
var _clock: Node

func setup(clock: Node) -> void:
	_clock = clock
	_clock.minute_changed.connect(_on_minute)

func create_drop(resource: ResourceType.Type, amount: int, position: Vector2) -> Drop:
	if amount <= 0:
		return null
	var drop = Drop.new(resource, amount, position, _clock.total_minutes)
	drop.id = StringName("ground_%d" % _next_id)
	_next_id += 1
	drops.append(drop)
	if logger != null: logger.info(EventLog.RESOURCE, "GroundResource создан: %d %s на земле; срок 3 игровых дня" % [amount, ResourceType.Type.keys()[resource]])
	added.emit(drop)
	return drop

func _on_minute(now: int) -> void:
	for drop in drops.duplicate():
		if drop.age_minutes(now) >= drop.lifetime:
			drops.erase(drop)
			if logger != null: logger.info(EventLog.RESOURCE, "GroundResource исчез: истёк срок 3 игровых дня")
			removed.emit(drop)

func take_reserved(drop: Drop, worker_id: StringName) -> bool:
	if drop not in drops or drop.reservation_owner_id != worker_id or worker_id.is_empty() or drop.amount < 1: return false
	drop.amount -= 1
	drop.release(worker_id)
	if drop.amount == 0:
		drops.erase(drop)
		removed.emit(drop)
	return true
