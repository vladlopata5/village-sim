extends "res://tests/test_mutual_dislike.gd"

const COMMON_GROUND := "social.find_common_ground"

func common_ground(isolated: bool = true, minute: int = COOLDOWN) -> Dictionary:
	var f := acquaintances(false)
	if isolated: only(f, COMMON_GROUND)
	var links: RefCounted = f.control.social_links
	check(links.commit_transition(links.prepare_transition(f.a, f.b, -1, 0), 0), "Seed ordinary -1 from level zero")
	f.clock.total_minutes = minute
	f.a.set_opinion("b", -40)
	f.b.set_opinion("a", -40)
	f.social.rng.rolls = [100, 0]
	return f

func ground_memory(f: Dictionary, side: bool = false, overrides: Dictionary = {}) -> void:
	var record := {"strength": 1}
	record.merge(overrides, true)
	prior(f, side, record)

func _run() -> void:
	ground_eligibility()
	ground_competition()
	ground_outcomes()
	ground_texts()
	ground_atomicity()
	zero_level_cooldown()
	ground_statistics()
	print("Find common ground: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func ground_eligibility() -> void:
	for context in SocialResult.Context.values():
		for side in [false, true]:
			var f := common_ground()
			f.social.rng.rolls = [0, 100] if side else [100, 0]
			ground_memory(f, side)
			check(fire(f, context).status == "completed" and f.control.social_links.get_level(f.a, f.b) == 0, "Either side qualifies at strength 1 in a different occurrence of the same minute")
			check(f.a.get_opinion("b") == (-41 if side else -39) and f.b.get_opinion("a") == (-39 if side else -41), "Only normal reactions alter opinions even outside the new tier's range")
			cleanup(f)

	for side in [false, true]:
		for scenario in ["missing", "weak", "tag", "target", "future", "same occurrence", "other memory", "neutral", "negative"]:
			var f := common_ground()
			f.social.rng.rolls = [0, 100] if side else [100, 0]
			var changes := {}
			match scenario:
				"weak": changes.strength = 0
				"tag": changes.tags = ["social"]
				"target": changes.target = {"kind": "resident", "id": f.b.id if side else f.a.id}
				"future": changes.created_minute = COOLDOWN + 1
				"same occurrence": changes.source_occurrence_id = JSON.stringify(["social.resolved", 1])
				"other memory": ground_memory(f, not side)
				"neutral": f.social.rng.rolls[int(side)] = 50
				"negative": f.social.rng.rolls[int(side)] = 0
			if scenario not in ["missing", "other memory"]: ground_memory(f, side, changes)
			var before: Dictionary = f.control.social_links.get_link(f.a, f.b)
			check(fire(f).status == "no_match" and f.service.chronicle.size() == 0 and f.control.social_links.get_link(f.a, f.b) == before, "Reaction and prior memory must belong to the same side: %s / %s" % [side, scenario])
			cleanup(f)

	for level in [-3, -2, 0, 1, 2, 3]:
		var f := common_ground()
		check(transition(f, level, 0), "Seed an expired level other than -1")
		ground_memory(f)
		check(fire(f).status == "no_match" and f.control.social_links.get_level(f.a, f.b) == level, "Reject level " + str(level))
		cleanup(f)

	for minute in [COOLDOWN - 1, COOLDOWN]:
		var f := common_ground(true, minute)
		ground_memory(f, true)
		var source: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
		var result: Dictionary = f.service.replay(source.confirmed_context().occurrence_id)
		check(result.status == ("completed" if minute == COOLDOWN else "no_match"), "Shared cooldown applies in reverse order at 10079 and 10080")
		cleanup(f)

	for opinion in [-50, 0]:
		var f := common_ground()
		f.a.set_opinion("b", opinion)
		f.b.set_opinion("a", opinion)
		ground_memory(f)
		check(fire(f).status == "completed", "No opinion condition at either end of the dislike range")
		check(f.a.get_opinion("b") == mini(0, opinion + 1) and f.b.get_opinion("a") == maxi(-50, opinion - 1), "Transition preserves actual ordinary opinion changes")
		cleanup(f)

func ground_competition() -> void:
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		var f := common_ground(false)
		f.social.rng.rolls = [100, 100]
		ground_memory(f, false, {"created_minute": COOLDOWN - 1})
		f.rng.value = draw
		var result := fire(f, SocialResult.Context.WORK)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == [COMMON_GROUND, WARM] and result.definition_id == (COMMON_GROUND if draw < 0.5 else WARM), "Two equal-weight candidates in the production catalog")
		check(f.control.social_links.get_level(f.a, f.b) == (0 if draw < 0.5 else -1), "Only the selected event affects the shared link")
		cleanup(f)

	for draw in [0.299999, 0.3]:
		var f := common_ground()
		ground_memory(f)
		f.service.selector.set_chance("social.resolved", 0.3)
		f.rng.value = draw
		check(fire(f).status == ("completed" if draw < 0.3 else "chance_failed"), "Exact boundary of the shared gate, no additional gate")
		cleanup(f)

