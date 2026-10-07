extends Node2D
## Temporary picture of separate GroundResource data.
const Drop = preload("res://scripts/ground_resource.gd")
var ground_resource: Drop

func setup(drop: Drop) -> void:
	ground_resource = drop
	global_position = drop.world_position
	var caption := Label.new()
	caption.text = preload("res://scripts/resource_type.gd").display_name(drop.resource_type)
	caption.position = Vector2(-16, -32)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-8, -8, 16, 16), Color("d5ad61"))

func interaction_hit(screen_position: Vector2) -> bool:
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_position
	return Rect2(-10, -10, 20, 20).has_point(point)
