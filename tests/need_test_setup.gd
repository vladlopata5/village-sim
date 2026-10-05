extends RefCounted
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
static func make_scene(tree: SceneTree, minute: int = 360, food: int = 2) -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.get_node("GameTime").total_minutes = minute
	tree.root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	scene.game_time.set_process(false)
	var runtime = scene.resident_runtimes[0]
	runtime.view.set_process(false)
	runtime.data.hunger = 0
	runtime.data.fatigue = 0
	scene.logistics.cancel_job(scene.logistics.current_job)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	runtime.intents.clear_reason(&"day_work")
	runtime.decision.work_available = Callable()
	if food > 0: scene.kitchen_data.resources.add(FOOD, food)
	runtime.intents.clear_reason(&"day_work")
	runtime.data.activity = preload("res://scripts/resident_activity.gd").Type.IDLE
	return scene
