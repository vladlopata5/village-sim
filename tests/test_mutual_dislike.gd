extends "res://tests/test_friendship_decline.gd"

const DISLIKE := "social.mutual_dislike"
const DRIFT_APART := "social.acquaintances_drift_apart"

func dislike(isolated: bool = true) -> Dictionary:
	var f := acquaintances(false)
	if isolated: only(f, DISLIKE)
	f.a.set_opinion("b", -19)
	f.b.set_opinion("a", -19)
	f.social.rng.rolls = [0, 0]
	return f

func dislike_memory(f: Dictionary, reverse: bool = false, overrides: Dictionary = {}) -> void:
	var record := {"strength": 1}
	record.merge(overrides, true)
	grievance(f, reverse, record)

func _run() -> void:
	dislike_eligibility()
	dislike_limits()
	dislike_cooldown()
	dislike_competition()
	dislike_outcomes()
	dislike_texts()
	dislike_atomicity()
	dislike_statistics()
	print("Mutual dislike: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func dislike_eligibility() -> void:
	for context in SocialResult.Context.values():
		for mask in [1, 2, 3]:
			var f := dislike()
			if mask & 1: dislike_memory(f)
			if mask & 2: dislike_memory(f, true)
			check(fire(f, context).status == "completed" and f.control.social_links.get_level(f.a, f.b) == -1, "Either or both prior memories qualify in every context, including the same minute")
			check(f.a.get_opinion("b") == -20 and f.b.get_opinion("a") == -20, "Both post-reaction opinions exactly on the boundary")
			cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "zero", "tag", "target", "future", "same occurrence", "opinion", "neutral", "positive"]:
			var f := dislike()
			var changes := {}
			var person: RefCounted = f.b if side else f.a
			var partner_id: String = f.a.id if side else f.b.id
			match scenario:
				"zero": changes.strength = 0
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": person.id}
				"future": changes.created_minute = f.clock.total_minutes + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"opinion": person.set_opinion(partner_id, -18)
				"neutral": f.social.rng.rolls[int(side)] = 50
				"positive": f.social.rng.rolls[int(side)] = 100
			if scenario != "missing": dislike_memory(f, side, changes)
			if scenario in ["opinion", "neutral", "positive"]: dislike_memory(f, not side)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Reject an unmet condition on either side: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -2, -1, 1, 2, 3]:
		var f := dislike()
		f.clock.total_minutes = COOLDOWN
		f.a.set_opinion("b", -20)
		f.b.set_opinion("a", -20)
		check(transition(f, level, 0), "Seed another level with an expired cooldown")
		dislike_memory(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Only level zero qualifies, not " + str(level))
		cleanup(f)

	var outside := dislike()
	outside.clock.total_minutes = COOLDOWN
	check(transition(outside, -2, 0) and outside.a.set_opinion("b", -60) and transition(outside, 0, 0), "Seed an existing opinion below the new link's range")
	dislike_memory(outside)
	check(fire(outside).status == "completed" and outside.a.get_opinion("b") == -60 and outside.b.get_opinion("a") == -20, "Commit preserves actual opinions, including an existing out-of-range value")
	check(not outside.a.set_opinion("b", -61) and outside.a.set_opinion("b", -59), "Subsequent opinion changes follow the existing new-tier bounds")
	cleanup(outside)

func dislike_limits() -> void:
	for side in [0, 1]:
		for count in [4, 5]:
			var f := dislike()
			dislike_memory(f)
			var person: RefCounted = f.a if side == 0 else f.b
			var levels := [-1, -2, -3, -3]
			if count == 5: levels.append(-2)
			add_tier_links(f, person, levels)
			check(f.control.social_links.counts_for(person).negative_1 == count, "Nested limit counts -1, -2 and -3")
			check(fire(f).status == ("completed" if count == 4 else "no_match"), "Four existing links allow one new link, five block it on either side")
			check(f.control.social_links.counts_for(person).negative_1 == 5, "No participant exceeds the limit of five")
			cleanup(f)

func dislike_cooldown() -> void:
	for elapsed in [COOLDOWN - 1, COOLDOWN]:
		var f := dislike(false)
		check(transition(f, 1, 0), "Seed acquaintances before drift")
		f.clock.total_minutes = COOLDOWN
		dislike_memory(f)
		only(f, DRIFT_APART)
		check(fire(f).definition_id == DRIFT_APART, "An actual previous event returns the pair to level zero")
		var zero: Dictionary = f.control.social_links.get_link(f.b, f.a)
		check(zero.link_level == 0 and zero.normal_transition_available_at == 2 * COOLDOWN, "Zero stores the deadline from the prior transition")
		f.service._load_catalogs()
		only(f, DISLIKE)
		f.a.set_opinion("b", -19)
		f.b.set_opinion("a", -19)
		f.clock.total_minutes = COOLDOWN + elapsed
		dislike_memory(f, true, {"id": "late-memory"})
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.MEAL)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		var current: Dictionary = f.control.social_links.get_link(f.a, f.b)
		if elapsed == COOLDOWN:
			check(result.status == "completed" and current.link_level == -1 and current.normal_transition_available_at == 3 * COOLDOWN, "At minute 10080 reverse orientation can transition and starts a new cooldown")
		else:
			check(result.status == "no_match" and current == zero, "At minute 10079 the existing level-zero cooldown still blocks")
		cleanup(f)

	var independent := dislike(false)
	dislike_memory(independent, false, {"created_minute": independent.clock.total_minutes - 1})
	check(fire(independent, SocialResult.Context.WORK).definition_id == DISLIKE, "First pair enters dislike")
	var c := Data.new("c", "Мария", 25)
	var d := Data.new("d", "Денис", 25)
	independent.control.register_resident(c)
	independent.control.register_resident(d)
	c.set_opinion("d", 19)
	d.set_opinion("c", 19)
	var other_pair := {"a": c, "b": d, "clock": independent.clock}
	prior(other_pair)
	independent.social.rng.rolls = [100, 100]
	var positive: RefCounted = independent.social.resolve(c, d, SocialResult.Context.WORK)
	check(independent.service.replay(positive.confirmed_context().occurrence_id).definition_id == ID, "Another pair can enter +1 during the negative pair's cooldown")
	check(independent.control.social_links.get_level(c, d) == 1 and independent.control.social_links.get_level(independent.a, independent.b) == -1, "Pairs have independent levels and cooldowns")
	cleanup(independent)

