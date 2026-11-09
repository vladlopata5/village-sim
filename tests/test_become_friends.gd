extends "res://tests/test_become_acquaintances.gd"

const FRIENDS := "social.become_friends"
const WARM := "social.warm_sympathy"
const COOLDOWN := preload("res://scripts/social_link_store.gd").TRANSITION_COOLDOWN_MINUTES

func friends(isolated: bool = true, minute: int = COOLDOWN) -> Dictionary:
	var f := acquaintances(false)
	if isolated: only(f, FRIENDS)
	check(transition(f, 1, 0), "Seed an ordinary friendship candidate at +1")
	f.clock.total_minutes = minute
	f.a.set_opinion("b", 44)
	f.b.set_opinion("a", 44)
	return f

func mutual_memories(f: Dictionary) -> void:
	prior(f)
	prior(f, true, {"type": "remembered_kindness", "topic": "work", "text": "Помощь в работе", "created_minute": f.clock.total_minutes - 1})

func add_tier_links(f: Dictionary, person: RefCounted, levels: Array) -> void:
	var links: RefCounted = f.control.social_links
	for index in levels.size():
		var neighbor := Data.new("%s-friend-%d" % [person.id, index], "Сосед", 25)
		f.control.register_resident(neighbor)
		var prepared: Dictionary = links.prepare_transition(person, neighbor, levels[index], 0, true)
		check(links.commit_transition(prepared, 0), "Seed a link of tier " + str(levels[index]))

