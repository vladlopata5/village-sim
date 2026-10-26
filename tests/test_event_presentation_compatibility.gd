extends SceneTree
## Golden output captured on 03b590b before the presentation implementation changed.
const Service = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Need = preload("res://scripts/need_type.gd")
const GOLDEN = "res://tests/fixtures/event_presentation_golden.json"
class TracedRng extends RefCounted:
	var source := RandomNumberGenerator.new()
	var calls: Array = []
	var fixed_floats: Array = []
	var cursor := 0
	func randf() -> float:
		var value: float = source.randf() if fixed_floats.is_empty() else fixed_floats[cursor % fixed_floats.size()]
		cursor += 1
		calls.append(["float", String.num(value, 17)])
		return value
	func randi_range(low: int, high: int) -> int:
		var value := source.randi_range(low, high)
		calls.append(["integer", low, high, value])
		return value
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var snapshot := capture()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			var capture_file := FileAccess.open(arg.trim_prefix("--capture="), FileAccess.WRITE)
			capture_file.store_string(JSON.stringify(snapshot, "  "))
			print("Captured unchanged social system; matching cases=648, stories=24")
			quit(0)
			return
	var file := FileAccess.open(GOLDEN, FileAccess.READ)
	check(file != null, "Pre-change golden fixture exists")
	if file == null:
		quit(1)
		return
	var expected: Dictionary = JSON.parse_string(file.get_as_text())
	check(expected.source_head == "03b590b5c04bb55950fb7d755825a7ab8d758a0a", "Golden provenance")
	for key in expected.snapshot:
		check(snapshot[key] == expected.snapshot[key], "Exact pre-change presentation/RNG trace: " + key)
	print("Event presentation compatibility: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func capture() -> Dictionary:
	var service := Service.new()
	root.add_child(service)
	var matrix: Array = []
	var tag_pairs := [[[], []], [["EATING", "VISITOR"], ["WORKING", "WORKER"]], [["WORKING", "WORKER"], ["EATING", "VISITOR"]], [["WORKING", "WORKER"], ["WORKING", "WORKER"]], [["WORKER"], ["VISITOR"]], [["TALKING"], ["TALKING"]]]
	for context in Event.Context.values():
		for first in Event.Reaction.values():
			for second in Event.Reaction.values():
				for traits in [[], [Trait.Type.FOOLISH], [Trait.Type.LAZY], [Trait.Type.FOOLISH, Trait.Type.LAZY]]:
					for tags in tag_pairs:
						var people := pair()
						for value in traits: people[1].add_trait(value)
						var event := Event.new()
						event.context = context
						event.reaction_1 = first
						event.reaction_2 = second
						var rows: Array = []
						for row in service.matching_entries(event, people[0], people[1], tags[0], tags[1]): rows.append([row.entry.id, row.orientations])
						matrix.append(rows)
	var stories: Array = []
	for entry in service.entries:
		for reverse in [false, true]: stories.append(story(entry, reverse, [0.199999, 0.2]))
	var edges: Array = []
	var both := Entry.new({"id": "both", "feed_text_a": "%A% -> %B%", "feed_text_b": "%B% -> %A%", "diary_text_a": "first %A%", "diary_text_b": "second %B%", "diary_importance": 1})
	for rolls in [[0.0, 0.0], [0.199999, 0.2], [0.2, 0.199999], [0.2, 0.2], [1.0, 1.0]]: edges.append(story(both, false, rolls))
	for texts in [["", ""], [" ", "\t"], ["", "%B% only"]]:
		both.feed_text_a = texts[0]
		both.feed_text_b = texts[1]
		edges.append(story(both, false, [0.0, 0.0]))
	both.diary_importance = 0
	edges.append(story(both, false, [0.0, 0.0]))
	both.diary_importance = 1
	both.diary_text_a = ""
	both.diary_text_b = ""
	edges.append(story(both, false, [0.0, 0.0]))
	service.free()
	var seeded: Array = []
	for seed_value in [0, 1, 7, 91, 12345]: seeded.append(seeded_trace(seed_value))
	var runtime := runtime_trace()
	return {"matching_sha256": JSON.stringify(matrix).sha256_text(), "matching_cases": matrix.size(), "stories": stories, "diary_edges": edges, "seeded_sha256": JSON.stringify(seeded).sha256_text(), "seeded_events": 150, "runtime_sha256": JSON.stringify(runtime).sha256_text(), "conversation_events": runtime.conversation_events, "conversation_chance_checks": runtime.conversation_chance_checks}

func pair() -> Array:
	return [Data.new("a", "Анна", 25), Data.new("b", "Борис", 30)]

func story(entry: RefCounted, reverse: bool, rolls: Array) -> String:
	var people := pair()
	for value in entry.conditions.get("required_traits_a", []): people[0].add_trait(value)
	for value in entry.conditions.get("required_traits_b", []): people[1].add_trait(value)
	people[0].set_opinion("b", 12)
	people[1].set_opinion("a", -17)
	var event := Event.new()
	var contexts: Array = entry.conditions.get("allowed_contexts", ["CONVERSATION"])
	event.context = Event.Context.keys().find(contexts[0]) as Event.Context
	var first := Event.Reaction.keys().find(entry.conditions.get("reaction_a", "NEUTRAL")) as Event.Reaction
	var second := Event.Reaction.keys().find(entry.conditions.get("reaction_b", "POSITIVE" if first != Event.Reaction.POSITIVE else "NEGATIVE")) as Event.Reaction
	event.reaction_1 = second if reverse else first
	event.reaction_2 = first if reverse else second
	var tags_a: Array = entry.conditions.get("participant_state_tags_a", ["TALKING"])
	var tags_b: Array = entry.conditions.get("participant_state_tags_b", ["TALKING"])
	var service := Service.new()
	root.add_child(service)
	service.entries = [entry]
	var random := TracedRng.new()
	random.source.seed = 0
	random.fixed_floats = rolls
	service.narrative_rng = random
	var feed: Array = []
	service.feed_message.connect(func(text): feed.append(text))
	var output: Dictionary = service.present(event, people[1] if reverse else people[0], people[0] if reverse else people[1], tags_b if reverse else tags_a, tags_a if reverse else tags_b)
	var result := JSON.stringify({"id": entry.id, "reverse_requested": reverse, "reversed": event.reversed_orientation, "selected": event.selected_entry_id, "feed": feed, "diary_a": diary(people[0]), "diary_b": diary(people[1]), "output": output, "calls": random.calls, "opinions": [people[0].get_opinion("b"), people[1].get_opinion("a")]})
	service.free()
	return result

func diary(person: RefCounted) -> Array:
	var output: Array = []
	for item in person.diary_entries: output.append([item.text, item.importance, item.created_minute])
	return output

func event_fields(event: RefCounted) -> Variant:
	if event == null: return null
	var row: Array = []
	for field in ["context", "resident_1_id", "resident_2_id", "attitude_1_to_2", "attitude_2_to_1", "roll_1", "roll_2", "reaction_1", "reaction_2", "opinion_delta_1", "opinion_delta_2", "selected_entry_id", "reversed_orientation"]: row.append(event.get(field))
	return row

func seeded_trace(seed_value: int) -> Dictionary:
	var service := Service.new()
	root.add_child(service)
	var mechanical := TracedRng.new()
	var narrative := TracedRng.new()
	mechanical.source.seed = seed_value
	narrative.source.seed = seed_value ^ 0x534F4349
	service.rng = mechanical
	service.narrative_rng = narrative
	var people := pair()
	people[1].add_trait(Trait.Type.FOOLISH)
	people[1].add_trait(Trait.Type.LAZY)
	people[0].add_liked_trait(Trait.Type.FOOLISH)
	people[0].set_opinion("b", 49)
	people[1].set_opinion("a", -50)
	var feed: Array = []
	service.feed_message.connect(func(text): feed.append(text))
	var events: Array = []
	for i in 30:
		events.append(event_fields(service.resolve(people[0], people[1], (i % 3) as Event.Context, ["EATING", "WORKER", "TALKING"], ["WORKING", "WORKER", "VISITOR"])))
	var result := {"seed": seed_value, "events": events, "feed": feed, "diary_a": diary(people[0]), "diary_b": diary(people[1]), "opinions": [people[0].get_opinion("b"), people[1].get_opinion("a")], "mechanical_calls": mechanical.calls, "narrative_calls": narrative.calls, "mechanical_state": str(mechanical.source.state), "narrative_state": str(narrative.source.state)}
	service.free()
	return result

func runtime_trace() -> Dictionary:
	var scene := Setup.make_scene(self)
	var service: Node = scene.social_events
	service.enabled = true
	scene.game_time.total_minutes = 635
	var mechanical := TracedRng.new()
	var narrative := TracedRng.new()
	mechanical.source.seed = 17
	mechanical.fixed_floats = [0.0]
	narrative.source.seed = 45
	service.rng = mechanical
	service.narrative_rng = narrative
	var events: Array = []
	var feed: Array = []
	service.event_resolved.connect(func(event): events.append(event_fields(event)))
	service.feed_message.connect(func(text): feed.append(text))
	var actor: Node = scene.resident_runtimes[1]
	var target: Node = scene.resident_runtimes[3]
	actor.data.get_need(Need.Type.SOCIAL).value = 100
	target.data.get_need(Need.Type.SOCIAL).value = 100
	var started: bool = actor.social.try_social_at(StringName(target.data.id), 8000)
	actor.view._process(100)
	var initial_events := events.size()
	var initial_chances := mechanical.cursor
	for person in scene.resident_runtimes:
		person.data.activity = Activity.Type.WORKING
		person.decision._work_cycle_active = true
		person.decision._work_assignment = {"location_id": scene.kitchen_data.id}
	for i in 20: service.trigger(actor, Event.Context.MEAL if i % 2 == 0 else Event.Context.WORK, scene.kitchen_data.id)
	var people: Array = []
	for person in scene.resident_runtimes: people.append([person.data.id, diary(person.data)])
	var result := {"started": started, "conversation_events": initial_events, "conversation_chance_checks": initial_chances, "events": events, "feed": feed, "people": people, "mechanical_calls": mechanical.calls, "narrative_calls": narrative.calls}
	scene.free()
	return result
