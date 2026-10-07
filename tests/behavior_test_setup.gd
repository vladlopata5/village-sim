extends RefCounted
## Controlled clock/needs: scenario tests choose the values being compared.
static func make_scene(tree: SceneTree) -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(scene)
	scene.game_time.set_process(false)
	scene.game_logger.console_enabled = false
	scene.logistics.unbind_execution()
	for job in scene.logistics.jobs.duplicate(): scene.logistics.cancel_job(job)
	for runtime in scene.resident_runtimes:
		for trait_type in runtime.data.traits.duplicate(): runtime.data.remove_trait(trait_type)
		runtime.view.set_process(false)
		runtime.wander.target_provider = Callable()
		scene.game_time.minute_changed.disconnect(runtime.need_dynamics._on_minute_changed)
		for need in runtime.data.needs.values(): need.value = 0
		runtime.decision.work_available = func(): return false
		runtime.decision.work_request = Callable()
		runtime.schedule.work_decision = Callable()
		runtime.data.work_location_id = &""
	return scene
