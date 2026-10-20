extends Node3D
## Sole physical position owner. Shares the resident navigation and segment mover.
const Animal = preload("res://scripts/animal_data.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var data: Animal
var navigation: RefCounted
var movement = preload("res://scripts/world_3d/grid_movement_3d.gd").new()
var behavior = preload("res://scripts/animal_behavior_controller.gd").new()
var view = preload("res://scripts/world_3d/sheep_view_3d.gd").new()
var _time_speed := 1
var _motion_token := -1
var movement_owner: Node
var home: RefCounted
var _hit_body: StaticBody3D
var _resume_after_frame := -1
func setup(animal: Animal, clock: Node) -> void:
	data = animal
	global_position = data.position
	add_child(view)
	view.setup(data)
	_hit_body=StaticBody3D.new()
	_hit_body.collision_layer=8;_hit_body.collision_mask=0
	_hit_body.set_meta("animal_id",data.id)
	var hit_shape:=CollisionShape3D.new()
	var capsule:=CapsuleShape3D.new();capsule.radius=Balance.SHEEP_NAV_RADIUS;capsule.height=0.8
	hit_shape.shape=capsule;hit_shape.position.y=0.4
	_hit_body.add_child(hit_shape);add_child(_hit_body)
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
func get_sim_position() -> Vector2: return Coordinates.to_sim(global_position)
func set_indoor(value: bool) -> void:
	view.visible=not value
	_hit_body.collision_layer=0 if value else 8
func set_time_speed(multiplier: int) -> void: _time_speed = multiplier
func _wander_offer(random: RandomNumberGenerator) -> Dictionary:
	if not navigation.is_world_walkable(global_position): return {}
	if home!=null and home.area()==null: return {}
	var center: Vector3 = home.area_center() if home!=null else data.habitat_center
	var extent: float = home.area_radius() if home!=null else data.habitat_radius
	for attempt in Balance.SHEEP_TARGET_ATTEMPTS:
		var angle := random.randf()*TAU
		var radius := sqrt(random.randf())*extent
		var target := center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if global_position.distance_to(target)<Balance.SHEEP_MIN_WALK_DISTANCE or not navigation.is_world_walkable(target): continue
		if not navigation.can_reach_point(global_position,target): continue
		var raw: PackedVector3Array = navigation.find_raw_path(global_position,target)
		# A destination inside the disk is insufficient: an obstacle detour can leave it.
		if raw.is_empty() or not _habitat_path(raw) or not navigation.is_raw_path_walkable(raw): continue
		return {"target":target,"prepared":{"raw":raw,"navigation_id":navigation.get_instance_id(),"revision":navigation.revision,"start":global_position,"target":target}}
	return {}
func _move(action_token: int, target: Vector3, prepared: Dictionary) -> void:
	if movement_owner != null: return
	if action_token != behavior.token or data.behavior not in [Animal.Behavior.WANDER,Animal.Behavior.RETURN_HOME]: return
	_motion_token = action_token
	movement.set_target(target,prepared)
func _arrived() -> void:
	data.position = global_position
	if movement_owner != null: return
	if home!=null and data.behavior==Animal.Behavior.RETURN_HOME:
		home.arrive(_motion_token)
		return
	behavior.finish_wander(_motion_token,true)
func _failed() -> void:
	data.position = global_position
	if movement_owner != null: return
	if home!=null and data.behavior==Animal.Behavior.RETURN_HOME:
		behavior._retry(behavior._clock.total_minutes)
		return
	behavior.finish_wander(_motion_token,false)
func _path_changed(points: PackedVector3Array) -> void:
	# Revision replans also have to stay inside the convex habitat disk.
	if movement_owner == null and data.behavior!=Animal.Behavior.RETURN_HOME and not points.is_empty() and not _habitat_path(points):
		movement.stop()
		_failed()
func _physics_process(delta: float) -> void:
	if data == null or movement_owner != null or (home!=null and home.is_inside()): return
	if _resume_after_frame >= 0:
		if Engine.get_physics_frames()==_resume_after_frame: return
		_resume_after_frame=-1
	_advance(delta,INF,INF)
func _advance(delta: float, cap: float, distance_limit: float) -> void:
	var previous := global_position
	movement.speed = minf(get_base_movement_speed(),cap)*_time_speed
	movement.advance(delta,distance_limit)
	data.position = global_position
	view.face_movement(global_position-previous)
func get_base_movement_speed() -> float: return Balance.SHEEP_WALK_SPEED
func claim_movement(requester: Node) -> bool:
	if movement_owner != null or (home!=null and home.is_inside()): return false
	movement_owner = requester
	behavior.suspend()
	return movement_owner == requester
func advance_owned(requester: Node, delta: float, cap: float, distance_limit: float) -> void:
	if movement_owner == requester: _advance(delta,cap,distance_limit)
func release_movement(requester: Node, _successful: bool) -> void:
	if movement_owner != requester: return
	movement.stop()
	movement_owner = null
	if Engine.is_in_physics_frame(): _resume_after_frame=Engine.get_physics_frames()
	if data.operation_id.is_empty(): behavior.resume()
func interrupt_movement() -> void:
	if is_instance_valid(movement_owner): movement_owner.cancel("follower_replaced")
func _habitat_path(points: PackedVector3Array) -> bool:
	# After an escort outside its wild habitat, a normal walk may return physically.
	var region: RefCounted=home.area() if home!=null else null
	var entered := _habitat_contains(points[0],region)
	for point in points:
		if _habitat_contains(point,region): entered = true
		elif entered: return false
	return entered
func _habitat_contains(point: Vector3, region: RefCounted) -> bool:
	return region.contains(Coordinates.to_sim(point)) if region!=null else data.contains(point)
func assign_home(building: RefCounted, uses: RefCounted, areas: RefCounted, requester: StringName = &"") -> bool:
	if home!=null: return home.building==building
	if movement_owner!=null or building==null or building.animal_housing==null: return false
	home=preload("res://scripts/world_3d/animal_home_3d.gd").new()
	var binding: RefCounted=home
	if binding.assign(self,building,uses,areas,requester): return true
	if home==binding: home=null
	return false
func release_home() -> void:
	if home!=null: home.release()
func _exit_tree() -> void:
	if is_instance_valid(movement_owner): movement_owner.cancel("follower_removed")
	if home!=null: home.release(false)
