extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
const Need = preload("res://scripts/need_type.gd").Type
class ControlSpy extends RefCounted:
	signal residents_changed
	func get_residents() -> Array: return []
	signal home_changed(resident_id: String, previous: StringName, current: StringName)
	func get_home(_resident_id: String) -> RefCounted: return null
	func notify_home() -> void:
		home_changed.emit("", &"", &"")
		residents_changed.emit()
	var calls: Array = []
	func describe_assignment(_resident: String, _assignment: StringName) -> String: return "Проверка"
	func cancel_assignment(resident: String, assignment: StringName) -> bool:
		calls.append([resident, assignment])
		return true
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func add(scene: Node, actor: Node, id: StringName, type: StringName, target: StringName):
	var task := Assignment.new(id, actor.data.id, type, target)
	check(scene.player_control.add_assignment(actor.data.id, task), "Add through API")
	return task
func row(card: Node, id: StringName):
	for child in card.assignment_list.get_children():
		if child.get_meta("assignment_id", &"") == id: return child
	return null
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[1]
	var target = scene.resident_runtimes[3]
	var card = scene.get_node("HUD/ResidentCard")
	scene.resident_selection.select(actor.data)
	check(card.assignment_list.get_child(0).text == "Поручений нет", "Empty placeholder")
	var first = add(scene, actor, &"first", Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	var second = add(scene, actor, &"second", Assignment.EAT_AT_TARGET, scene.kitchen_data.id)
	var talk = add(scene, actor, &"talk", Assignment.TALK_TO, StringName(target.data.id))
	check(card.assignment_list.get_child_count() == 3 and row(card, first.id).get_child(0).text == "Поесть — Общая кухня", "Live append, duplicates, kitchen name")
	check(row(card, talk.id).get_child(0).text == "Поговорить с Марина", "Concrete target resident label")
	check(card.assignment_list.get_child(0).get_meta("assignment_id") == first.id and card.assignment_list.get_child(1).get_meta("assignment_id") == second.id, "Insertion order")
	check(row(card, first.id).get_child(1).text == "Ожидает", "Queued state")
	actor.assignments._change_state(talk, Assignment.State.ACTIVE)
	check(row(card, talk.id).get_child(1).text == "Выполняется", "Active event")
	actor.assignments._change_state(talk, Assignment.State.SUSPENDED)
	check(row(card, talk.id).get_child(1).text == "Приостановлено", "Suspended state")
	actor.assignments._change_state(talk, Assignment.State.QUEUED)
	var spy := ControlSpy.new()
	card.bind_control(spy)
	spy.notify_home() # Exercise the management notification contract of the UI test double.
	row(card, second.id).get_child(2).pressed.emit()
	check(spy.calls == [[actor.data.id, second.id]] and second.state == Assignment.State.QUEUED and actor.data.assignments.size() == 3, "Exact ID through API, UI never mutates data")
	card.bind_control(scene.player_control)
	row(card, second.id).get_child(2).pressed.emit()
	check(second.state == Assignment.State.CANCELLED and row(card, second.id) == null and row(card, first.id) != null, "Cancel removes only selected duplicate immediately")
	actor.assignments._complete_assignment(first, true)
	check(row(card, first.id) == null, "Completed row removed by signal")
	scene.resident_selection.select(target.data)
	check(card.assignment_list.get_child(0).text == "Поручений нет", "Selection isolates resident lists")
	scene.resident_selection.select(actor.data)
	check(row(card, talk.id) != null and card.assignment_list.get_child_count() == 1, "Switch back restores unfinished list")
	for i in range(20): add(scene, actor, StringName("many_%d" % i), Assignment.TALK_TO, StringName(target.data.id))
	await process_frame
	await process_frame
	check(root.get_visible_rect().encloses(card.get_global_rect()) and card.get_global_rect().encloses(card.close_button.get_global_rect()), "Many assignments keep panel/close inside viewport")
	check(card.get_node("Margin/Column/Scroll").get_v_scroll_bar().max_value > card.get_node("Margin/Column/Scroll").size.y, "Long list scrolls")
	scene.free()
	# Exercise real UI cancellation before/after consumption and conversation arrival.
	for type in [Assignment.EAT_AT_TARGET, Assignment.TALK_TO]:
		for active in [false, true]:
			for arrived in [false, true]:
				scene = Setup.make_scene(self)
				actor = scene.resident_runtimes[1]
				target = scene.resident_runtimes[3]
				card = scene.get_node("HUD/ResidentCard")
				scene.kitchen_data.resources.add(FOOD, 1)
				actor.data.hunger = 80 if type == Assignment.EAT_AT_TARGET else 0
				actor.data.get_need(Need.SOCIAL).value = 100 if type == Assignment.TALK_TO else 0
				target.data.get_need(Need.SOCIAL).value = 100
				var task = add(scene, actor, &"cancel", type, scene.kitchen_data.id if type == Assignment.EAT_AT_TARGET else StringName(target.data.id))
				scene.resident_selection.select(actor.data)
				if active: actor.assignments.start(task.id)
				elif type == Assignment.EAT_AT_TARGET: actor.needs.try_eat_at(task.target, 5000)
				else: actor.social.try_social_at(task.target, 8000)
				if arrived: actor.view._process(20)
				var intent = actor.intents.current_intent
				var decisions: int = actor.decision.decision_count
				# Avoid choosing the same autonomous action immediately after normal completion.
				actor.data.hunger = 0
				actor.data.get_need(Need.SOCIAL).value = 0
				row(card, task.id).get_child(2).pressed.emit()
				check(task.state == Assignment.State.CANCELLED and row(card, task.id) == null, "UI cancels correct instance")
				if not active:
					check(actor.intents.current_intent == intent, "Queued cancellation preserves independent similar action")
				else:
					check(actor.intents.current_intent != intent and actor.decision.decision_count > decisions and actor.commands.active_command == null, "Owned cancellation cleans execution and requests normal decision, no PlayerCommand")
				if type == Assignment.TALK_TO and active and arrived: check(scene.social_world.group_of(actor.data.id) == null, "Social membership cleanup")
				if type == Assignment.EAT_AT_TARGET:
					check(scene.kitchen_data.resources.get_amount(FOOD) == (0 if arrived else 1), "Consumed food never returned")
					check(scene.kitchen_data.resources.get_reserved_out(FOOD) == (0 if active or arrived else 1), "Owned reservation freed, independent reservation preserved")
				scene.free()
	print("Assignment UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
