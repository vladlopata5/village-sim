extends RefCounted
## Older subsystem scenarios deliberately exercise one resident in isolation.
static func isolate_first(scene: Node) -> void:
	for runtime in scene.resident_runtimes.slice(1):
		runtime.view.free()
		runtime.free()
	scene.resident_runtimes.resize(1)
	scene.resident_runtimes[0].wander.target_provider = Callable()

static func unbind_work(scene: Node) -> void:
	# Isolated schedule/need tests inject a simple work action instead of real hauling.
	scene.logistics.unbind_execution()
	for runtime in scene.resident_runtimes:
		for trait_type in runtime.data.traits.duplicate(): runtime.data.remove_trait(trait_type)
		runtime.decision.work_request = Callable()
		runtime.decision.work_available = Callable()
		runtime.schedule.work_decision = Callable()
