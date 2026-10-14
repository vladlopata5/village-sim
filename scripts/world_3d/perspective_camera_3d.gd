extends "res://scripts/prototypes/prototype_camera_3d.gd"
## Canonical perspective adapter. The orthographic prototype retains its defaults.
@export var min_distance: float = 19.02956881
@export var max_distance: float = 253.72758419
@export var distance_step: float = 5.07455168

func get_focus_position() -> Vector3:
	# The view remains aimed at the ground. Derive focus; do not keep a second rig state.
	return global_position - global_basis.z * get_zoom_distance()

func get_zoom_distance() -> float:
	return global_position.y / global_basis.z.y

func set_zoom_distance(distance: float) -> void:
	var focus := get_focus_position()
	global_position = focus + global_basis.z * clampf(distance, min_distance, max_distance)

func zoom(steps: float) -> void:
	set_zoom_distance(get_zoom_distance() - steps * distance_step)

func orbit_to_yaw(yaw_degrees: float) -> void:
	# Existing code/tests may change direction; keep the same pitch and ground pivot.
	# No new player hotkeys are introduced.
	var focus := get_focus_position()
	var distance := get_zoom_distance()
	rotation_degrees.y = yaw_degrees
	global_position = focus + global_basis.z * distance

func drag_pan(relative: Vector2, screen_position: Variant = null) -> void:
	var cursor: Vector2 = get_viewport().get_visible_rect().size / 2 if screen_position == null else screen_position
	var ground := Plane(Vector3.UP, 0)
	var previous: Variant = ground.intersects_ray(project_ray_origin(cursor-relative), project_ray_normal(cursor-relative))
	var current_point: Variant = ground.intersects_ray(project_ray_origin(cursor), project_ray_normal(cursor))
	if previous == null or current_point == null: return
	# Unlike parallel orthographic rays, perspective rays vary across the screen.
	global_position += previous-current_point

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_mouse_panning = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_panning:
		drag_pan(event.relative, event.position)
		get_viewport().set_input_as_handled()
