extends SceneTree
const Dispatcher = preload("res://scripts/ai_decision_dispatcher.gd")
var checks := 0
var failures := 0
class Receiver extends Node:
	var calls: Array = []
	var callback: Callable
	func execute_queued_decision(reason: String, context: Dictionary) -> bool:
		calls.append([reason, context])
		if callback.is_valid(): callback.call()
		return true
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var queue = Dispatcher.new()
	root.add_child(queue)
	queue.set_process(false)
	var actors: Array = []
	var order: Array = []
	for index in 35:
		var actor := Receiver.new()
		root.add_child(actor)
		actor.callback = func(): order.append(index)
		actors.append(actor)
	queue._process(0)
	check(queue.pending_count() == 0, "Empty queue")
	await process_frame
	for index in 30: check(queue.request(str(index), actors[index], "work", {"value": index}), "Enqueue")
	for repeat in 100:
		for index in 30: queue.request(str(index), actors[index], "repeat")
	check(queue.pending_count() == 30 and queue.duplicates == 3000, "Dedup retains one request per resident")
	queue.cancel("9", actors[8])
	check(queue.pending_count() == 30, "Different identity cannot cancel pending")
	queue.cancel("9", actors[9])
	check(queue.pending_count() == 29, "Cancellation")
	for frame in 29:
		await process_frame
		var before: int = queue.executed
		queue._process(0)
		queue._process(0)
		check(queue.executed == before + 1, "At most one per actual frame")
	check(order == range(9) + range(10,30), "FIFO and no starvation from dedup")
	check(actors[0].calls[0][1].value == 0, "Original context retained")
	queue.request("old", actors[30], "old")
	actors[30].free()
	await process_frame
	queue._process(0)
	check(queue.discarded == 1, "Freed receiver discarded without strong reference")
	queue.request("reuse", actors[31], "old identity")
	queue.request("reuse", actors[32], "new identity")
	await process_frame
	queue._process(0)
	check(actors[31].calls.is_empty() and actors[32].calls.size() == 1, "Same ID replacement")
	queue.request("pause", actors[31], "paused")
	paused = true
	await process_frame
	queue._process(0)
	check(actors[31].calls.is_empty() and queue.pending_count() == 1, "Pause preserves requests")
	paused = false
	await process_frame
	queue._process(0)
	check(actors[31].calls.size() == 1, "Resume drains")
	actors[33].callback = func():
		queue.request("reentrant", actors[33], "duplicate")
		queue.request("later", actors[34], "next")
		queue._process(0)
	queue.request("reentrant", actors[33], "first")
	await process_frame
	queue._process(0)
	check(actors[33].calls.size() == 1 and actors[34].calls.is_empty(), "No reentrant drain or same receiver echo")
	await process_frame
	queue._process(0)
	check(actors[34].calls.size() == 1, "New request during drain runs next frame")
	queue.decisions_per_frame = 3
	for index in 8: queue.request(str(index), actors[index], "budget")
	await process_frame
	var before: int = queue.executed
	queue._process(0)
	queue._process(0)
	check(queue.executed == before + 3 and queue.pending_count() == 5, "Configured budget and one drain per frame")
	queue.clear()
	check(queue.pending_count() == 0, "Teardown clear")
	for actor in actors:
		if is_instance_valid(actor): actor.free()
	queue.free()
	print("AI dispatcher: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