func ground_outcomes() -> void:
	for bits in 16:
		for role_mask in [1, 2, 3]:
			var f := common_ground()
			f.social.rng.rolls = [100, 100]
			if role_mask & 1: ground_memory(f)
			if role_mask & 2: ground_memory(f, true)
			var messages: Array = []
			f.service.resident_message.connect(func(id, _name, line): messages.append([id, line]))
			for index in 4: f.service.executor.rng.values.append(0.499999 if bits & (1 << index) else 0.5)
			var result := fire(f)
			var link: Dictionary = f.control.social_links.get_link(f.b, f.a)
			check(result.status == "completed" and link.link_level == 0 and link.normal_transition_available_at == 2 * COOLDOWN and f.service.chronicle.size() == 1, "Mandatory effects on all sixteen outcomes for every role configuration")
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
					check(entry.owner.id == person.id and entry.target.id == partner.id and entry.strength == (25 if reconciles else 15) and entry.topic == "social" and entry.tags == ["social", "positive", "relationship"] and entry.provenance.kind == "experienced" and not entry.permanent, "Diary uses the role of the same side, including when both are ready to reconcile")
					check(entry.created_minute == COOLDOWN and entry.source_occurrence_id == result.occurrence_id, "Diary identifies the committed occurrence")
				check(person.memories.size() == int(reconciles) + records.size() and person.moodlets.size() == 0 and person.get_opinion(partner.id) == -39, "No extra diary, moodlet or opinion effects")
			cleanup(f)

func ground_texts() -> void:
	for mask in [1, 2, 3]:
		for variant in 5:
			var f := common_ground()
			f.social.rng.rolls = [100, 100]
			if mask & 1: ground_memory(f)
			if mask & 2: ground_memory(f, true)
			var definition := definition_for(f, COMMON_GROUND)
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
				if reconciles and chat_index == 1:
					check(messages[side].contains("относилась" if side == 0 else "относился"), "Chat agrees with the speaker")
				if reconciles and diary_index == 1:
					check(entry.text.contains("Вспомнила" if side == 0 else "Вспомнил,") and entry.text.contains("обращала" if side == 0 else "обращал внимание"), "Both diary verbs agree with the speaker")
				if reconciles and diary_index == 2:
					check(entry.text.contains("Степан не такой уж неприятный человек" if side == 0 else "Анна не такая уж неприятная"), "Diary agrees with the partner")
				if reconciles and diary_index == 4:
					check(entry.text.contains("почувствовала" if side == 0 else "почувствовал раздражения"), "Diary uses the speaker's gender")
				if not reconciles and diary_index == 1:
					check(entry.text.contains("не уверена," if side == 0 else "не уверен,"), "Other diary agrees with the speaker")
				if (reconciles and diary_index in [0, 1, 4]) or (not reconciles and diary_index in [0, 3]):
					check(entry.text.contains("со Степаном" if side == 0 else "с Анной"), "Instrumental and preposition")
			var history: String = f.service.chronicle.entries()[0].text
			var expected: String = definition.text.chronicle[indices[4]]
			expected = expected.replace("{actor.name}", "Анна").replace("{other.name}", "Степан").replace("{actor.name:gen}", "Анны").replace("{other.name:gen}", "Степана").replace("{actor.name:ins}", "Анной").replace("{other.name:ins}", "Степаном")
			check(history == expected, "All five chronicle texts, including both genitives and instrumentals")
			cleanup(f)

func ground_atomicity() -> void:
	for scenario in ["both lose role", "one loses role", "other gains role", "revision", "recipient", "clock", "journal"]:
		var f := common_ground()
		f.social.rng.rolls = [100, 100]
		if scenario == "journal": f.b.memories = LateRejectingJournal.new("b")
		ground_memory(f)
		if scenario in ["both lose role", "one loses role", "journal"]: ground_memory(f, true)
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
				"other gains role": ground_memory(f, true)
				"revision": check(transition(f, 0, 0) and transition(f, -1, 0), "Change and restore the level during preparation")
				"recipient": f.control.unregister_resident("b")
				"clock": f.clock.total_minutes += 1
		var result := fire(f)
		check(result.status == "prepare_failed" and f.service.executor.rng.draws == last_draw, "Late refusal: " + scenario + " " + str(result))
		var link: Dictionary = f.control.social_links.get_link(f.a, f.b)
		check(link.link_level == -1 and link.normal_transition_available_at == COOLDOWN and f.service.chronicle.size() == 0 and f.service.completed_events().is_empty(), "No partial transition, cooldown or chronicle")
		check(notices.is_empty() and f.a.memories.find({"type": "relationship_recovery"}).is_empty() and f.b.memories.find({"type": "relationship_recovery"}).is_empty(), "No partial diaries, chat or notifications")
		cleanup(f)

	var nested := common_ground()
	ground_memory(nested)
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
	check(completed.status == "completed" and observed == [[0, 2 * COOLDOWN, 1, 1, "completed"]], "Nested callback observes the full commit")
	check(nested.service.replay(nested.service.last_occurrence().occurrence_id).status == "no_match", "Queued occurrence cannot repeat the transition")
	var draws: int = nested.service.executor.rng.draws
	nested.clock.total_minutes += 1
	nested.service.executor.execute({}, {"occurrence_id": completed.occurrence_id}, nested.clock.total_minutes, nested.a)
	nested.service.executor.publish(completed.occurrence_id)
	check(nested.service.replay(completed.occurrence_id).duplicate and nested.service.executor.rng.draws == draws and nested.control.social_links.get_link(nested.a, nested.b).normal_transition_available_at == 2 * COOLDOWN, "Replay does not extend the cooldown or roll again")
	check(messages == ["a", "b"] and nested.service.chronicle.size() == 1 and nested.a.memories.size() == 2 and nested.b.memories.size() == 1, "Replay creates no duplicate consequences")
	cleanup(nested)

