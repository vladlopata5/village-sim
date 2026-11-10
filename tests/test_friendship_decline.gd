extends "res://tests/test_become_friends.gd"

const DECLINE := "social.friendship_decline"
const GRUDGE := "social.old_grudge"

func decline(isolated: bool = true, minute: int = COOLDOWN) -> Dictionary:
	var f := acquaintances(false)
	if isolated: only(f, DECLINE)
	check(transition(f, 2, 0), "Seed a friendship at +2")
	f.clock.total_minutes = minute
	f.a.set_opinion("b", 55)
	f.b.set_opinion("a", 55)
	f.social.rng.rolls = [0, 100]
	return f

func grievance(f: Dictionary, side: bool = false, overrides: Dictionary = {}) -> void:
	var record := {"type": "unpleasant_interaction", "tags": ["negative"], "strength": 30}
	record.merge(overrides, true)
	prior(f, side, record)

func _run() -> void:
	decline_eligibility()
	decline_competition()
	decline_outcomes()
	decline_texts()
	decline_atomicity()
	invalid_text_branch()
	decline_statistics()
	print("Friendship decline: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func decline_eligibility() -> void:
	for context in SocialResult.Context.values():
		for side in [false, true]:
			var f := decline()
			f.social.rng.rolls = [100, 0] if side else [0, 100]
			grievance(f, side)
			check(fire(f, context).status == "completed" and f.control.social_links.get_level(f.a, f.b) == 1, "Either side qualifies at strength 30 in a different occurrence of the same minute")
			check(f.a.get_opinion("b") == (56 if side else 54) and f.b.get_opinion("a") == (54 if side else 56), "Only normal reactions alter opinions even outside the new tier's range")
			cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "weak", "tag", "target", "future", "same occurrence", "other memory", "neutral", "positive"]:
			var f := decline()
			f.social.rng.rolls = [100, 0] if side else [0, 100]
			var changes := {}
			match scenario:
				"weak": changes.strength = 29
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": f.b.id if side else f.a.id}
				"future": changes.created_minute = COOLDOWN + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"other memory": grievance(f, not side)
				"neutral": f.social.rng.rolls[int(side)] = 50
				"positive": f.social.rng.rolls[int(side)] = 100
			if scenario not in ["missing", "other memory"]: grievance(f, side, changes)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Reaction and prior memory must belong to the same side: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -2, -1, 0, 1, 3]:
		var f := decline()
		check(transition(f, level, 0), "Seed an expired non-friendship level")
		grievance(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Reject level " + str(level))
		cleanup(f)

	for minute in [COOLDOWN - 1, COOLDOWN]:
		var f := decline(true, minute)
		grievance(f, true)
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		check(result.status == ("completed" if minute == COOLDOWN else "no_match"), "Shared cooldown applies in reverse order at 10079 and 10080")
		cleanup(f)

	for opinion in [25, 75]:
		var f := decline()
		f.a.set_opinion("b", opinion)
		f.b.set_opinion("a", opinion)
		grievance(f)
		check(fire(f).status == "completed", "No opinion condition at either end of the friendship range")
		check(f.a.get_opinion("b") == maxi(25, opinion - 1) and f.b.get_opinion("a") == mini(75, opinion + 1), "Transition preserves actual ordinary opinion changes")
		cleanup(f)

func decline_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := decline(false)
		grievance(f, false, {"created_minute": COOLDOWN - 1})
		f.rng.value = draw
		var result := fire(f, SocialResult.Context.WORK)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [DECLINE, GRUDGE] and result.definition_id == (DECLINE if draw < 0.5 else GRUDGE), "Two equal-weight candidates in the production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == (1 if draw < 0.5 else 2), "Only the selected event affects the shared link")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := decline()
		grievance(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact boundary of the shared gate, no additional gate")
		cleanup(f)

func decline_outcomes() -> void:
	for bits in 16:
		for role_mask in [1, 2, 3]:
			var f := decline()
			f.social.rng.rolls = [0, 0]
			if role_mask & 1: grievance(f)
			if role_mask & 2: grievance(f, true)
			var messages: Array = []
			f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
			for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
			var result := fire(f)
			var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
			check(result.status == "completed" and link.link_level == 1 and link.normal_transition_available_at == 2 * COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes for every role configuration")
			check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent 50 percent chat chances")
			check(f.service.executor.rng.draws == 5 + messages.size() + int(bool(bits & 4)) + int(bool(bits & 8)), "Only four chance draws and the needed presentation draws")
			for side in 2:
				var person: RefCounted = f.a if side == 0 else f.b
				var partner: RefCounted = f.b if side == 0 else f.a
				var hurt := bool(role_mask & (1 << side))
				var records: Array = person.memories.find({"type": "relationship_decline"})
				check(records.size() == int(bool(bits & (4 << side))), "Independent diary chance")
				if not records.is_empty():
					var entry: Dictionary = records[0]
					check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == (40 if hurt else 25) and entry.topic == "social" and entry.tags == ["social", "negative", "relationship", "friendship"] and entry.provenance.kind == "experienced" and not entry.permanent, "Diary uses the role of the same side, including both hurt")
					check(entry.created_minute == COOLDOWN and entry.source_occurrence_id == result.occurrence_id, "Diary identifies the committed occurrence")
				check(person.memories.size() == int(hurt) + records.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == 54, "No extra diary, moodlet or opinion effects")
			cleanup(f)

func decline_texts() -> void:
	for mask in [1, 2, 3]:
		for variant in 5:
			var f := decline()
			f.social.rng.rolls = [0, 0]
			if mask & 1: grievance(f)
			if mask & 2: grievance(f, true)
			var definition := definition_for(f, DECLINE)
			var indices := [variant, (variant + 1) % 5, (variant + 2) % 5, (variant + 3) % 5, (variant + 4) % 5]
			var draws: Array = [0, 0, 0, 0]
			for index in indices: draws.append((index + 0.1) / 5.0)
			f.service.executor.rng.values = draws
			var messages: Array = []
			f.service.resident_message.connect(func(_id, _name, line): messages.append(line))
			check(fire(f).status == "completed", "Every role can render all five texts in both channels")
			for side in 2:
				var person: RefCounted = f.a if side == 0 else f.b
				var partner: RefCounted = f.b if side == 0 else f.a
				var values := {"speaker": person.event_text_projection(), "partner": partner.event_text_projection()}
				var hurt := bool(mask & (1 << side))
				var role := "hurt" if hurt else "other"
				var chat_index: int = indices[side]
				var diary_index: int = indices[2 + side]
				var entry: Dictionary = person.memories.find({"type": "relationship_decline"})[0]
				check(messages[side] == Renderer.render(definition.params[role + "_chat"][chat_index], values).text, "Chat renders the correct pool for each role and speaker")
				check(entry.text == Renderer.render(definition.params[role + "_diary"][diary_index], values).text, "Diary renders the correct pool for each role and speaker")
				if not hurt and chat_index == 0:
					check(messages[side].contains("не уверена," if side == 0 else "не уверен,"), "Neutral-side chat agrees with the speaker")
				if hurt and chat_index == 1:
					check(messages[side].contains("пропустила " if side == 0 else "пропустил "), "Hurt chat agrees with the speaker")
				if hurt and diary_index == 0:
					check(entry.text.contains("обиды на Степана." if side == 0 else "обиды на Анну."), "Accusative for both names")
				if hurt and diary_index == 2:
					check(entry.text.ends_with("не уверена." if side == 0 else "не уверен."), "Hurt diary agrees with the speaker")
				if (hurt and diary_index == 1) or (not hurt and diary_index in [0, 3]):
					check(entry.text.contains("со Степаном" if side == 0 else "с Анной"), "Instrumental with appropriate preposition")
			var history: String = f.service.chronicle.entries()[0].text
			var expected: String = definition.text.chronicle[indices[4]]
			expected = expected.replace("{actor.name}", "Анна").replace("{other.name}", "Степан").replace("{actor.name:gen}", "Анны").replace("{other.name:gen}", "Степана").replace("{actor.name:ins}", "Анной").replace("{other.name:ins}", "Степаном")
			check(history == expected, "All five chronicle texts, including both genitives and instrumentals")
			cleanup(f)

func decline_atomicity() -> void:
	for scenario in ["both lose role", "one loses role", "other gains role", "revision", "recipient", "clock", "journal"]:
		var f := decline()
		f.social.rng.rolls = [0, 0]
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		grievance(f)
		if scenario in ["both lose role", "one loses role", "journal"]: grievance(f, true)
		if scenario == "journal": f.b.memories.validations = 0
		var notices: Array = []
		f.service.chronicle.changed.connect(func(id): notices.append(id))
		f.service.resident_message.connect(func(_id, _name, line): notices.append(line))
		f.a.memories.changed.connect(func(id):
			if id != "prior": notices.append(id))
		f.b.memories.changed.connect(func(id):
			if id != "prior": notices.append(id))
		var last_draw := 9
		if scenario == "recipient":
			f.service.executor.rng.values = [0.5, 0.5, 0.5, 0.5]
			last_draw = 5
		f.service.executor.rng.on_draw = func(draw):
			if draw != last_draw: return
			match scenario:
				"both lose role":
					f.a.memories.remove("prior")
					f.b.memories.remove("prior")
				"one loses role": f.a.memories.remove("prior")
				"other gains role": grievance(f, true)
				"revision": check(transition(f, 1, 0) and transition(f, 2, 0), "Change and restore the level during preparation")
				"recipient": f.control.unregister_resident("b")
				"clock": f.clock.total_minutes += 1
		var result := fire(f)
		check(result.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Late refusal: " + scenario + " " + str(result))
		var link: Dictionary = f.control.social_links.get_link(f.a, f.b)
		check(link.link_level == 2 and link.normal_transition_available_at == COOLDOWN and f.service.chronicle.size() == 0 and f.service.completed_events().is_empty(), "No partial transition, cooldown or chronicle")
		check(notices.is_empty() and f.a.memories.find({"type": "relationship_decline"}).is_empty() and f.b.memories.find({"type": "relationship_decline"}).is_empty(), "No partial diaries, chat or notifications")
		cleanup(f)

	var nested := decline()
	grievance(nested)
	var observed: Array = []
	var messages: Array = []
	nested.service.resident_message.connect(func(id, _name, _line): messages.append(id))
	nested.a.memories.changed.connect(func(id):
		if id == "prior": return
		var token: String = nested.service.last_occurrence().occurrence_id
		var link: Dictionary = nested.control.social_links.get_link(nested.a, nested.b)
		observed.append([link.link_level, link.normal_transition_available_at, nested.b.memories.size(), nested.service.chronicle.size(), nested.service.replay(token).status])
		nested.service.executor.publish(token)
		nested.social.resolve(nested.b, nested.a, SocialResult.Context.CONVERSATION))
	var completed := fire(nested)
	check(completed.status == "completed" and observed == [[1, 2 * COOLDOWN, 1, 1, "completed"]], "Nested callback observes the full commit")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued occurrence cannot repeat the transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": completed.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(completed.occurrence_id)
	check(nested.service.replay(completed.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 2 * COOLDOWN, "Replay does not extend the cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 1, "Replay creates no duplicate consequences")
	cleanup(nested)

func invalid_text_branch() -> void:
	var f := decline()
	var definition := definition_for(f, DECLINE)
	definition.params.other_chat = ["{missing.name}"]
	check(not f.service.catalog.load_data({"definitions": [definition]}, f.service.facts), "Catalog checks the alternative text branch before any outcome")
	check(f.service.catalog.errors.any(func(error): return error.contains("missing")), "Validation reports the invalid participant")
	cleanup(f)

func decline_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10112026
	var counts := {"chance_failed": 0, DECLINE: 0, GRUDGE: 0}
	for index in 600:
		var f := decline(false)
		grievance(f, false, {"created_minute": COOLDOWN - 1})
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f, SocialResult.Context.WORK)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[DECLINE] + counts[GRUDGE] == 600 and absf(counts[DECLINE] / 600.0 - 0.15) < 0.06, "Seeded shared gate and equal-weight competition")
	print("Friendship decline sample seed=10112026 N=600 ", JSON.stringify(counts))
