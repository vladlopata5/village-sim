extends Node
## Late world-input adapter: GUI consumes clicks first; placement precedes residents.
const Placement = preload("res://scripts/building_placement.gd")
const Ghost = preload("res://scripts/building_ghost_2d.gd")
var placement: Placement
var field: Node2D
var ghost: Ghost
var _world: Node2D
var _cursor_screen_position := Vector2.ZERO
func setup(model: Placement, world_field: Node2D, world: Node2D) -> void:
	placement = model
	field = world_field
	_world = world
	placement.changed.connect(refresh)
	refresh()
func refresh() -> void:
	if not placement.is_active():
		if is_instance_valid(ghost): ghost.queue_free()
		ghost = null
		return
	if ghost == null:
		ghost = Ghost.new()
		_world.add_child(ghost)
	var local_point: Vector2 = field.get_global_transform_with_canvas().affine_inverse() * _cursor_screen_position
	placement.update_position(field.to_global(local_point))
	ghost.refresh(placement.selected_definition, placement.position, placement.can_place())
func _input(event: InputEvent) -> void:
	# Track motion even over GUI; do not consume or act on GUI clicks.
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_cursor_screen_position = event.position

func _process(_delta: float) -> void:
	if placement.is_active(): refresh()
func _unhandled_key_input(event: InputEvent) -> void:
	if placement.is_active() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		placement.cancel()
		get_viewport().set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	if not placement.is_active(): return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_point: Vector2 = field.get_global_transform_with_canvas().affine_inverse() * event.position
			placement.update_position(field.to_global(local_point))
			if field.FIELD.has_point(local_point): placement.confirm()
			if ghost != null: ghost.refresh(placement.selected_definition, placement.position, placement.can_place())
		get_viewport().set_input_as_handled()
