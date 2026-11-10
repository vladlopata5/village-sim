extends "res://tests/test_mutual_dislike.gd"

const ENEMIES := "social.become_enemies"

func enemies(isolated: bool = true, minute: int = COOLDOWN, people: Array = []) -> Dictionary:
	var f := acquaintances(false) if people.is_empty() else fixture(people)
	if isolated: only(f, ENEMIES)
	var links: RefCounted = f.control.social_links
	check(links.commit_transition(links.prepare_transition(f.a, f.b, -1, 0), 0), "Seed ordinary dislike at -1")
	f.social.rng.rolls = [0, 0]
	f.clock.total_minutes = minute
	f.a.set_opinion("b", -44)
	f.b.set_opinion("a", -44)
	return f

func enemy_memories(f: Dictionary) -> void:
	dislike_memory(f)
	dislike_memory(f, true, {"type": "remembered_disagreement", "topic": "work", "text": "Прежние разногласия", "created_minute": f.clock.total_minutes - 1})

func _run() -> void:
	enemy_eligibility()
	enemy_competition()
	enemy_outcomes()
	enemy_texts()
	enemy_atomicity()
	enemy_statistics()
	print("Become enemies: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func enemy_eligibility() -> void:
	for context in SocialResult.Context.values():
		var f := enemies()
		enemy_memories(f)
		check(fire(f, context).status == "completed", "Mutual memories of different types and a prior occurrence in the same minute qualify")
		check(f.a.get_opinion("b") == -45 and f.b.get_opinion("a") == -45, "Both opinions meet the exact threshold only after the ordinary reactions")
		cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "tag", "target", "zero", "future", "same occurrence", "opinion"]:
			var f := enemies()
			var changes := {}
			var person: RefCounted = f.b if side else f.a
			var partner_id: String = f.a.id if side else f.b.id
			match scenario:
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": person.id}
				"zero": changes.strength = 0
				"future": changes.created_minute = COOLDOWN + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"opinion": person.set_opinion(partner_id, -43)
			dislike_memory(f, not side)
			if scenario != "missing": dislike_memory(f, side, changes)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Either side can independently fail: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -2, 0, 1, 2, 3]:
		var f := enemies()
		f.a.set_opinion("b", -45)
		f.b.set_opinion("a", -45)
		check(transition(f, level, 0), "Seed another level with expired cooldown and sufficient opinions")
		enemy_memories(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Only -1 qualifies, not " + str(level))
		cleanup(f)

	for first in [0, 50, 100]:
		for second in [0, 50, 100]:
			if first == 0 and second == 0: continue
			var f := enemies()
			f.a.set_opinion("b", -47)
			f.b.set_opinion("a", -47)
			enemy_memories(f)
			f.social.rng.rolls = [first, second]
			check(fire(f).status == "no_match", "All eight reaction combinations other than NEGATIVE/NEGATIVE are rejected with sufficient opinions")
			cleanup(f)

	var outside := enemies()
	check(transition(outside, -3, 0) and outside.a.set_opinion("b", -85) and transition(outside, -1, 0), "Seed an opinion below the future tier range")
	enemy_memories(outside)
	check(fire(outside).status == "completed" and outside.a.get_opinion("b") == -85 and outside.b.get_opinion("a") == -45, "Transition preserves an actual opinion outside the new bounds")
	check(not outside.a.set_opinion("b", -86) and outside.a.set_opinion("b", -84), "New tier retains the usual recovery towards range")
	cleanup(outside)

	for side in [0, 1]:
		for blocked in [false, true]:
			var f := enemies()
			enemy_memories(f)
			var person: RefCounted = f.a if side == 0 else f.b
			# With the candidate pair itself, both cases already have five links <= -1.
			add_tier_links(f, person, [-1, -1 if not blocked else -2, -2, -3])
			var counts: Dictionary = f.control.social_links.counts_for(person)
			check(counts.negative_1 == 5 and counts.negative_2 == (3 if blocked else 2), "Nested capacity includes -3 links")
			check(fire(f).status == ("no_match" if blocked else "completed"), "Only capacity at -2 matters for either participant")
			var after: Dictionary = f.control.social_links.counts_for(person)
			check(after.negative_1 == 5 and after.negative_2 == 3, "Upgrade preserves the number of links <= -1")
			cleanup(f)

	for minute in [COOLDOWN - 1, COOLDOWN]:
		var f := enemies(true, minute)
		enemy_memories(f)
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		check(result.status == ("completed" if minute == COOLDOWN else "no_match"), "Shared cooldown boundary applies in reverse order")
		cleanup(f)

func enemy_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := enemies(false)
		dislike_memory(f, false, {"created_minute": f.clock.total_minutes - 1})
		dislike_memory(f, true)
		f.rng.value = draw
		var result := fire(f, SocialResult.Context.WORK)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [ENEMIES, GRUDGE] and result.definition_id == (ENEMIES if draw < 0.5 else GRUDGE), "Equal weights in the production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == (-2 if draw < 0.5 else -1), "Competition applies only the selected event")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := enemies()
		enemy_memories(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact boundary of the existing 30 percent gate")
		cleanup(f)

func enemy_outcomes() -> void:
	for bits in 16:
		var f := enemies()
		enemy_memories(f)
		var messages: Array = []
		f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
		for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
		var result := fire(f)
		var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
		check(result.status == "completed" and link.link_level == -2 and link.normal_transition_available_at == 2 * COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes")
		check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent 50 percent chat for each speaker")
		for side in 2:
			var person: RefCounted = f.a if side == 0 else f.b
			var partner: RefCounted = f.b if side == 0 else f.a
			var entries: Array = person.memories.find({"type": "relationship_decline"})
			check(entries.size() == int(bool(bits & (4 << side))), "Independent 50 percent diary for each resident")
			if not entries.is_empty():
				var entry: Dictionary = entries[0]
				check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == 40 and entry.topic == "social" and entry.tags == ["social", "negative", "relationship", "enmity"] and entry.provenance.kind == "experienced" and not entry.permanent, "Exact friendship memory parameters")
				check(entry.created_minute == COOLDOWN and entry.source_occurrence_id == result.occurrence_id, "Memory identifies the committed occurrence")
			check(person.memories.size() == 1 + entries.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == -45, "No extra opinion or moodlets, earlier memory remains")
		cleanup(f)


func enemy_texts() -> void:
	for first in [0, 1]:
		for second in [2, 3]:
			for variant in 5:
				var names := ["Иван", "Анна", "Степан", "Ольга"]
				var genitives := ["Ивана", "Анны", "Степана", "Ольги"]
				var instrumentals := ["Иваном", "Анной", "Степаном", "Ольгой"]
				var with_names := ["с Иваном", "с Анной", "со Степаном", "с Ольгой"]
				var a := Data.new("a", names[first], 25)
				var b := Data.new("b", names[second], 25)
				if first == 1: a.grammatical_gender = Traits.GrammaticalGender.FEMININE
				if second == 3: b.grammatical_gender = Traits.GrammaticalGender.FEMININE
				var f := enemies(true, COOLDOWN, [a, b])
				enemy_memories(f)
				var definition := definition_for(f, ENEMIES)
				var indices := [variant, (variant + 1) % 5, (variant + 2) % 5, (variant + 3) % 5, (variant + 4) % 5]
				var draws: Array = [0, 0, 0, 0]
				for index in indices: draws.append((index + 0.1) / 5.0)
				f.service.executor.rng.values = draws
				var messages: Array = []
				f.service.resident_message.connect(func(_id, _name, line): messages.append(line))
				check(fire(f).status == "completed" and f.service.executor.rng.draws == 9, "All variant choices independent for any pair of genders")
				for side in 2:
					var speaker := a if side == 0 else b
					var partner := b if side == 0 else a
					var speaker_feminine: bool = (first if side == 0 else second) % 2 == 1
					var partner_feminine: bool = (second if side == 0 else first) % 2 == 1
					var with_partner: String = with_names[second if side == 0 else first]
					var values := {"speaker": speaker.event_text_projection(), "partner": partner.event_text_projection()}
					var chat_index: int = indices[side]
					var diary_index: int = indices[side + 2]
					var entry: Dictionary = speaker.memories.find({"type": "relationship_decline"})[0]
					check(messages[side] == Renderer.render(definition.params.chat[chat_index], values).text, "Chat renders the chosen variant")
					check(entry.text == Renderer.render(definition.params.diary[diary_index], values).text, "Diary renders the chosen variant")
					match chat_index:
						1: check(messages[side].contains("раздражала," if partner_feminine else "раздражал,"), "Chat agrees with partner")
						2: check(messages[side].ends_with("убедилась." if speaker_feminine else "убедился."), "Chat agrees with speaker")
						3: check(messages[side].contains("иметь дело " + with_partner + ","), "Chat inserts one correct preposition")
					match diary_index:
						0:
							check(entry.text.contains("убедилась," if speaker_feminine else "убедился,"), "Diary agrees with speaker")
							check(entry.text.contains("нам " + with_partner + " не по пути"), "Diary uses the correct preposition")
						1: check(entry.text.contains("иметь " + with_partner + " никаких"), "Diary uses correct instrumental with one preposition")
						2:
							check(entry.text.contains("стала для меня" if partner_feminine else "стал для меня"), "Diary agrees with partner")
							check(entry.text.contains("Не думала," if speaker_feminine else "Не думал,"), "Diary agrees with speaker independently")
						3: check(entry.text.contains("надеялась," if speaker_feminine else "надеялся,"), "Diary reflexive verb agrees with speaker")
						4: check(entry.text.contains("связанные " + with_partner + "."), "Diary does not duplicate the preposition")
				var expected: String = definition.text.chronicle[indices[4]]
				expected = expected.replace("{actor.name}", names[first]).replace("{other.name}", names[second]).replace("{actor.name:gen}", genitives[first]).replace("{other.name:gen}", genitives[second]).replace("{actor.name:ins}", instrumentals[first]).replace("{other.name:ins}", instrumentals[second])
				check(f.service.chronicle.entries()[0].text == expected, "Chronicle uses names in the correct cases")
				cleanup(f)

func enemy_atomicity() -> void:
	for scenario in ["actor memory", "other memory", "recipient", "capacity", "opinion", "pair revision", "clock", "journal"]:
		var f := enemies()
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		enemy_memories(f)
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
				"capacity": add_tier_links(f, f.b, [-2, -2, -3])
				"opinion": f.a.set_opinion("b", -44)
				"pair revision": check(transition(f, 0, 0) and transition(f, -1, 0), "Pair changed and returned to -1 during preparation")
				"clock": f.clock.total_minutes += 1
		var refused := fire(f)
		check(refused.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Reject stale preparation after selecting texts: " + scenario + " " + str(refused))
		check(f.control.social_links.get_level(f.a, f.b) == -1 and f.control.social_links.get_link(f.a, f.b).normal_transition_available_at == COOLDOWN, "Rejected event leaves link and cooldown untouched")
		check(f.service.completed_events().is_empty() and f.service.chronicle.size() == 0 and notices.is_empty(), "No chronicle, chat or notification on rejected transition")
		check(f.a.memories.find({"type": "relationship_decline"}).is_empty() and f.b.memories.find({"type": "relationship_decline"}).is_empty(), "No partial diary writes")
		cleanup(f)

	var nested := enemies()
	enemy_memories(nested)
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
	check(result.status == "completed" and observed == [[-2, 2 * COOLDOWN, 2, 1, "completed"]], "Nested callback observes all committed effects")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued nested occurrence does not start a second transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": result.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(result.occurrence_id)
	check(nested.service.replay(result.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 2 * COOLDOWN, "Replay does not renew cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 2, "Replay emits neither notices nor new entries")
	cleanup(nested)

func enemy_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 14112026
	var counts := {"chance_failed": 0, ENEMIES: 0, GRUDGE: 0}
	for index in 600:
		var f := enemies(false)
		dislike_memory(f, false, {"created_minute": f.clock.total_minutes - 1})
		dislike_memory(f, true)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f, SocialResult.Context.WORK)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[ENEMIES] + counts[GRUDGE] == 600 and absf(counts[ENEMIES] / 600.0 - 0.15) < 0.06, "Seeded gate and equal-weight competition")
	print("Enmity sample seed=14112026 N=600 ", JSON.stringify(counts))
