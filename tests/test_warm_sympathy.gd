extends "res://tests/test_event_catalog_content.gd"
const Renderer = preload("res://scripts/event_text_renderer.gd")
const Memory = preload("res://scripts/memory_store.gd")

func sympathy_fixture(people: Array = []) -> Dictionary:
	if people.is_empty(): people = [Data.new("a", "Анна", 25), Data.new("b", "Степан", 30)]
	people[0].grammatical_gender = Traits.GrammaticalGender.FEMININE
	var f := fixture(people)
	prepare_story(f, "social.warm_sympathy"); only(f, "social.warm_sympathy")
	return f

func _run() -> void:
	eligibility(); independent_outcomes(); symmetric_cooldown(); texts_and_orientation()
	independent_formulations(); atomic_and_repeat(); memory_contract(); statistics()
	await ui_company()
	print("Warm sympathy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func eligibility() -> void:
	for context in SocialResult.Context.values():
		for first in [-100, 0, 100]:
			for second in [-100, 0, 100]:
				var f := sympathy_fixture(); f.social.rng.rolls = [first, second]
				var result := fire(f, context)
				var expected: bool = first == 100 and second == 100
				check(result.status == ("completed" if expected else "no_match"), "Both positive in all three social contexts")
				check(f.a.get_opinion("b") == signi(first) and f.b.get_opinion("a") == signi(second), "Only the original directed social deltas")
				check(f.service.chronicle.size() == int(expected), "Only a completed event writes one chronicle")
				cleanup(f)
	var production := fixture(); var service := Service.new()
	check(service.selector._chances["social.resolved"] == 0.3, "Unchanged production 30 percent")
	service.free()
	var story := definition_for(production, "social.warm_sympathy")
	check(story.weight == 1 and story.cooldown.minutes == 240 and story.cooldown.symmetric, "Weight one and symmetric 240-minute cooldown")
	cleanup(production)

func rolls(bits: int, sender: float = 0.0) -> Array:
	# Four independent effects, exclusive chat chance/choice, shared moodlet chance.
	var values: Array = []
	for i in 4: values.append(0.0 if bits & (1 << i) else 1.0)
	values.append(0.0 if bits & 16 else 1.0)
	if bits & 16: values.append(sender)
	values.append(0.0 if bits & 32 else 1.0)
	return values

func independent_outcomes() -> void:
	for bits in 64:
		for sender in [0.0, 1.0]:
			var f := sympathy_fixture(); var messages: Array = []
			f.service.resident_message.connect(func(id, name, text): messages.append([id, name, text]))
			f.service.executor.rng.values = rolls(bits, sender)
			var result := fire(f)
			check(result.status == "completed" and f.service.chronicle.size() == 1, "Every consequence combination commits exactly one event")
			for side in 2:
				var person: RefCounted = f.a if side == 0 else f.b
				var partner: RefCounted = f.b if side == 0 else f.a
				check(person.diary_entries.size() == int(bool(bits & (1 << side))), "Independent 50-percent diary")
				var memories: Array = person.memories.find()
				check(memories.size() == int(bool(bits & (1 << (side + 2)))), "Independent 30-percent memory")
				if not memories.is_empty():
					var memory: Dictionary = memories[0]
					check(memory.type == "pleasant_interaction" and memory.tags == ["social", "positive"] and memory.target.id == partner.id and memory.strength == 30 and memory.provenance == {"kind":"experienced"} and not memory.permanent and not memory.text.is_empty(), "Structured memory, other target, one stored text")
				var company: Array = person.moodlets.find({"type":"pleasant_company"})
				check(company.size() == int(bool(bits & 32)) and person.mood == (60 if bits & 32 else 50), "Shared chance yields both +10 offsets or neither")
				if not company.is_empty(): check(company[0].target.id == partner.id and company[0].expires_at_minute == 755 and company[0].context.display_name == "Приятная компания", "Company target, title, 120-minute deadline")
			check(messages.size() == int(bool(bits & 16)), "Chat is independent and sends at most one message")
			if bits & 16:
				check(messages[0][0] == ("a" if sender == 0 else "b") and messages[0][1] == ("Анна" if sender == 0 else "Степан"), "Equal choice of the real sender")
				check(messages[0][2] == ("Со Степаном приятно проводить время!" if sender == 0 else "С Анной приятно проводить время!"), "Other resident is the chat partner")
			var draws: int = f.service.executor.rng.draws
			var token: String = f.service.last_occurrence().occurrence_id
			var history: Array = f.service.chronicle.entries()
			f.clock.total_minutes += 10
			f.service.replay(token); f.service.executor.execute({}, f.service.last_occurrence(), 645, f.a); f.service.executor.publish(token)
			check(f.service.executor.rng.draws == draws and f.service.chronicle.entries() == history and messages.size() == int(bool(bits & 16)), "Duplicate neither rerolls nor republishes")
			if bits & 32: check(f.a.moodlets.find({"type":"pleasant_company"})[0].expires_at_minute == 755, "Duplicate cannot refresh deadline")
			cleanup(f)
	var boundary := sympathy_fixture()
	boundary.service.executor.rng.values = [0.5, 0.5, 0.3, 0.3, 0.25, 0.5]
	check(fire(boundary).status == "completed" and boundary.a.diary_entries.is_empty() and boundary.b.diary_entries.is_empty() and boundary.a.memories.size() == 0 and boundary.b.memories.size() == 0 and boundary.a.mood == 50, "Exact probability boundaries fail at equality")
	cleanup(boundary)

func symmetric_cooldown() -> void:
	var f := sympathy_fixture(); var observations: Array = []
	f.a.diary_changed.connect(func(): observations.append({"history":f.service.cooldown_history(), "moods":[f.a.mood,f.b.mood], "diaries":[f.a.diary_entries.size(),f.b.diary_entries.size()], "memories":[f.a.memories.size(),f.b.memories.size()]}))
	check(fire(f).status == "completed", "First pair event succeeds")
	var history: Dictionary = f.service.cooldown_history()
	check(history.size() == 2 and history.values() == [635, 635], "Both directed records committed with the same minute")
	check(observations.size() == 1 and observations[0].history == history and observations[0].moods == [60.0,60.0] and observations[0].diaries == [1,1] and observations[0].memories == [1,1], "Both cooldowns and all consequences exist before any publication")
	check(f.a.mood == 60 and f.b.mood == 60 and f.a.memories.size() == 1 and f.b.memories.size() == 1, "Both residents receive the committed transaction")
	var result: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "no_match", "Swapping roles cannot bypass cooldown")
	f.clock.total_minutes = 874; check(fire(f).status == "no_match", "239 minutes remains blocked")
	f.clock.total_minutes = 875; result = f.social.resolve(f.b, f.a, SocialResult.Context.MEAL)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "completed" and f.service.cooldown_history().values() == [875, 875], "Reversed pair succeeds at 240 and refreshes both directions")
	cleanup(f)
	for keep_reverse in [false, true]:
		var old := sympathy_fixture(); fire(old)
		var keys: Array = old.service._history.keys(); old.service._history.erase(keys[0 if keep_reverse else 1])
		check(fire(old).status == "no_match", "Either stored direction alone blocks the pair")
		cleanup(old)

