extends RefCounted
## Placement rules operate on the existing world registry, independently of UI.
const Definition = preload("res://scripts/building_definition.gd")
const Instance = preload("res://scripts/building_instance.gd")
const EventLog = preload("res://scripts/game_logger.gd")
signal changed
signal placed(building: Instance)
var logger: EventLog
var buildings: Array
var selected_definition: Definition
var position := Vector2.ZERO
var _next_id := 1
func setup(registry: Array) -> void: buildings = registry
func is_active() -> bool: return selected_definition != null
func select(definition: Definition) -> void:
	selected_definition = definition
	if logger != null: logger.info(EventLog.BUILDING, "выбран тип здания — %s" % definition.display_name)
	changed.emit()
func update_position(world_position: Vector2) -> void:
	position = world_position
func can_place() -> bool:
	if not is_active(): return false
	var proposed := Rect2(position - selected_definition.size / 2.0, selected_definition.size)
	for building in buildings:
		if proposed.intersects(building.footprint()): return false
	return true
func confirm() -> Instance:
	if not can_place():
		if is_active() and logger != null: logger.debug(EventLog.BUILDING, "Нельзя разместить здание здесь — пересечение footprint")
		return null
	var id := StringName("building_%04d" % _next_id)
	while buildings.any(func(existing): return existing.id == id):
		_next_id += 1
		id = StringName("building_%04d" % _next_id)
	_next_id += 1
	var building := _create_instance(id)
	buildings.append(building)
	if logger != null: logger.info(EventLog.BUILDING, "размещено здание %s — %s, state=UNDER_CONSTRUCTION" % [id, building.display_name])
	selected_definition = null
	placed.emit(building)
	changed.emit()
	return building
func cancel() -> void:
	if not is_active(): return
	selected_definition = null
	if logger != null: logger.info(EventLog.BUILDING, "placement отменён")
	changed.emit()

func _create_instance(id: StringName) -> Instance:
	return Instance.new(id, selected_definition, position, Instance.State.UNDER_CONSTRUCTION)
