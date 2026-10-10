extends Camera3D
@export var movement_speed: float = 12.0
@export var zoom_step: float = 2.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 40.0
var _mouse_panning := false
func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1.0
	pan(direction, delta)
func _plane_direction(direction: Vector2) -> Vector3:
	var right := global_basis.x
	var forward := -global_basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()
	return right * direction.x - forward * direction.y
func pan(direction: Vector2, delta: float) -> void:
	global_position += _plane_direction(direction).limit_length() * movement_speed * maxf(delta, 0.0)
func drag_pan(relative: Vector2) -> void:
	# Orthographic projection supplies the current zoom/aspect world units per pixel.
	var viewport_size := get_viewport().get_visible_rect().size
	var pixels := viewport_size.x if keep_aspect == KEEP_WIDTH else viewport_size.y
	if pixels <= 0.0: return
	var units_per_pixel := size / pixels
	var vertical_projection := absf(global_basis.y.normalized().dot(_plane_direction(Vector2.UP)))
	if is_zero_approx(vertical_projection): return
	# Flattening camera up onto the ground foreshortens vertical motion: compensate
	# so the grabbed map point follows the cursor, without changing camera height.
	global_position += _plane_direction(Vector2(-relative.x, -relative.y / vertical_projection)) * units_per_pixel
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_mouse_panning = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _mouse_panning:
		drag_pan(event.relative)
		get_viewport().set_input_as_handled()
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: _mouse_panning = false
func zoom(steps: float) -> void:
	size = clampf(size - steps * zoom_step, min_zoom, max_zoom)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(-1.0)
			get_viewport().set_input_as_handled()
