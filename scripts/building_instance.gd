extends RefCounted
## One entity for the entire lifecycle; changing state never replaces its identity.
const Definition = preload("res://scripts/building_definition.gd")
const ResourceContainer = preload("res://scripts/resource_container.gd")
const Balance = preload("res://scripts/balance_config.gd")
enum State { UNDER_CONSTRUCTION, BUILT }
var id: StringName
var definition: Definition
var position: Vector2
var state: State
var resources: ResourceContainer
var production_progress: int = 0
var logistics_weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT
# Compatibility accessors keep existing systems using the same instance data.
var display_name: String:
	get: return definition.display_name
var type: int:
	get: return definition.type
func _init(instance_id: StringName, building_definition: Definition, world_position: Vector2 = Vector2.ZERO, initial_state: State = State.BUILT) -> void:
	id = instance_id
	definition = building_definition
	position = world_position
	state = initial_state
	resources = ResourceContainer.new(id)
func is_built() -> bool: return state == State.BUILT
func footprint() -> Rect2: return Rect2(position - definition.size / 2.0, definition.size)
