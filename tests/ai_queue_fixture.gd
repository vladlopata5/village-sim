extends RefCounted
## Explicit service boundaries for tests using a manually advanced GameTime.
class SingleSlice extends "res://scripts/ai_decision_dispatcher.gd":
	var ticks := 0
	func _now_usec() -> int:
		ticks += 1000
		return ticks
static func one_per_slice(world: Node) -> Node:
	var previous: Node = world.decision_dispatcher
	var queue := SingleSlice.new()
	queue.budget_usec = 1000
	queue.clock = world.game_time
	queue.set_process(false)
	world.add_child(queue)
	queue.set_process(false)
	world.decision_dispatcher = queue
	for actor in world.resident_runtimes:
		if is_instance_valid(actor): actor.decision.bind_dispatcher(queue)
	previous.free()
	return queue
static func drain(world: Node) -> void:
	for frame in 512:
		await world.get_tree().process_frame
		world.decision_dispatcher._process(0)
		if world.decision_dispatcher.pending_count() == 0: return
	assert(false, "Finite test queue must drain with frozen clock and explicit service")