func texts_and_orientation() -> void:
	for feminine in [false, true]:
		for index in 12:
			var f := sympathy_fixture()
			if feminine:
				f.a.resident_name = "Иван"; f.a.grammatical_gender = Traits.GrammaticalGender.MASCULINE
				f.b.resident_name = "Анна"; f.b.grammatical_gender = Traits.GrammaticalGender.FEMININE
			var definition := definition_for(f, "social.warm_sympathy")
			check(definition.params.diary_text.size() == 12 and definition.params.memory_text.size() == 12 and definition.params.chat_text.size() == 12, "One shared pool per channel, no orientation copies")
			var draw := (index + 0.25) / 12.0
			f.service.executor.rng.values = [0,0,0,0,0,0,0,draw,draw,draw,draw,draw,float(index % 4) / 4 + 0.01]
			var messages: Array = []; f.service.resident_message.connect(func(id, _name, text): messages.append([id,text]))
			check(fire(f).status == "completed", "All selected textual effects commit")
			for pair in [[f.a,f.b],[f.b,f.a]]:
				var person: RefCounted = pair[0]; var partner: RefCounted = pair[1]
				var values := {"speaker":person.event_text_projection(),"partner":partner.event_text_projection()}
				var diary_text: String = Renderer.render(definition.params.diary_text[index], values).text
				var memory_text: String = Renderer.render(definition.params.memory_text[index], values).text
				check(person.diary_entries[0].text == diary_text and person.memories.find()[0].text == memory_text, "All 12 diary/memory variants once, in owner's perspective")
				if index == 3: check(diary_text.contains("обрадовалась" if person.grammatical_gender == Traits.GrammaticalGender.FEMININE else "обрадовался"), "Gender belongs to the actual owner")
				var frozen: Dictionary = person.memories.find()[0]; f.clock.total_minutes += 1
				check(person.memories.get_entry(frozen.id).text == memory_text, "Reading never selects a new variant")
			var expected_chat: String = Renderer.render(definition.params.chat_text[index], {"speaker":f.a.event_text_projection(),"partner":f.b.event_text_projection()}).text
			check(messages == [["a",expected_chat]], "All 12 chat variants use actual sender/partner")
			var chronicle: String = f.service.chronicle.entries()[0].text
			if index % 4 == 2: check(chronicle == ("Между Иваном и Анной возникла взаимная симпатия." if feminine else "Между Анной и Степаном возникла взаимная симпатия."), "Instrumental after Между for both genders")
			if index % 4 == 3: check(chronicle.contains("Ивана и Анны" if feminine else "Анны и Степана"), "Genitive of both participants")
			cleanup(f)

