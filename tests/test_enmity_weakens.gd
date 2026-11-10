extends "res://tests/test_become_enemies.gd"

const WEAKENS := "social.enmity_weakens"

func enmity(isolated: bool = true, minute: int = COOLDOWN) -> Dictionary:
	var f := acquaintances(false)
	if isolated: only(f, WEAKENS)
	check(transition(f, -2, 0), "Seed enmity at -2")
	f.clock.total_minutes = minute
	f.a.set_opinion("b", -60)
	f.b.set_opinion("a", -60)
	f.social.rng.rolls = [100, 0]
	return f

func weakens_memory(f: Dictionary, side: bool = false, overrides: Dictionary = {}) -> void:
	var record := {"strength": 30}
	record.merge(overrides, true)
	prior(f, side, record)

func _run() -> void:
	weakens_eligibility()
	weakens_competition()
	weakens_outcomes()
	weakens_texts()
	weakens_atomicity()
	reversible_enmity()
	weakens_statistics()
	print("Enmity weakens: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func weakens_eligibility() -> void:
	for context in SocialResult.Context.values():
		for side in [false, true]:
			var f := enmity()
			f.social.rng.rolls = [0, 100] if side else [100, 0]
			weakens_memory(f, side)
			check(fire(f, context).status == "completed" and f.control.social_links.get_level(f.a, f.b) == -1, "Either side qualifies at strength 30 in a different occurrence of the same minute")
			check(f.a.get_opinion("b") == (-61 if side else -59) and f.b.get_opinion("a") == (-59 if side else -61), "Only normal reactions alter opinions even outside the new tier's range")
			cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "weak", "tag", "target", "future", "same occurrence", "other memory", "neutral", "negative"]:
			var f := enmity()
			f.social.rng.rolls = [0, 100] if side else [100, 0]
			var changes := {}
			match scenario:
				"weak": changes.strength = 29
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": f.b.id if side else f.a.id}
				"future": changes.created_minute = COOLDOWN + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"other memory": weakens_memory(f, not side)
				"neutral": f.social.rng.rolls[int(side)] = 50
				"negative": f.social.rng.rolls[int(side)] = 0
			if scenario not in ["missing", "other memory"]: weakens_memory(f, side, changes)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Reaction and prior memory must belong to the same side: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -1, 0, 1, 2, 3]:
		var f := enmity()
		check(transition(f, level, 0), "Seed an expired level other than -2")
		weakens_memory(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Reject level " + str(level))
		cleanup(f)

	for minute in [COOLDOWN - 1, COOLDOWN]:
		var f := enmity(true, minute)
		weakens_memory(f, true)
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		check(result.status == ("completed" if minute == COOLDOWN else "no_match"), "Shared cooldown applies in reverse order at 10079 and 10080")
		cleanup(f)

	for opinion in [-75, -25]:
		var f := enmity()
		f.a.set_opinion("b", opinion)
		f.b.set_opinion("a", opinion)
		weakens_memory(f)
		check(fire(f).status == "completed", "No opinion condition at either end of the enmity range")
		check(f.a.get_opinion("b") == mini(-25, opinion + 1) and f.b.get_opinion("a") == maxi(-75, opinion - 1), "Transition preserves actual ordinary opinion changes")
		cleanup(f)

func weakens_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := enmity(false)
		f.social.rng.rolls = [100, 100]
		weakens_memory(f, false, {"created_minute": COOLDOWN - 1})
		f.rng.value = draw
		var result := fire(f, SocialResult.Context.WORK)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [WEAKENS, WARM] and result.definition_id == (WEAKENS if draw < 0.5 else WARM), "Two equal-weight candidates in the production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == (-1 if draw < 0.5 else -2), "Only the selected event affects the shared link")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := enmity()
		weakens_memory(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact boundary of the shared gate, no additional gate")
		cleanup(f)

func weakens_outcomes() -> void:
	for bits in 16:
		for role_mask in [1, 2, 3]:
			var f := enmity()
			f.social.rng.rolls = [100, 100]
			weakens_memory(f, false, {"strength": 30 if role_mask & 1 else 29})
			weakens_memory(f, true, {"strength": 30 if role_mask & 2 else 29})
			var messages: Array = []
			f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
			for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
			var result := fire(f)
			var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
			check(result.status == "completed" and link.link_level == -1 and link.normal_transition_available_at == 2 * COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes for every role configuration")
			check(messages.map(func(message): return message[0]) == (["a"] if bits & 1 else []) + (["b"] if bits & 2 else []), "Independent 50 percent chat chances")
			check(f.service.executor.rng.draws == 5 + messages.size() + int(bool(bits & 4)) + int(bool(bits & 8)), "Only four chance draws and the needed presentation draws")
			for side in 2:
				var person: RefCounted = f.a if side == 0 else f.b
				var partner: RefCounted = f.b if side == 0 else f.a
				var reconciles := bool(role_mask & (1 << side))
				var records: Array = person.memories.find({"type": "relationship_recovery"})
				check(records.size() == int(bool(bits & (4 << side))), "Independent diary chance")
				if not records.is_empty():
					var entry: Dictionary = records[0]
					check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == (40 if reconciles else 25) and entry.topic == "social" and entry.tags == ["social", "positive", "relationship", "enmity"] and entry.provenance.kind == "experienced" and not entry.permanent, "Diary uses the role of the same side, including when both are ready to reconcile")
					check(entry.created_minute == COOLDOWN and entry.source_occurrence_id == result.occurrence_id, "Diary identifies the committed occurrence")
				check(person.memories.size() == 1 + records.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == -59, "No extra diary, moodlet or opinion effects")
			cleanup(f)

func weakens_texts() -> void:
	for mask in [1, 2, 3]:
		for variant in 5:
			var f := enmity()
			f.social.rng.rolls = [100, 100]
			if mask & 1: weakens_memory(f)
			if mask & 2: weakens_memory(f, true)
			var definition := definition_for(f, WEAKENS)
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
				var reconciles := bool(mask & (1 << side))
				var role := "reconcile" if reconciles else "other"
				var chat_index: int = indices[side]
				var diary_index: int = indices[2 + side]
				var entry: Dictionary = person.memories.find({"type": "relationship_recovery"})[0]
				check(messages[side] == Renderer.render(definition.params[role + "_chat"][chat_index], values).text, "Chat renders the correct pool for each role and speaker")
				check(entry.text == Renderer.render(definition.params[role + "_diary"][diary_index], values).text, "Diary renders the correct pool for each role and speaker")
				if reconciles and chat_index == 0:
					check(messages[side].contains("держала на" if side == 0 else "держал на"), "Chat agrees with the speaker")
				if reconciles and chat_index == 4:
					check(messages[side].contains("Степана своим" if side == 0 else "Анну своим"), "Chat uses the partner's accusative")
				if reconciles:
					match diary_index:
						0: check(entry.text.contains("вспомнила," if side == 0 else "вспомнил,"), "Diary agrees with the speaker")
						1: check(entry.text.contains("обиды на Степана." if side == 0 else "обиды на Анну."), "Diary uses the accusative")
						2: check(entry.text.contains("обнаружила," if side == 0 else "обнаружил,") and entry.text.contains("к Степану." if side == 0 else "к Анне."), "Diary agrees with the speaker and uses the dative")
						4: check(entry.text.contains("подумала," if side == 0 else "подумал,"), "Diary uses the speaker's gender")
				else:
					match diary_index:
						0: check(entry.text.contains("Степан больше не настроен так" if side == 0 else "Анна больше не настроена так"), "Diary agrees with the partner")
						1: check(entry.text.contains("не готова забыть" if side == 0 else "не готов забыть"), "Other diary agrees with the speaker")
						3: check(entry.text.contains("Не уверена," if side == 0 else "Не уверен,") and entry.text.contains("доверять Степану" if side == 0 else "доверять Анне"), "Other diary uses the dative")
				if (reconciles and diary_index in [0, 3]) or (not reconciles and diary_index in [1, 4]):
					check(entry.text.contains("со Степаном" if side == 0 else "с Анной"), "Instrumental and preposition")
			var history: String = f.service.chronicle.entries()[0].text
			var expected: String = definition.text.chronicle[indices[4]]
			expected = expected.replace("{actor.name}", "Анна").replace("{other.name}", "Степан").replace("{actor.name:gen}", "Анны").replace("{other.name:gen}", "Степана").replace("{actor.name:ins}", "Анной").replace("{other.name:ins}", "Степаном")
			check(history == expected, "All five chronicle texts, including both genitives and instrumentals")
			cleanup(f)

func weakens_atomicity() -> void:
	for scenario in ["both lose role", "first loses role", "second loses role", "other gains role", "revision", "recipient", "clock", "journal"]:
		var f := enmity()
		f.social.rng.rolls = [100, 100]
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		weakens_memory(f)
		if scenario in ["both lose role", "first loses role", "second loses role", "journal"]: weakens_memory(f, true)
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
				"first loses role": check(f.a.memories.weaken("prior", 1, f.clock.total_minutes, 0), "Drop the first role below 30 while the other still qualifies")
				"second loses role": check(f.b.memories.weaken("prior", 1, f.clock.total_minutes, 0), "Drop the second role below 30 while the other still qualifies")
				"other gains role": weakens_memory(f, true)
				"revision": check(transition(f, -1, 0) and transition(f, -2, 0), "Change and restore the level during preparation")
				"recipient": f.control.unregister_resident("b")
				"clock": f.clock.total_minutes += 1
		var result := fire(f)
		check(result.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Late refusal: " + scenario + " " + str(result))
		var link: Dictionary = f.control.social_links.get_link(f.a, f.b)
		check(link.link_level == -2 and link.normal_transition_available_at == COOLDOWN and f.service.chronicle.size() == 0 and f.service.completed_events().is_empty(), "No partial transition, cooldown or chronicle")
		check(notices.is_empty() and f.a.memories.find({"type": "relationship_recovery"}).is_empty() and f.b.memories.find({"type": "relationship_recovery"}).is_empty(), "No partial diaries, chat or notifications")
		cleanup(f)

	var nested := enmity()
	weakens_memory(nested)
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
	check(completed.status == "completed" and observed == [[-1, 2 * COOLDOWN, 1, 1, "completed"]], "Nested callback observes the full commit")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued occurrence cannot repeat the transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": completed.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(completed.occurrence_id)
	check(nested.service.replay(completed.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 2 * COOLDOWN, "Replay does not extend the cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 1, "Replay creates no duplicate consequences")
	cleanup(nested)

func reversible_enmity() -> void:
	var f := enemies(false)
	var links: RefCounted = f.control.social_links
	add_tier_links(f, f.a, [-3])
	add_tier_links(f, f.b, [-3])
	enemy_memories(f)
	only(f, ENEMIES)
	check(fire(f, SocialResult.Context.WORK).definition_id == ENEMIES, "Production event starts the -1 to -2 to -1 cycle")
	var enemy_link: Dictionary = links.get_link(f.a, f.b)
	check(enemy_link.link_level == -2 and enemy_link.normal_transition_available_at == 2 * COOLDOWN, "Starting enmity sets the first deadline")
	for person in [f.a, f.b]:
		var counts: Dictionary = links.counts_for(person)
		check(counts.negative_1 == 2 and counts.negative_2 == 2 and counts.negative_3 == 1, "Original pair and separate -3 link are both counted")

	f.service._load_catalogs()
	only(f, WEAKENS)
	f.a.set_opinion("b", -60)
	f.b.set_opinion("a", -60)
	f.social.rng.rolls = [100, 0]
	f.clock.total_minutes = 2 * COOLDOWN - 1
	weakens_memory(f, false, {"id": "positive-prior"})
	check(fire(f, SocialResult.Context.WORK).status == "no_match" and links.get_link(f.a, f.b) == enemy_link, "Recovery is blocked by the first deadline")
	f.clock.total_minutes += 1
	var plan: Dictionary = links.prepare_transition(f.a, f.b, -1, f.clock.total_minutes)
	check(not plan.is_empty() and fire(f, SocialResult.Context.WORK).definition_id == WEAKENS, "At the boundary the ordinary recovery completes the cycle")
	var dislike_link: Dictionary = links.get_link(f.b, f.a)
	check(dislike_link.link_level == -1 and dislike_link.revision > enemy_link.revision and dislike_link.normal_transition_available_at == 3 * COOLDOWN, "Recovery updates the revision and renews the deadline")
	check(not links.commit_transition(plan, f.clock.total_minutes), "Stale recovery plan cannot overwrite the commit")
	check(f.a.get_opinion("b") == -58 and f.b.get_opinion("a") == -62, "Both opinions outside the new range retain their actual post-reaction values")
	for person in [f.a, f.b]:
		var counts: Dictionary = links.counts_for(person)
		check(counts.negative_1 == 2 and counts.negative_2 == 1 and counts.negative_3 == 1, "Only the -2 threshold count falls for both residents")

	f.service._load_catalogs()
	only(f, ENEMIES)
	f.social.rng.rolls = [0, 0]
	f.clock.total_minutes = 3 * COOLDOWN - 1
	dislike_memory(f, false, {"id": "late-negative-a"})
	dislike_memory(f, true, {"id": "late-negative-b"})
	check(fire(f, SocialResult.Context.WORK).status == "no_match" and links.get_link(f.a, f.b) == dislike_link, "Renewed enmity is blocked one minute before the new deadline")
	f.clock.total_minutes += 1
	var reversed: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
	check(f.service.replay(reversed.confirmed_context().occurrence_id).definition_id == ENEMIES and links.get_level(f.a, f.b) == -2, "The existing event can return the pair to -2 at the exact boundary")
	check(links.get_link(f.b, f.a).normal_transition_available_at == 4 * COOLDOWN, "Enmity starts another shared cooldown")
	cleanup(f)

func weakens_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15112026
	var counts := {"chance_failed": 0, WEAKENS: 0, WARM: 0}
	for index in 600:
		var f := enmity(false)
		f.social.rng.rolls = [100, 100]
		weakens_memory(f, false, {"created_minute": COOLDOWN - 1})
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f, SocialResult.Context.WORK)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[WEAKENS] + counts[WARM] == 600 and absf(counts[WEAKENS] / 600.0 - 0.15) < 0.06, "Seeded shared gate and equal-weight competition")
	print("Weakening enmity sample seed=15112026 N=600 ", JSON.stringify(counts))
