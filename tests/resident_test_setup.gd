extends RefCounted
## Older subsystem scenarios deliberately exercise one resident in isolation.
static func isolate_first(scene: Node) -> void:
	for runtime in scene.resident_runtimes.slice(1):
		runtime.view.free()
		runtime.free()
	scene.resident_runtimes.resize(1)