func independent_formulations() -> void:
	var f := sympathy_fixture(); var definition := definition_for(f, "social.warm_sympathy")
	var messages: Array = []; f.service.resident_message.connect(func(_id, _name, text): messages.append(text))
	f.service.executor.rng.values = [0,0,0,0,0,1,0,0.01,0.1,0.18,0.26,0.34,0.6]
	fire(f)
	var actor_values := {"speaker":f.a.event_text_projection(),"partner":f.b.event_text_projection()}
	var other_values := {"speaker":f.b.event_text_projection(),"partner":f.a.event_text_projection()}
	check(f.a.diary_entries[0].text == Renderer.render(definition.params.diary_text[0],actor_values).text and f.b.diary_entries[0].text == Renderer.render(definition.params.diary_text[1],other_values).text, "Independent diary formulation draws")
	check(f.a.memories.find()[0].text == Renderer.render(definition.params.memory_text[2],actor_values).text and f.b.memories.find()[0].text == Renderer.render(definition.params.memory_text[3],other_values).text, "Independent memory formulation draws")
	check(messages == [Renderer.render(definition.params.chat_text[4],other_values).text] and messages[0] == "Не думал, что мы так быстро поладим!", "Reversed speaker uses its own gender and independent chat draw")
	check(f.service.chronicle.entries()[0].text == "Между Анной и Степаном возникла взаимная симпатия.", "Chronicle has its own independent variant draw")
	cleanup(f)

func atomic_and_repeat() -> void:
	for reason in ["diary", "store", "inactive", "late_inactive", "template"]:
		var people: Array = [Data.new("a", "Анна", 25), RejectingDiary.new("b", "Степан", 30)] if reason == "diary" else []
		var f := sympathy_fixture(people); var messages: Array = []
		f.service.resident_message.connect(func(id, _name, text): messages.append([id,text]))
		if reason == "store": f.b.moodlets = RejectingStore.new("b")
		if reason in ["inactive", "late_inactive"]:
			f.service.executor.rng.on_draw = func(draw):
				if draw == (8 if reason == "inactive" else 13): f.control.unregister_resident("b")
		if reason == "template": f.service.catalog._by_trigger["social.resolved"][0].params.memory_text[11] = "{partner.missing}"
		var result := fire(f)
		check(result.status != "completed" and f.service.completed_events().is_empty() and f.service.chronicle.size() == 0 and f.service.cooldown_history().is_empty(), "Failure leaves no history or cooldown: " + reason)
		check(f.a.diary_entries.is_empty() and f.b.diary_entries.is_empty() and f.a.memories.size() == 0 and f.b.memories.size() == 0 and f.a.moodlets.size() == 0 and f.b.moodlets.size() == 0 and messages.is_empty(), "No partial consequences: " + reason)
		cleanup(f)
	var refreshed := sympathy_fixture(); refreshed.service.executor.rng.values = rolls(32); fire(refreshed)
	var first: Dictionary = refreshed.a.moodlets.find({"type":"pleasant_company"})[0]
	var independent := definition_for(refreshed, "social.warm_sympathy"); independent.id = "test.independent_company"; independent.erase("cooldown")
	load_content(refreshed, {"definitions":[independent]}); refreshed.clock.total_minutes = 645
	refreshed.service.executor.rng = SequenceRng.new(); refreshed.service.executor.rng.values = rolls(32)
	check(fire(refreshed).status == "completed" and refreshed.a.moodlets.size() == 1 and refreshed.a.mood == 60 and refreshed.b.mood == 60, "Different event refreshes, never stacks +10")
	check(refreshed.a.moodlets.find()[0].expires_at_minute == 765 and first.expires_at_minute == 755, "Refresh has new now+120 deadline")
	refreshed.clock.total_minutes = 765; refreshed.a.moodlets.advance(765); refreshed.b.moodlets.advance(765)
	check(refreshed.a.mood == 50 and refreshed.b.mood == 50 and refreshed.a.moodlets.size() == 0 and refreshed.b.moodlets.size() == 0, "Both offsets disappear exactly at expiry")
	cleanup(refreshed)