func _run() -> void:
	friend_eligibility()
	friend_competition()
	friend_outcomes()
	friend_atomicity()
	friend_statistics()
	print("Become friends: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func friend_eligibility() -> void:
	for context in SocialResult.Context.values():
		var f := friends()
		mutual_memories(f)
		check(fire(f, context).status == "completed", "Mutual memories of different types and a prior occurrence in the same minute qualify")
		check(f.a.get_opinion("b") == 45 and f.b.get_opinion("a") == 45, "Both opinions meet the exact threshold only after the ordinary reactions")
		cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "tag", "target", "zero", "future", "same occurrence", "opinion", "neutral", "negative"]:
			var f := friends()
			var changes := {}
			var person: RefCounted = f.b if side else f.a
			var partner_id: String = f.a.id if side else f.b.id
			match scenario:
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": person.id}
				"zero": changes.strength = 0
				"future": changes.created_minute = COOLDOWN + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"opinion": person.set_opinion(partner_id, 43)
				"neutral": f.social.rng.rolls[int(side)] = 50
				"negative": f.social.rng.rolls[int(side)] = 0
			prior(f, not side)
			if scenario != "missing": prior(f, side, changes)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Either side can independently fail: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -2, -1, 0, 2, 3]:
		var f := friends()
		f.a.set_opinion("b", 45)
		f.b.set_opinion("a", 45)
		check(transition(f, level, 0), "Seed another level with expired cooldown and sufficient opinions")
		mutual_memories(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Only +1 qualifies, not " + str(level))
		cleanup(f)

	for side in [0, 1]:
		for blocked in [false, true]:
			var f := friends()
			mutual_memories(f)
			var person: RefCounted = f.a if side == 0 else f.b
			# With the candidate pair itself, both cases already have five links >= +1.
			add_tier_links(f, person, [1, 1 if not blocked else 2, 2, 3])
			var counts: Dictionary = f.control.social_links.counts_for(person)
			check(counts.positive_1 == 5 and counts.positive_2 == (3 if blocked else 2), "Nested capacity includes close friends")
			check(fire(f).status == ("no_match" if blocked else "completed"), "Only capacity at +2 matters for either participant")
			var after: Dictionary = f.control.social_links.counts_for(person)
			check(after.positive_1 == 5 and after.positive_2 == 3, "Upgrade preserves the number of links >= +1")
			cleanup(f)

	for minute in [COOLDOWN - 1, COOLDOWN]:
		var f := friends(true, minute)
		mutual_memories(f)
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		check(result.status == ("completed" if minute == COOLDOWN else "no_match"), "Shared cooldown boundary applies in reverse order")
		cleanup(f)

func friend_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := friends(false)
		mutual_memories(f)
		f.rng.value = draw
		var result := fire(f)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [FRIENDS, WARM] and result.definition_id == (FRIENDS if draw < 0.5 else WARM), "Equal weights in the production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == (2 if draw < 0.5 else 1), "Competition applies only the selected event")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := friends()
		mutual_memories(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact boundary of the existing 30 percent gate")
		cleanup(f)

func friend_outcomes() -> void:
	for bits in 16:
		var f := friends()
		mutual_memories(f)
		var messages: Array = []
		f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
		for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
		var result := fire(f)
		var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
		check(result.status == "completed" and link.link_level == 2 and link.normal_transition_available_at == 2 * COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes")
		check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent 50 percent chat for each speaker")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var entries: Array = person.memories.find({"type": "relationship_progress"})
			check(entries.size() == int(bool(bits & (4 << side))), "Independent 50 percent diary for each resident")
			if not entries.is_empty():
				var entry: Dictionary = entries[0]
				check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == 40 and entry.topic == "social" and entry.tags == ["social", "positive", "relationship", "friendship"] and entry.provenance.kind == "experienced" and not entry.permanent, "Exact friendship memory parameters")
				check(entry.created_minute == COOLDOWN and entry.source_occurrence_id == result.occurrence_id, "Memory identifies the committed occurrence")
			check(person.memories.size() == 1 + entries.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == 45, "No extra opinion or moodlets, earlier memory remains")
		cleanup(f)

	for variant in 5:
		var f := friends()
		mutual_memories(f)
		var definition := definition_for(f, FRIENDS)
		var indices := [variant, (variant + 1) % 5, (variant + 2) % 5, (variant + 3) % 5, (variant + 4) % 5]
		var draws: Array = [0, 0, 0, 0]
		for index in indices: draws.append((index + 0.1) / 5.0)
		f.service.executor.rng.values = draws
		var messages: Array = []
		f.service.resident_message.connect(func(_id, _name, line): messages.append(line))
		check(fire(f).status == "completed" and f.service.executor.rng.draws == 9, "Four consequence draws and five independent text choices")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var values := {"speaker": person.event_text_projection(), "partner": partner.event_text_projection()}
			var entry: Dictionary = person.memories.find({"type": "relationship_progress"})[0]
			check(messages[side] == Renderer.render(definition.params.chat[indices[side]], values).text, "All chat texts for both partners")
			check(entry.text == Renderer.render(definition.params.diary[indices[2 + side]], values).text, "All diary texts for both speakers")
			if indices[side] == 0:
				check(messages[side].ends_with("настоящий друг." if side == 0 else "настоящая подруга."), "Chat agrees with partner gender")
			match indices[2 + side]:
				0, 3: check(entry.text.contains("со Степаном" if side == 0 else "с Анной"), "Instrumental and preposition")
				2:
					var expected := "Сегодня поймала себя на мысли, что давно считаю Степана своим другом. Интересно, почему раньше этого не замечала." if side == 0 else "Сегодня поймал себя на мысли, что давно считаю Анну своей подругой. Интересно, почему раньше этого не замечал."
					check(entry.text == expected, "Speaker gender and accusative with partner gender agreement")
				4: check(entry.text.contains("ещё один настоящий друг" if side == 0 else "ещё одна настоящая подруга"), "Diary agrees with partner gender")
		var history: String = f.service.chronicle.entries()[0].text
		var expected_history: String = definition.text.chronicle[indices[4]].replace("{actor.name}", "Анна").replace("{other.name}", "Степан").replace("{actor.name:gen}", "Анны").replace("{other.name:gen}", "Степана")
		check(history == expected_history, "All chronicle texts, including both genitives")
		cleanup(f)

func friend_atomicity() -> void:
	for scenario in ["actor memory", "other memory", "recipient", "capacity", "opinion", "pair revision", "journal"]:
		var f := friends()
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		mutual_memories(f)
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
				"actor memory": f.a.memories.remove("prior")
				"other memory": f.b.memories.remove("prior")
				"recipient": f.control.unregister_resident("b")
				"capacity": add_tier_links(f, f.b, [2, 2, 3])
				"opinion": f.a.set_opinion("b", 44)
				"pair revision": check(transition(f, 2, 0) and transition(f, 1, 0), "Pair changed and returned to +1 during preparation")
		var refused := fire(f)
		check(refused.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Reject stale preparation after selecting texts: " + scenario + " " + str(refused))
		check(f.control.social_links.get_level(f.a, f.b) == 1 and f.control.social_links.get_link(f.a, f.b).normal_transition_available_at == COOLDOWN, "Rejected event leaves link and cooldown untouched")
		check(f.service.completed_events().is_empty() and f.service.chronicle.size() == 0 and notices.is_empty(), "No chronicle, chat or notification on rejected transition")
		check(f.a.memories.find({"type": "relationship_progress"}).is_empty() and f.b.memories.find({"type": "relationship_progress"}).is_empty(), "No partial diary writes")
		cleanup(f)

	var nested := friends()
	mutual_memories(nested)
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
	var result := fire(nested)
	check(result.status == "completed" and observed == [[2, 2 * COOLDOWN, 2, 1, "completed"]], "Nested callback observes all committed effects")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued nested occurrence does not start a second transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": result.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(result.occurrence_id)
	check(nested.service.replay(result.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 2 * COOLDOWN, "Replay does not renew cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 2, "Replay emits neither notices nor new entries")
	cleanup(nested)

func friend_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9112026
	var counts := {"chance_failed": 0, FRIENDS: 0, WARM: 0}
	for index in 600:
		var f := friends(false)
		mutual_memories(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[FRIENDS] + counts[WARM] == 600 and absf(counts[FRIENDS] / 600.0 - 0.15) < 0.06, "Seeded gate and equal-weight competition")
	print("Friendship sample seed=9112026 N=600 ", JSON.stringify(counts))
