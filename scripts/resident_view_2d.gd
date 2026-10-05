extends Node2D
## Temporary representation. This reference points to data owned outside the view.
const Clock = preload("res://scripts/game_time.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const ResidentIntent = preload("res://scripts/resident_intent.gd")
signal selection_requested(data: ResidentData)
signal intent_completed(intent: ResidentIntent)
var name_caption: Label
var cargo_indicator: Label
var resident_data: ResidentData
@export_range(1.0, 1000.0) var movement_speed: float = 120.0
var target_position: Vector2 = Vector2.ZERO
var has_movement_target: bool = false
var _time_speed: int = 1
var _active_intent: ResidentIntent

func setup(data: ResidentData) -> void:
	resident_data = data
	if name_caption == null:
		name_caption = Label.new()
		name_caption.position = Vector2(-30, 22)
		name_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_caption)
	name_caption.text = data.resident_name
	if cargo_indicator == null:
		cargo_indicator = Label.new()
		cargo_indicator.text = "■ FOOD"
		cargo_indicator.position = Vector2(24, -24)
		cargo_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cargo_indicator)
	resident_data.inventory.changed.connect(_update_cargo)
	_update_cargo()
	queue_redraw()

func _draw() -> void:
	if resident_data == null:
		return
	# A simple head and body, with a dark outline for visibility on the field.
	draw_circle(Vector2.ZERO, 19.0, Color("28313b"))
	draw_circle(Vector2.ZERO, 16.0, Color("f2c66d"))
	draw_circle(Vector2(0, -22), 10.0, Color("28313b"))
	draw_circle(Vector2(0, -22), 7.0, Color("ffe5bb"))

func _unhandled_input(event: InputEvent) -> void:
	if resident_data == null or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if local_point.length() <= 19.0 or local_point.distance_to(Vector2(0, -22)) <= 10.0:
			selection_requested.emit(resident_data)
			get_viewport().set_input_as_handled()

## Temporary command API, independent of mouse input or resident traits.
func move_to(world_target: Vector2) -> void:
	_active_intent = null
	target_position = world_target
	has_movement_target = not global_position.is_equal_approx(target_position)

func set_time_speed(multiplier: int) -> void:
	if multiplier in Clock.SUPPORTED_SPEEDS:
		_time_speed = multiplier

func _process(delta: float) -> void:
	# This view processes input on pause, but never advances paused movement.
	if get_tree().paused or not has_movement_target or delta <= 0.0:
		return
	global_position = global_position.move_toward(target_position, movement_speed * _time_speed * delta)
	if global_position.is_equal_approx(target_position):
		global_position = target_position
		has_movement_target = false
		_complete_intent()

func apply_intent(intent: ResidentIntent) -> void:
	if intent.type == ResidentIntent.Type.NONE:
		_active_intent = null
		has_movement_target = false
		return
	move_to(intent.target_position)
	_active_intent = intent
	if not has_movement_target:
		_complete_intent()

func _complete_intent() -> void:
	if _active_intent != null:
		var completed := _active_intent
		_active_intent = null
		intent_completed.emit(completed)

func _update_cargo() -> void:
	cargo_indicator.visible = resident_data.inventory.amount > 0