func memory_contract() -> void:
	var f := sympathy_fixture(); var definition := definition_for(f, "social.warm_sympathy")
	for mutation in ["alias", "brace", "empty", "scope", "missing_scope", "flag"]:
		var bad := definition.duplicate(true)
		if mutation == "alias": bad.effects[0].text_bindings["actor"] = {"role":"actor"}
		if mutation == "brace": bad.params.memory_text[0] = "{partner.name"
		if mutation == "empty": bad.params.diary_text = []
		if mutation == "scope": bad.cooldown.scope.pop_back()
		if mutation == "missing_scope": bad.cooldown.erase("scope")
		if mutation == "flag": bad.cooldown.symmetric = "yes"
		check(not f.service.catalog.load_data({"definitions":[bad]}, f.service.facts), "Catalog rejects invalid text/bindings/cooldown: " + mutation)
	var record := {"id":"old","type":"old","topic":"social","strength":30,"created_minute":1,"source_occurrence_id":"old","provenance":{"kind":"experienced"}}
	var store := Memory.new("a")
	check(store.add(record) and not store.get_entry("old").has("text"), "Old memories without text retain schema and matching")
	for invalid in [null, 42, [], ""]:
		var bad := record.duplicate(true); bad.id = "bad"; bad["text"] = invalid
		check(not store.add(bad), "Optional text requires a nonempty ready string")
	var ready := record.duplicate(true); ready.id = "ready"; ready["text"] = "Мне было приятно общаться со Степаном"
	check(store.add(ready) and store.reinforce("ready", 5, 2, "later") and store.weaken("ready", 1, 3, 0), "Ready text works with ordinary memory mutations")
	check(store.get_entry("ready").text == ready.text and store.find({"text":ready.text}).size() == 1, "Memory reinforcement and queries retain the original formulation")
	cleanup(f)

func statistics() -> void:
	var f := sympathy_fixture(); var rng := RandomNumberGenerator.new(); rng.seed = 725463; f.service.executor.rng = rng
	var counts := [0,0,0,0,0,0,0,0]; var joint := [0,0,0,0]; var signature: Array = []
	var messages: Array = []; f.service.resident_message.connect(func(id, _name, _text): messages.append(id))
	var samples := 4000
	for index in samples:
		f.clock.total_minutes = 635 + index * 240
		var result := fire(f); check(result.status == "completed", "Seeded trial completes")
		var flags := [false,false,false,false,false,false]
		for effect in result.effects:
			if effect.op == "diary.add": flags[0 if effect.owner == "a" else 1] = true
			if effect.op == "memory.add": flags[2 if effect.owner == "a" else 3] = true
			if effect.op == "moodlet.add": flags[4] = true
			if effect.op == "chat.say": flags[5] = true
		for bit in flags.size(): counts[bit] += int(flags[bit])
		if flags[5]: counts[6 if messages.back() == "a" else 7] += 1
		joint[int(flags[0]) + int(flags[1]) * 2] += 1
		if index < 30: signature.append([result.effects, f.a.memories.find().map(func(entry): return entry.text), rng.state])
		# Test-only cleanup avoids production retention policy changes.
		f.a.memories._entries.clear(); f.b.memories._entries.clear(); f.a.diary_entries.clear(); f.b.diary_entries.clear()
	for i in 6:
		var expected: float = [0.5,0.5,0.3,0.3,0.5,0.25][i]
		check(absf(float(counts[i])/samples - expected) < 0.035, "Fixed seed chances near design")
	for count in joint: check(absf(float(count)/samples - 0.25) < 0.035, "All four diary combinations near 25 percent")
	check(absi(counts[6]-counts[7]) < samples * 0.025, "Sender split near 50/50")
	print("SYMPATHY_STATISTICS samples=",samples," counts=",counts," diary_joint=",joint)
	var again := sympathy_fixture(); again.service.executor.rng = RandomNumberGenerator.new(); again.service.executor.rng.seed = 725463
	for index in 30:
		again.clock.total_minutes = 635 + index * 240
		var result := fire(again)
		check([result.effects,again.a.memories.find().map(func(entry): return entry.text),again.service.executor.rng.state] == signature[index], "Same seed reproduces effects, stored text and RNG state")
		again.a.memories._entries.clear(); again.b.memories._entries.clear(); again.a.diary_entries.clear(); again.b.diary_entries.clear()
	cleanup(again); cleanup(f)

func ui_company() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate(); root.add_child(scene)
	configure_world(scene); scene.social_events.rng.rolls = [100,100]
	var actor: Node = scene.resident_runtimes[1]; var partner: Node = scene.resident_runtimes[3]
	var result: RefCounted = scene.social_events.resolve(actor.data, partner.data, SocialResult.Context.CONVERSATION)
	check(scene.game_events.replay(result.confirmed_context().occurrence_id).definition_id == "social.warm_sympathy", "Canonical world executes actual event")
	scene.resident_selection.select(actor.data)
	scene.game_ui.info_panel.set_expanded(true); scene.game_ui.info_panel.select_tab(&"bio")
	await process_frame
	var card: Control = scene.resident_card_view()
	check(card.moodlets_label.text.contains("Приятная компания"), "Card displays data-driven company title")
	scene.free(); await process_frame