func zero_level_cooldown() -> void:
	var f := common_ground(false)
	var links: RefCounted = f.control.social_links
	var old_link: Dictionary = links.get_link(f.a, f.b)
	check(old_link.link_level == -1 and old_link.normal_transition_available_at == COOLDOWN, "Fixture starts with an ordinary -1 and a cooldown")
	check(links.prepare_transition(f.b, f.a, 0, COOLDOWN - 1).is_empty(), "Return to zero is blocked before cooldown elapses")
	var old_plan: Dictionary = links.prepare_transition(f.a, f.b, 0, COOLDOWN)
	check(not old_plan.is_empty(), "Ordinary recovery is available at the boundary")
	ground_memory(f)
	f.service.executor.rng.values = [0.5, 0.5, 0.5, 0.5]
	check(fire(f, SocialResult.Context.WORK).definition_id == COMMON_GROUND, "Production recovery event takes the pair to zero")
	var zero: Dictionary = links.get_link(f.b, f.a)
	check(zero.link_level == 0 and zero.revision > old_link.revision and zero.normal_transition_available_at == 2 * COOLDOWN, "Level zero retains a new revision and shared deadline")
	check(not links.commit_transition(old_plan, COOLDOWN) and links.get_link(f.a, f.b) == zero, "An old plan cannot overwrite the zero-level record")
	check(links.counts_for(f.a).negative_1 == 0 and links.counts_for(f.b).negative_1 == 0, "Level zero no longer counts as dislike")
	check(f.a.get_opinion("b") == -39 and f.b.get_opinion("a") == -41, "Both opinions outside the zero-level range retain the actual post-reaction value")
	for minute in [COOLDOWN, 2 * COOLDOWN - 1]:
		check(links.prepare_transition(f.a, f.b, 1, minute).is_empty() and links.prepare_transition(f.b, f.a, -1, minute).is_empty(), "Both ordinary directions remain blocked at level zero")
	only(f, DISLIKE)
	f.social.rng.rolls = [0, 0]
	f.clock.total_minutes = 2 * COOLDOWN - 1
	dislike_memory(f, false, {"id": "negative-prior"})
	check(fire(f).status == "no_match" and links.get_link(f.a, f.b) == zero, "Mutual dislike is blocked even when opinions, reactions and memory qualify")
	f.clock.total_minutes += 1
	check(links.normal_transition_ready(f.b, f.a, f.clock.total_minutes), "Shared deadline expires at the exact minute")
	var reversed: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
	check(f.service.replay(reversed.confirmed_context().occurrence_id).definition_id == DISLIKE and links.get_level(f.a, f.b) == -1, "The production event completes the -1 to 0 to -1 cycle at the boundary")
	check(links.get_link(f.b, f.a).normal_transition_available_at == 3 * COOLDOWN, "Renewed dislike starts another shared cooldown")
	cleanup(f)

func ground_statistics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13112026
	var counts := {"chance_failed": 0, COMMON_GROUND: 0, WARM: 0}
	for index in 600:
		var f := common_ground(false)
		f.social.rng.rolls = [100, 100]
		ground_memory(f, false, {"created_minute": COOLDOWN - 1})
		f.service.selector.set_chance("social.resolved", 0.3)
		f.service.selector.rng = rng
		var result := fire(f, SocialResult.Context.WORK)
		var key: String = result.get("definition_id", result.status)
		counts[key] = counts.get(key, 0) + 1
		cleanup(f)
	check(counts.chance_failed + counts[COMMON_GROUND] + counts[WARM] == 600 and absf(counts[COMMON_GROUND] / 600.0 - 0.15) < 0.06, "Seeded shared gate and equal-weight competition")
	print("Common ground sample seed=13112026 N=600 ", JSON.stringify(counts))
