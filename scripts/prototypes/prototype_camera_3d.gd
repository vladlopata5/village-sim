extends Camera3D
@export var movement_speed: float = 12.0
@export var zoom_step: float = 2.0
@export var min_zoom: float = 8.0
@export var max_zoom: float = 40.0
func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): direction.y += 1.0
	pan(direction, delta)
func pan(direction: Vector2, delta: float) -> void:
	var right := global_basis.x
	var forward := -global_basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()
	var movement := (right * direction.x - forward * direction.y).limit_length()
	global_position += movement * movement_speed * maxf(delta, 0.0)
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
