extends RefCounted
const Types=preload("res://scripts/building_type.gd").Type
const Definition=preload("res://scripts/building_definition.gd")
static func create(tree: SceneTree) -> Node:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	tree.root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.decision_dispatcher.set_process(false)
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0;need.base_weight=0
	return world
static func building(world: Node, type: int, point: Vector3):
	var result: Dictionary=world.debug_spawn.spawn_building(point,Definition.for_type(type))
	assert(result.ok,"Production Debug spawn must validate the building")
	return result.objects[0]
static func click(tree: SceneTree, control: Control) -> void:
	click_at(tree,control.get_global_rect().get_center())
static func click_at(tree: SceneTree, point: Vector2, button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=point
	tree.root.push_input(motion,true)
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.pressed=down;event.button_index=button
		tree.root.push_input(event,true)
static func key(tree: SceneTree, code: Key) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code;event.pressed=down
		tree.root.push_input(event,true)
static func row_click(tree: SceneTree, window: Control, id: String) -> void:
	window.table.scroll_to_item(window.rows[id])
	await tree.process_frame
	await tree.process_frame
	var rect: Rect2=window.table.get_item_area_rect(window.rows[id],0)
	click_at(tree,window.table.global_position+rect.get_center())
static func walk(world: Node, actor: Node) -> void:
	for step in range(12000):
		world.game_time.total_minutes=420
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving(): break