func dislike_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := dislike(false)
		dislike_memory(f, false, {"created_minute": f.clock.total_minutes - 1})
		f.rng.value = draw
		var result := fire(f, SocialResult.Context.WORK)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [DISLIKE, GRUDGE] and result.definition_id == (DISLIKE if draw < 0.5 else GRUDGE), "Equal tickets for both qualified production definitions")
		check(f.control.social_links.get_level(f.a, f.b) == (-1 if draw < 0.5 else 0), "Only the chosen event affects the link")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := dislike()
		dislike_memory(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact shared gate boundary")
		cleanup(f)

func dislike_outcomes() -> void:
	for bits in 16:
		var f := dislike()
		dislike_memory(f)
		var prior_record: Array = f.a.memories.find()
		var messages: Array = []
		f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
		for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
		var result := fire(f)
		var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
		check(result.status == "completed" and link.link_level == -1 and link.normal_transition_available_at == f.clock.total_minutes + COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects are present for all sixteen outcomes")
		check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent chat chances and owners")
		check(f.service.executor.rng.draws == 5 + messages.size() + int(bool(bits & 4)) + int(bool(bits & 8)), "Only four consequence chances and necessary text draws")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var records: Array = person.memories.find({"type": "relationship_decline"})
			check(records.size() == int(bool(bits & (4 << side))), "Independent diary chances")
			if not records.is_empty():
				var entry: Dictionary = records[0]
				check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == 25 and entry.topic == "social" and entry.tags == ["social", "negative", "relationship"] and entry.provenance.kind == "experienced" and not entry.permanent, "Exact diary metadata")
				check(entry.created_minute == f.clock.total_minutes and entry.source_occurrence_id == result.occurrence_id, "Diary identifies the occurrence")
			check(person.memories.size() == int(side == 0) + records.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == -20, "No extra memories, moodlets or opinion changes")
		check(f.a.memories.find({"type": "unpleasant_interaction"}) == prior_record, "Qualifying memory is read-only")
		cleanup(f)

func dislike_texts() -> void:
	for variant in 5:
		var f := dislike()
		dislike_memory(f)
		var definition := definition_for(f, DISLIKE)
		var indices := [variant, (variant + 1) % 5, (variant + 2) % 5, (variant + 3) % 5, (variant + 4) % 5]
		var draws: Array = [0, 0, 0, 0]
		for index in indices: draws.append((index + 0.1) / 5.0)
		f.service.executor.rng.values = draws
		var messages: Array = []
		f.service.resident_message.connect(func(_id, _name, line): messages.append(line))
		check(fire(f).status == "completed", "Every text variant can be rendered")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var values := {"speaker": person.event_text_projection(), "partner": partner.event_text_projection()}
			var entry: Dictionary = person.memories.find({"type": "relationship_decline"})[0]
			check(messages[side] == Renderer.render(definition.params.chat[indices[side]], values).text, "All chat variants for both speakers")
			check(entry.text == Renderer.render(definition.params.diary[indices[side + 2]], values).text, "All diary variants for both speakers")
			if indices[side] == 2:
				check(messages[side].contains("предпочла бы" if side == 0 else "предпочёл бы"), "Chat agrees with the speaker")
			if indices[side + 2] in [0, 2, 4]:
				check(entry.text.contains("со Степаном" if side == 0 else "с Анной"), "Diary uses instrumental and proper preposition")
		var expected: String = definition.text.chronicle[indices[4]]
		expected = expected.replace("{actor.name}", "Анна").replace("{other.name}", "Степан").replace("{actor.name:gen}", "Анны").replace("{other.name:gen}", "Степана").replace("{actor.name:ins}", "Анной").replace("{other.name:ins}", "Степаном")
		check(f.service.chronicle.entries()[0].text == expected, "All five chronicles, including both genitives and instrumentals")
		cleanup(f)

func dislike_atomicity() -> void:
	for scenario in ["memory", "capacity", "opinion", "recipient", "clock", "revision", "journal"]:
		var f := dislike()
		f.clock.total_minutes = COOLDOWN
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		dislike_memory(f)
		var notices: Array = []
		f.service.chronicle.changed.connect(func(id): notices.append(id))
		f.service.resident_message.connect(func(_id, _name, line): notices.append(line))
		for person in [f.a, f.b]:
			person.memories.changed.connect(func(id):
				if id != "prior": notices.append(id))
		var last_draw := 9
		if scenario == "recipient":
			f.service.executor.rng.values = [0.5, 0.5, 0.5, 0.5]
			last_draw = 5
		f.service.executor.rng.on_draw = func(draw):
			if draw != last_draw: return
			match scenario:
				"memory": f.a.memories.remove("prior")
				"capacity": add_tier_links(f, f.b, [-1, -1, -2, -3, -3])
				"opinion": f.a.set_opinion("b", -19)
				"recipient": f.control.unregister_resident("b")
				"clock": f.clock.total_minutes += 1
				"revision": check(transition(f, 1, 0) and transition(f, 0, 0), "Change and restore the level after preparation")
		var result := fire(f)
		check(result.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Late refusal: " + scenario + " " + str(result))
		var link: Dictionary = f.control.social_links.get_link(f.a, f.b)
		check(link.link_level == 0 and (link.normal_transition_available_at == COOLDOWN if scenario == "revision" else link.normal_transition_available_at == null) and f.service.chronicle.size() == 0 and f.service.completed_events().is_empty(), "No partial transition, new cooldown or chronicle")
		check(notices.is_empty() and f.a.memories.find({"type": "relationship_decline"}).is_empty() and f.b.memories.find({"type": "relationship_decline"}).is_empty(), "No partial diaries, chat or notices")
		cleanup(f)

	var stale := dislike()
	stale.clock.total_minutes = COOLDOWN
	dislike_memory(stale)
	stale.rng.on_draw = func(draw):
		if draw == 2: check(transition(stale, 1, 0) and transition(stale, 0, 0), "Change and restore level during selection")
	check(fire(stale).status == "prepare_failed" and stale.service.executor.rng.draws == 0, "Stale selection is rejected before effect draws")
	stale.rng.on_draw = Callable()
	cleanup(stale)

	var nested := dislike()
	dislike_memory(nested)
	var observed: Array = []
	var messages: Array = []
	var deadline: int = nested.clock.total_minutes + COOLDOWN
	nested.service.resident_message.connect(func(id, _name, _line): messages.append(id))
	nested.a.memories.changed.connect(func(_id):
		var token: String = nested.service.last_occurrence().occurrence_id
		var link: Dictionary = nested.control.social_links.get_link(nested.a, nested.b)
		observed.append([link.link_level, link.normal_transition_available_at, nested.b.memories.size(), nested.service.chronicle.size(), nested.service.replay(token).status])
		nested.service.executor.publish(token)
		nested.social.resolve(nested.b, nested.a, SocialResult.Context.WORK))
	var completed := fire(nested)
	check(completed.status == "completed" and observed == [[-1, deadline, 1, 1, "completed"]], "Nested callback sees both committed stores, link and cooldown")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued occurrence cannot repeat the transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": completed.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(completed.occurrence_id)
	check(nested.service.replay(completed.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == deadline, "Replay does not extend the cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 1, "Replay creates no duplicate consequences")
	cleanup(nested)

func dislike_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12112026
	var counts := {"chance_failed": 0, DISLIKE: 0, GRUDGE: 0}
	for index in 600:
		var f := dislike(false)
		dislike_memory(f, false, {"created_minute": f.clock.total_minutes - 1})
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f, SocialResult.Context.WORK)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[DISLIKE] + counts[GRUDGE] == 600 and absf(counts[DISLIKE] / 600.0 - 0.15) < 0.06, "Seeded shared gate and equal-weight competition")
	print("Mutual dislike sample seed=12112026 N=600 ", JSON.stringify(counts))
