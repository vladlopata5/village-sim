extends "res://tests/test_event_catalog_content.gd"
const ID := "social.become_acquaintances"
const Renderer = preload("res://scripts/event_text_renderer.gd")

class LateRejectingJournal extends "res://scripts/memory_store.gd":
	var validations := 0
	func prepare_add(record: Dictionary) -> Dictionary:
		validations += 1
		return super.prepare_add(record) if validations == 1 else {}

func acquaintances(isolated: bool = true) -> Dictionary:
	var a := Data.new("a", "Анна", 25)
	a.grammatical_gender = Traits.GrammaticalGender.FEMININE
	var f := fixture([a, Data.new("b", "Степан", 25)])
	if isolated: only(f, ID)
	f.a.set_opinion("b", 19)
	f.b.set_opinion("a", 19)
	f.social.rng.rolls = [100, 100]
	return f

func prior(f: Dictionary, reverse: bool = false, overrides: Dictionary = {}) -> void:
	var owner: RefCounted = f.b if reverse else f.a
	var partner: RefCounted = f.a if reverse else f.b
	owner.memories.advance(f.clock.total_minutes)
	var record := {"id": "prior", "type": "pleasant_interaction", "topic": "social", "text": "Прежняя встреча", "tags": ["positive"], "target": {"kind": "resident", "id": partner.id}, "strength": 10, "created_minute": f.clock.total_minutes, "source_occurrence_id": "fixture/previous", "provenance": {"kind": "experienced"}}
	record.merge(overrides, true)
	check(owner.memories.add(record), "Seed prior memory")

func transition(f: Dictionary, level: int, minute: int) -> bool:
	var links: RefCounted = f.control.social_links
	return links.commit_transition(links.prepare_transition(f.a, f.b, level, minute, true), minute)

func add_links(f: Dictionary, person: RefCounted, count: int) -> void:
	var links: RefCounted = f.control.social_links
	for index in count:
		var neighbor := Data.new("%s-neighbor-%d" % [person.id, index], "Сосед", 25)
		f.control.register_resident(neighbor)
		check(links.commit_transition(links.prepare_transition(person, neighbor, index % 3 + 1, 0, true), 0), "Seed nested link tier")

func _run() -> void:
	eligibility()
	competition_and_gate()
	outcomes_and_text()
	atomicity()
	statistics()
	print("Become acquaintances: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func eligibility() -> void:
	for interaction in SocialResult.Context.values():
		for mask in [1, 2, 3]:
			var f := acquaintances()
			if mask & 1: prior(f)
			if mask & 2: prior(f, true)
			check(fire(f, interaction).status == "completed", "Prior memory on either side at the same minute, all contexts")
			check(f.a.get_opinion("b") == 20 and f.b.get_opinion("a") == 20, "Exact boundary after the ordinary reactions; event adds no opinion")
			cleanup(f)
	for scenario in ["no memory", "tag", "target", "zero", "future", "same occurrence", "actor opinion", "other opinion", "actor reaction", "other reaction", "positive link", "negative link"]:
		var f := acquaintances()
		var changes := {}
		match scenario:
			"tag": changes.tags = ["social"]
			"target": changes.target = {"kind": "resident", "id": "a"}
			"zero": changes.strength = 0
			"future": changes.created_minute = 636
			"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
			"actor opinion": f.a.set_opinion("b", 18)
			"other opinion": f.b.set_opinion("a", 18)
			"actor reaction": f.social.rng.rolls = [50, 100]
			"other reaction": f.social.rng.rolls = [100, 0]
			"positive link", "negative link":
				f.a.set_opinion("b", 20)
				f.b.set_opinion("a", 20)
				f.clock.total_minutes = 10080
				check(transition(f, 1 if scenario == "positive link" else -1, 0), "Seed nonzero level with expired cooldown and sufficient opinions")
		if scenario != "no memory": prior(f, false, changes)
		var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
		check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Rejected condition: " + scenario)
		cleanup(f)
	for side in [0, 1]:
		for count in [4, 5]:
			var f := acquaintances()
			prior(f)
			add_links(f, f.a if side == 0 else f.b, count)
			check(fire(f).status == ("completed" if count == 4 else "no_match"), "Nested limit for each participant includes +2 and +3")
			cleanup(f)
	for minute in [10079, 10080]:
		var f := acquaintances()
		check(transition(f, -1, 0) and transition(f, 0, 0), "Seed locked zero-level pair")
		f.clock.total_minutes = minute
		prior(f)
		var result: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.MEAL)
		check(f.service.replay(result.confirmed_context().occurrence_id).status == ("completed" if minute == 10080 else "no_match"), "Exact shared cooldown boundary in reverse order")
		cleanup(f)

