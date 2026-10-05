extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Tracks lifetime in game minutes; no pickup or container access.
const Drop = preload("res://scripts/ground_resource.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
signal added(drop: Drop)
signal removed(drop: Drop)
var drops: Array[Drop] = []
var _clock: Node

func setup(clock: Node) -> void:
	_clock = clock
	_clock.minute_changed.connect(_on_minute)

func create_drop(resource: ResourceType.Type, amount: int, position: Vector2) -> Drop:
	if amount <= 0:
		return null
	var drop = Drop.new(resource, amount, position, _clock.total_minutes)
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
