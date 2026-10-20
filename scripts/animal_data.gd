extends RefCounted
## Animal state in WORLD units. The executor is the sole physical position owner.
const Balance = preload("res://scripts/balance_config.gd")
enum Species { SHEEP }
enum Status { WILD, DOMESTIC }
enum Behavior { IDLE, WANDER, GRAZE, SLEEP, RETURN_HOME }
signal changed
var id: StringName
var species: Species = Species.SHEEP
var status: Status = Status.WILD
var home_id: StringName
var position: Vector3
var habitat_center: Vector3
var habitat_radius: float = Balance.SHEEP_HABITAT_RADIUS
var behavior: Behavior = Behavior.IDLE
var behavior_started_at := -1
var behavior_ends_at := -1
var sleep_started_at := -1
var wake_at := -1
var wool_growth := 0:
	set(value):
		var next := clampi(value,0,Balance.SHEEP_MAX_WOOL)
		if wool_growth == next: return
		wool_growth = next
		changed.emit()
func _init(animal_id: StringName, center: Vector3, start: Vector3) -> void:
	id = animal_id
	habitat_center = center
	position = start
func contains(point: Vector3) -> bool:
	return point.is_finite() and Vector2(point.x,point.z).distance_squared_to(Vector2(habitat_center.x,habitat_center.z)) <= habitat_radius * habitat_radius
