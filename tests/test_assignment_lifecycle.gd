extends SceneTree
## Shared lifecycle invariants at synchronous executor/log callbacks.
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	for type in [Assignment.EAT_AT_TARGET, Assignment.TALK_TO]:
		var scene = Setup.make_scene(self)
		var actor = scene.resident_runtimes[1]
		var target_id: StringName = scene.kitchen_data.id if type == Assignment.EAT_AT_TARGET else StringName(scene.resident_runtimes[3].data.id)
		scene.kitchen_data.resources.add(FOOD, 2)
		actor.data.hunger = 80 if type == Assignment.EAT_AT_TARGET else 0
		var task := Assignment.new(&"active", actor.data.id, type, target_id)
		check(scene.player_control.add_assignment(actor.data.id, task) and actor.assignments.start(task.id), "Both types use common activation")
		check(actor.assignments.active_assignment == task and actor.assignments._owned_intent != null, "Execution ownership acquired")
		var waiting := Assignment.new(&"waiting", actor.data.id, type, target_id)
		check(scene.player_control.add_assignment(actor.data.id, waiting), "Append duplicate while another execution is owned")
		var owned_intent = actor.assignments._owned_intent
		check(scene.player_control.cancel_assignment(actor.data.id, waiting.id), "Queued sibling can cancel independently")
		check(actor.assignments.active_assignment == task and actor.assignments._owned_intent == owned_intent and actor.intents.current_intent == owned_intent, "Cancelling queued sibling never detaches current execution")
		var callback_observed := [false]
		var verify_cleanup = func():
			callback_observed[0] = true
			check(task.state == Assignment.State.CANCELLED and actor.assignments.active_assignment == null and actor.assignments._owned_intent == null, "Cancel detaches before reentrant executor callback")
		if type == Assignment.EAT_AT_TARGET:
			scene.kitchen_data.resources.availability_changed.connect(func(_resource: int, _amount: int): verify_cleanup.call())
		else:
			actor.view._process(20)
			scene.social_world.membership_changed.connect(verify_cleanup)
		check(scene.player_control.cancel_assignment(actor.data.id, task.id), "Manual cancellation accepted for each executor")
		check(callback_observed[0], "Real executor cleanup emitted callback")
		check(not scene.player_control.cancel_assignment(actor.data.id, task.id), "Terminal task cannot cancel twice")
		check(actor.assignments.collect_actions().is_empty(), "Cancelled record excluded from candidates")
		scene.free()
	# The common waiting lookup preserves insertion order and invokes type-specific
	# matching only for eligible records; it does not complete any task itself.
	var lookup_scene = Setup.make_scene(self)
	var lookup_actor = lookup_scene.resident_runtimes[1]
	for type in [Assignment.EAT_AT_TARGET, Assignment.TALK_TO]:
		var target_id: StringName = lookup_scene.kitchen_data.id if type == Assignment.EAT_AT_TARGET else StringName(lookup_scene.resident_runtimes[3].data.id)
		var records: Array = []
		for id in ["done", "cancelled", "z_oldest", "a_newer"]:
			var task := Assignment.new(StringName("%s_%s" % [type, id]), lookup_actor.data.id, type, target_id)
			check(lookup_scene.player_control.add_assignment(lookup_actor.data.id, task), "Append matching result instance")
			records.append(task)
		records[0].state = Assignment.State.COMPLETED
		records[1].state = Assignment.State.CANCELLED
		records[2].state = Assignment.State.SUSPENDED
		var visited: Array = []
		var found = lookup_actor.assignments._first_waiting_match(type, func(task: Assignment):
			visited.append(task.id)
			return task.target == target_id)
		check(found == records[2] and visited == [records[2].id], "Oldest waiting match; no terminal or other-type predicate calls")
		check(records[2].state == Assignment.State.SUSPENDED and records[3].state == Assignment.State.QUEUED, "Lookup never changes state or closes duplicates")
		check(lookup_actor.assignments._first_waiting_match(type, func(_task: Assignment): return false) == null, "No eligible result means no completion")
	lookup_scene.free()
	print("Assignment lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
