extends Node
const Intent = preload("res://scripts/resident_intent.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
signal intent_completed(intent: Intent)
var resident_data: RefCounted
var position := Vector2.ZERO
var global_position: Vector2:
	get: return position
	set(value): position=value
var target_position := Vector2.ZERO
var has_movement_target := false
var selected := false
var movement_speed := 120.0
var _active_intent: Intent
var _time_speed := 1
func setup(data: RefCounted) -> void: resident_data=data
func get_sim_position() -> Vector2: return position
func set_selected(value: bool) -> void: selected=value
func set_time_speed(value: int) -> void: _time_speed=value
func move_to(target: Vector2) -> void:
	_active_intent=null
	target_position=target
	has_movement_target=not position.is_equal_approx(target)
func apply_intent(intent: Intent) -> void:
	if intent.type==Intent.Type.NONE:
		_active_intent=null
		has_movement_target=false
		return
	move_to(intent.target_position)
	_active_intent=intent
	if not has_movement_target: _complete()
func _process(delta: float) -> void:
	if get_tree().paused or not has_movement_target or delta<=0: return
	position=position.move_toward(target_position,Modifiers.movement_speed(resident_data,movement_speed)*_time_speed*delta)
	if position.is_equal_approx(target_position):
		has_movement_target=false
		_complete()
func _complete() -> void:
	if _active_intent!=null:
		var completed=_active_intent
		_active_intent=null
		intent_completed.emit(completed)
