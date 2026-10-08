extends Node
## UI consumes input first; ray queries run on a physics boundary.
const View = preload("res://scripts/prototypes/pickable_view_3d.gd")
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
var camera: Camera3D
var ground: StaticBody3D
var selection: Node
var control: Node
var _clicks: Array[InputEventMouseButton] = []
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		selection.clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_clicks.append(event)
		get_viewport().set_input_as_handled()
func _physics_process(_delta: float) -> void:
	for event in _clicks:
		handle_hit(event.button_index, pick(event.position))
	_clicks.clear()
func pick(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var target := origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(origin, target, 3)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)
func handle_hit(button: int, hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	if button == MOUSE_BUTTON_LEFT:
		if collider is View and collider.entity != null:
			if collider.entity_kind == View.Kind.RESIDENT: selection.select(collider.entity)
			else: selection.select_building(collider.entity)
		else: selection.clear()
	elif button == MOUSE_BUTTON_RIGHT and collider == ground and hit.has("position"):
		control.move_to(Coordinates.to_sim(hit.position))
