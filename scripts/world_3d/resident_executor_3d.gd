extends Node3D
## Sole physical position owner in 3D. The child view has no independent movement.
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
signal intent_completed(intent: Intent)
signal intent_failed(intent: Intent)
var resident_data: RefCounted
var view = preload("res://scripts/world_3d/resident_view_3d.gd").new()
var movement = preload("res://scripts/world_3d/grid_movement_3d.gd").new()
var navigation: RefCounted
var _active: Intent
var _time_speed := 1
func setup(data: RefCounted) -> void:
	resident_data = data
	view.setup(data)
	view.name = "ResidentView3D"
	add_child(view)
	movement.body = self
	movement.navigation = navigation
	movement.name = "NavigationMovement"
	add_child(movement)
	movement.set_physics_process(false)
	movement.arrived.connect(_arrived)
	movement.failed.connect(_failed)
func get_world_position() -> Vector3: return global_position
func get_sim_position() -> Vector2: return Coordinates.to_sim(get_world_position())
# Interrupted cargo cannot be left inside a hard-blocked interior.
func get_drop_sim_position() -> Vector2:
	if not is_instance_valid(_marker):
		return Coordinates.to_sim(_entry_position) if not _building.is_empty() else get_sim_position()
	return Coordinates.to_sim(_entry_position) if _marker.purpose!=Slot.Purpose.CONSTRUCTION else get_sim_position()
func set_selected(value: bool) -> void: view.set_selected(value)
func set_time_speed(multiplier: int) -> void: _time_speed = multiplier
func move_to(target: Vector2) -> void:
	_exit_building()
	_active = null
	movement.set_target(Coordinates.to_world(target))
func apply_intent(intent: Intent) -> void:
	if intent.type == Intent.Type.NONE:
		_active = null
		movement.stop()
		if not _reporting_arrival: _exit_building()
		return
	move_to(intent.target_position)
	_active = intent
func _physics_process(delta: float) -> void:
	movement.speed = Coordinates.length_to_world(Modifiers.movement_speed(resident_data, 120.0)) * _time_speed
	movement.advance(delta)
func _arrived() -> void:
	if uses!=null and _active!=null and not _active.building_id.is_empty():
		_enter_or_wait()
		return
	_finish_arrival()
func _finish_arrival() -> void:
	var completed = _active
	_active = null
	if completed != null:
		_reporting_arrival=true
		intent_completed.emit(completed)
		_reporting_arrival=false
		_release_finished()
func _failed() -> void:
	var failed_intent = _active
	_active = null
	if failed_intent != null: intent_failed.emit(failed_intent)

const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
signal building_use_unavailable(intent: Intent)
var uses: RefCounted
var _intents: Node
var _building: StringName = &""
var _marker: Marker3D
var _waiting := false
var _reporting_arrival := false
var _entry_position := Vector3.ZERO
func bind_building_use(service: RefCounted, intents: Node) -> void:
	uses=service
	uses.executors[resident_data.id]=weakref(self)
	_intents=intents
	uses.slots_changed.connect(_slot_changed)
	uses.removed.connect(_building_removed)
	intents.forced_interrupt.connect(_forced_exit)
	resident_data.activity_changed.connect(_check_activity)
func _exit_building() -> void:
	_waiting=false
	if not is_instance_valid(_marker):
		if not _building.is_empty() and is_inside_tree(): global_position=_entry_position
		_marker=null
		_building=&""
		return
	var marker := _marker
	var id := _building
	_marker=null
	_building=&""
	if marker.purpose!=Slot.Purpose.CONSTRUCTION and is_inside_tree():
		global_position=_entry_position
	uses.release(id,marker,resident_data.id)
func _forced_exit(_intent: Intent) -> void: _exit_building()
func _check_activity() -> void:
	if not _reporting_arrival: _release_finished()
func _release_finished() -> void:
	if _intents!=null and not _intents.current_intent.resource_handling.is_empty(): return
	if resident_data.activity not in [preload("res://scripts/resident_activity.gd").Type.WORKING,preload("res://scripts/resident_activity.gd").Type.EATING,preload("res://scripts/resident_activity.gd").Type.SLEEPING] and (_active==null or _active.type==Intent.Type.NONE): _exit_building()
func _enter_or_wait() -> void:
	if _active==null or _marker!=null or _active.building_id.is_empty() or movement.is_moving(): return
	if _active.slot_purpose==Slot.Purpose.COURIER and not uses.courier_position(_active.building_id) is Vector3:
		_failed()
		return
	if _active.slot_purpose==Slot.Purpose.CONSTRUCTION:
		var free: Array = uses.choices(_active.building_id,_active.slot_purpose,global_position)
		if not free.is_empty() and global_position.distance_to(free[0].global_position)>0.1:
			movement.set_target(free[0].global_position)
			return
	var arriving := _active
	var marker: Marker3D = uses.acquire(arriving.building_id,arriving.slot_purpose,resident_data.id,global_position)
	# Occupancy signals can synchronously interrupt this action.
	if _active!=arriving:
		if marker!=null: uses.release(arriving.building_id,marker,resident_data.id)
		return
	if marker==null:
		if _active.slot_purpose in [Slot.Purpose.WORKER,Slot.Purpose.COURIER]:
			_waiting=true
			return
		var unavailable := _active
		_active=null
		building_use_unavailable.emit(unavailable)
		return
	_waiting=false
	_building=_active.building_id
	_marker=marker
	_entry_position=global_position
	# This transition can later animate/internal-navigate without changing actions.
	if marker.purpose!=Slot.Purpose.CONSTRUCTION: global_position=marker.global_position
	_finish_arrival()
func _slot_changed(id: StringName, purpose: int) -> void:
	if _waiting and _active!=null and _active.building_id==id and _active.slot_purpose==purpose: call_deferred("_enter_or_wait")
func _building_removed(id: StringName) -> void:
	if _building==id or (_active!=null and _active.building_id==id):
		_exit_building()
		if _intents!=null: _intents.abort_current(_intents.current_intent)
		_failed()
func _exit_tree() -> void:
	_exit_building()
	if uses!=null: uses.executors.erase(resident_data.id)
