extends Node3D
## Sole physical position owner. Shares the resident navigation and segment mover.
const Animal = preload("res://scripts/animal_data.gd")
const Balance = preload("res://scripts/balance_config.gd")
var data: Animal
var navigation: RefCounted
var movement = preload("res://scripts/world_3d/grid_movement_3d.gd").new()
var behavior = preload("res://scripts/animal_behavior_controller.gd").new()
var view = preload("res://scripts/world_3d/sheep_view_3d.gd").new()
var _time_speed := 1
var _motion_token := -1
func setup(animal: Animal, clock: Node) -> void:
	data = animal
	global_position = data.position
	add_child(view)
	view.setup(data)
	movement.body = self
	movement.navigation = navigation
	# No animal road bonus yet; retain the existing slow terrain, including trees.
	movement.surface_speed = func(_cell: Vector2i, planned: float): return minf(planned,1.0)
	add_child(movement)
	movement.arrived.connect(_arrived)
	movement.failed.connect(_failed)
	movement.path_changed.connect(_path_changed)
	add_child(behavior)
	behavior.wander_offer = _wander_offer
	behavior.movement_requested.connect(_move)
	behavior.stop_requested.connect(movement.stop)
	_time_speed = clock.speed_multiplier
	clock.speed_changed.connect(set_time_speed)
	behavior.setup(data,clock)
func get_world_position() -> Vector3: return global_position
func set_time_speed(multiplier: int) -> void: _time_speed = multiplier
func _wander_offer(random: RandomNumberGenerator) -> Dictionary:
	if not navigation.is_world_walkable(global_position): return {}
	for attempt in Balance.SHEEP_TARGET_ATTEMPTS:
		var angle := random.randf()*TAU
		var radius := sqrt(random.randf())*data.habitat_radius
		var target := data.habitat_center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if global_position.distance_to(target)<Balance.SHEEP_MIN_WALK_DISTANCE or not navigation.is_world_walkable(target): continue
		if not navigation.can_reach_point(global_position,target): continue
		var raw: PackedVector3Array = navigation.find_raw_path(global_position,target)
		# A destination inside the disk is insufficient: an obstacle detour can leave it.
		if raw.is_empty() or not Array(raw).all(data.contains) or not navigation.is_raw_path_walkable(raw): continue
		return {"target":target,"prepared":{"raw":raw,"navigation_id":navigation.get_instance_id(),"revision":navigation.revision,"start":global_position,"target":target}}
	return {}
func _move(action_token: int, target: Vector3, prepared: Dictionary) -> void:
	if action_token != behavior.token or data.behavior != Animal.Behavior.WANDER: return
	_motion_token = action_token
	movement.set_target(target,prepared)
func _arrived() -> void:
	data.position = global_position
	behavior.finish_wander(_motion_token,true)
func _failed() -> void:
	data.position = global_position
	behavior.finish_wander(_motion_token,false)
func _path_changed(points: PackedVector3Array) -> void:
	# Revision replans also have to stay inside the convex habitat disk.
	if not points.is_empty() and not Array(points).all(data.contains):
		movement.stop()
		_failed()
func _physics_process(delta: float) -> void:
	if data == null: return
	var previous := global_position
	movement.speed = Balance.SHEEP_WALK_SPEED*_time_speed
	movement.advance(delta)
	data.position = global_position
	view.face_movement(global_position-previous)