func competition_and_gate() -> void:
	for roll in [0.0, 0.5, 1.0]:
		var f := acquaintances(false)
		prior(f)
		f.rng.value = roll
		var result := fire(f)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [ID, "social.warm_sympathy"] and result.definition_id == (ID if roll < 0.5 else "social.warm_sympathy"), "Two equal-weight tickets in the full production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == int(roll < 0.5), "Losing weighted selection leaves link unchanged")
		cleanup(f)
	for roll in [0.299999, 0.3]:
		var f := acquaintances()
		prior(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = roll
		check(fire(f).status == ("completed" if roll < 0.3 else "chance_failed"), "Existing 30-percent gate")
		cleanup(f)

func outcomes_and_text() -> void:
	for bits in 16:
		var f := acquaintances()
		prior(f)
		var messages: Array = []
		f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
		for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
		var result := fire(f)
		var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
		check(result.status == "completed" and link.link_level == 1 and link.normal_transition_available_at == 10715 and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes")
		check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent chat owners and exact probability boundary")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var entries: Array = person.memories.find({"type": "relationship_progress"})
			check(entries.size() == int(bool(bits & (4 << side))), "Independent diary owners")
			if not entries.is_empty():
				var entry: Dictionary = entries[0]
				check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == 25 and entry.topic == "social" and entry.tags == ["social", "positive", "relationship"] and entry.provenance.kind == "experienced" and not entry.permanent, "Structured diary entry")
			check(person.memories.size() == entries.size() + int(side == 0) and person.moodlets.size() == 0, "One journal write at most and no moodlets")
		cleanup(f)
	for variant in 5:
		var f := acquaintances()
		prior(f)
		var definition := definition_for(f, ID)
		var indices := [variant, (variant + 1) % 5, (variant + 2) % 5, (variant + 3) % 5, (variant + 4) % 5]
		var draws: Array = [0, 0, 0, 0]
		for index in indices: draws.append((index + 0.1) / 5.0)
		f.service.executor.rng.values = draws
		var messages: Array = []
		f.service.resident_message.connect(func(_id, _name, line): messages.append(line))
		check(fire(f).status == "completed" and f.service.executor.rng.draws == 9, "Four independent chances and five text selections")
		check(messages == [definition.params.chat[indices[0]], definition.params.chat[indices[1]]], "All five independent chat texts")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var entry: Dictionary = person.memories.find({"type": "relationship_progress"})[0]
			var text_index: int = indices[2 + side]
			check(entry.text == Renderer.render(definition.params.diary[text_index], {"speaker": person.event_text_projection(), "partner": partner.event_text_projection()}).text, "All diary variants for both genders")
			if text_index == 2:
				var expected := "Похоже, у нас со Степаном нашлось больше общего, чем я сначала предполагала." if side == 0 else "Похоже, у нас с Анной нашлось больше общего, чем я сначала предполагал."
				check(entry.text == expected, "Correct speaker gender and instrumental")
			if text_index == 4:
				check(entry.text.contains("появился новый приятель" if side == 0 else "появилась новая приятельница"), "Partner gender agreement")
		var expected_history: String = definition.text.chronicle[indices[4]].replace("{actor.name}", "Анна").replace("{other.name}", "Степан")
		check(f.service.chronicle.entries()[0].text == expected_history, "All five chronicle texts")
		cleanup(f)

func atomicity() -> void:
	for failure in ["recipient", "required recipient", "replacement", "version", "opinion", "memory", "capacity", "clock", "journal"]:
		var f := acquaintances()
		f.clock.total_minutes = 10635
		prior(f)
		if failure == "journal": f.b.memories = LateRejectingJournal.new("b")
		if failure == "required recipient": f.service.executor.rng.values = [0.5, 0.5, 0.5, 0.5]
		var notices: Array = []
		f.service.chronicle.changed.connect(func(id): notices.append(id))
		f.service.resident_message.connect(func(_id, _name, line): notices.append(line))
		f.service.executor.rng.on_draw = func(draw):
			# The fifth draw selects the chronicle after participant text has been read.
			if draw != (5 if failure == "required recipient" else 4): return
			match failure:
				"recipient", "required recipient": f.control.unregister_resident("b")
				"replacement": f.control.setup([Data.new("b", "Другой", 25)], [])
				"version": check(transition(f, -1, 0) and transition(f, 0, 0), "Inject version change with same level and expired cooldown")
				"opinion": f.b.set_opinion("a", 19)
				"memory": f.a.memories.remove("prior")
				"capacity": add_links(f, f.b, 5)
				"clock": f.clock.total_minutes += 1
		var refused := fire(f)
		var expected_status := "text_failed" if failure == "recipient" else "prepare_failed"
		check(refused.status == expected_status and f.service.executor.rng.draws >= 4 and f.service.completed_events().is_empty(), "Selected transaction rejects stale input: " + failure + " " + str(refused))
		check(f.control.social_links.get_level(f.a, f.b) == 0 and f.service.chronicle.size() == 0 and notices.is_empty(), "No partial link or presentation: " + failure)
		check(f.a.memories.find({"type": "relationship_progress"}).is_empty() and f.b.memories.find({"type": "relationship_progress"}).is_empty(), "No partial diary: " + failure)
		if failure == "journal": check(f.b.memories.validations == 2, "Late refusal happens after both diaries have prepared")
		cleanup(f)
	var stale_selection := acquaintances()
	stale_selection.clock.total_minutes = 10635
	prior(stale_selection)
	stale_selection.rng.on_draw = func(draw):
		if draw == 2:
			check(transition(stale_selection, -1, 0) and transition(stale_selection, 0, 0), "Pair changes and returns to zero during selection")
	check(fire(stale_selection).status == "prepare_failed" and stale_selection.service.executor.rng.draws == 0 and stale_selection.service.chronicle.size() == 0, "Selection snapshot revision is required before any effect roll")
	stale_selection.rng.on_draw = Callable()
	cleanup(stale_selection)
	var nested := acquaintances()
	prior(nested)
	var observed: Array = []
	nested.a.memories.changed.connect(func(_id):
		var token: String = nested.service.last_occurrence().occurrence_id
		var link: Dictionary = nested.control.social_links.get_link(nested.a, nested.b)
		observed.append([link.link_level, link.normal_transition_available_at, nested.b.memories.size(), nested.service.chronicle.size(), nested.service.replay(token).status])
		nested.service.executor.publish(token)
		nested.social.resolve(nested.b, nested.a, SocialResult.Context.CONVERSATION))
	var result := fire(nested)
	check(result.status == "completed" and nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match" and observed == [[1, 10715, 1, 1, "completed"]], "Nested callback sees fully committed state and queued occurrence is rejected")
	var committed: Dictionary = nested.service.completed_events()
	var occurrence: String = committed.keys()[0]
	var draws: int = nested.service.executor.rng.draws
	nested.service.executor.execute({}, {"occurrence_id": occurrence}, 645, nested.a)
	nested.service.executor.publish(occurrence)
	check(nested.service.replay(occurrence).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 10715, "Replay does not extend cooldown or consume RNG")
	cleanup(nested)

func statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6112026
	var counts := {"chance_failed": 0, ID: 0, "social.warm_sympathy": 0}
	for index in 600:
		var f := acquaintances(false)
		prior(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[ID] + counts["social.warm_sympathy"] == 600 and absf(counts[ID] / 600.0 - 0.15) < 0.06, "Seeded end-to-end gate plus competition")
	print("Acquaintance sample seed=6112026 N=600 ", JSON.stringify(counts))
