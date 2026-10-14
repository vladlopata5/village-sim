extends RefCounted
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
static func make(tree: SceneTree) -> Node:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	tree.root.add_child(world)
	world.game_time.set_process(false)
	world.social_events.enabled=false
	world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	return world
static func click(tree: SceneTree, point: Vector2, button: int=MOUSE_BUTTON_LEFT) -> void:
	var motion=InputEventMouseMotion.new()
	motion.position=point
	tree.root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.button_index=button
		event.pressed=pressed
		tree.root.push_input(event,true)
static func screen(world: Node, point: Vector2) -> Vector2:
	return world.get_node("World/Camera3D").unproject_position(Coordinates.to_world(point))
