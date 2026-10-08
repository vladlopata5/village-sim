extends Node3D
## Sole physical position owner in 3D. The child view has no independent movement.
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
signal intent_completed(intent: Intent)
signal intent_failed(intent: Intent)
var resident_data: RefCounted
var view = preload("res://scripts/world_3d/resident_view_3d.gd").new()
var movement = preload("res://scripts/prototypes/resident_movement_3d.gd").new()
var agent := NavigationAgent3D.new()
var _active: Intent
var _time_speed := 1
func setup(data: RefCounted) -> void:
	resident_data = data
	view.setup(data)
	view.name = "ResidentView3D"
	add_child(view)
	agent.radius = 10.0
	agent.path_desired_distance = 0.5
	agent.target_desired_distance = 0.75
	agent.avoidance_enabled = false
	add_child(agent)
	movement.body = self
	movement.agent = agent
	movement.surface_tolerance = 3.0
	movement.name = "NavigationMovement"
	add_child(movement)
	movement.set_physics_process(false)
	movement.arrived.connect(_arrived)
	movement.failed.connect(_failed)
func get_sim_position() -> Vector2: return Coordinates.to_sim(global_position)
func set_selected(value: bool) -> void: view.set_selected(value)
func set_time_speed(multiplier: int) -> void: _time_speed = multiplier
func move_to(target: Vector2) -> void:
	_active = null
	movement.set_target(Coordinates.to_world(target))
func apply_intent(intent: Intent) -> void:
	if intent.type == Intent.Type.NONE:
		_active = null
		movement.stop()
		return
	move_to(intent.target_position)
	_active = intent
func _physics_process(delta: float) -> void:
	movement.speed = Modifiers.movement_speed(resident_data, 120.0) * _time_speed
	movement.advance(delta)
func _arrived() -> void:
	var completed = _active
	_active = null
	if completed != null: intent_completed.emit(completed)
func _failed() -> void:
	var failed_intent = _active
	_active = null
	if failed_intent != null: intent_failed.emit(failed_intent)
