extends "res://tests/test_event_catalog_content.gd"

func _run() -> void:
	conditions_and_contexts()
	outcomes_and_grammar()
	cooldown_and_identity()
	atomic_refusals()
	await live_action()
	statistics()
	print("Social quarrel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func quarrel_fixture() -> Dictionary:
	var f := fixture([Data.new("a", "Иван", 25), Data.new("b", "Анна", 30)])
	f.b.grammatical_gender = Traits.GrammaticalGender.FEMININE
	MoodSetup.set_value(f.a, 20); MoodSetup.set_value(f.b, 20)
	f.social.rng.rolls = [0, 0]
	only(f, "social.rough_conversation")
	return f

func conditions_and_contexts() -> void:
	for context in SocialResult.Context.values():
		for mood in [19,20,21]:
			for reactions in [[0,0],[0,50],[50,0]]:
				var f := quarrel_fixture(); MoodSetup.set_value(f.a, mood); f.social.rng.rolls = reactions
				var result := fire(f, context)
				var expected: bool = mood <= 20 and reactions == [0,0]
				check((result.status == "completed") == expected, "Quarrel conditions mood/context/reactions: " + str([mood,context,reactions]))
				check(f.service.chronicle.size() == int(expected) and f.a.memories.size() == int(expected) and f.b.memories.size() == 0, "Exactly one world entry, no private duplicate")
				check(f.a.mood == mood and not f.service.last_occurrence().payload.has("mood"), "Real mood is read without mutation or changing social.resolved")
				check(PairFacts.snapshot(f.a,f.b,635).read({"kind":"resident","id":"a"},"mood").value == mood, "Mood fact is a real snapshot")
				cleanup(f)
	var boundary := quarrel_fixture(); boundary.service.selector.set_chance("social.resolved",0.3); boundary.rng.value = 0.3
	check(fire(boundary).status == "chance_failed" and boundary.service.chronicle.size() == 0, "Global30% boundary preserved")
	boundary.rng.value = 0.29999
	check(fire(boundary).status == "completed", "Global30% draw before selection")
	cleanup(boundary)

func outcomes_and_grammar() -> void:
	for memory_roll in [0.0,0.59999,0.6,1.0]:
		for anger_roll in [0.0,0.39999,0.4,1.0]:
			for wording in [0.0,1.0]:
				var f := quarrel_fixture(); var messages: Array = []
				f.service.resident_message.connect(func(id, person_name, text): messages.append([id,person_name,text]))
				f.service.executor.rng.values = [memory_roll,anger_roll] + ([0.0] if memory_roll < 0.6 else []) + [wording]
				check(fire(f).status == "completed", "Every combination is a successful event")
				var memory: bool = memory_roll < 0.6; var angry: bool = anger_roll < 0.4
				check(f.service.chronicle.size() == 1 and f.service.chronicle.entries()[0].text == "Иван поссорился с Анной.", "Mandatory objective grammatical chronicle")
				check(f.a.memories.size() == int(memory) and f.a.moodlets.find({"type":"angry"}).size() == int(angry) and messages.size() == int(angry), "Independent60% memory / shared40% moodlet and message")
				check(f.service.executor.rng.draws == 2 + int(angry) + int(memory), "One group draw; text choice only on success")
				if memory:
					var entry: Dictionary = f.a.memories.find()[0]
					check(entry.type == "unpleasant_interaction" and entry.target.id == "b" and entry.strength == 45 and entry.tags == ["negative","social","grudge"] and entry.provenance.kind == "experienced", "Standard generic negative memory")
				if angry:
					check(f.a.moodlets.get_entry("angry").expires_at_minute == 755 and f.a.moodlets.get_entry("angry").modifiers.is_empty(), "Standard inert angry120")
					check(messages[0] == ["a","Иван","Какая же Анна дура!" if wording == 0 else "Анна умеет испортить настроение!"], "Female other and exact actor sender")
				cleanup(f)
	var gender_fixture := quarrel_fixture(); gender_fixture.a.grammatical_gender = Traits.GrammaticalGender.FEMININE; gender_fixture.a.resident_name = "Анна"; gender_fixture.b.grammatical_gender = Traits.GrammaticalGender.MASCULINE; gender_fixture.b.resident_name = "Степан"
	var gender_messages: Array = []; gender_fixture.service.resident_message.connect(func(_id,_name,text): gender_messages.append(text))
	fire(gender_fixture)
	check(gender_fixture.service.chronicle.entries()[0].text == "Анна поссорилась со Степаном." and gender_messages == ["Какой же Степан болван!"], "Female actor, male other, со and gender agreement")
	cleanup(gender_fixture)

func cooldown_and_identity() -> void:
	var f := quarrel_fixture(); fire(f)
	var occurrence: Dictionary = f.service.last_occurrence(); var entry: Dictionary = f.a.moodlets.get_entry("angry"); var draws: int = f.service.executor.rng.draws
	f.clock.total_minutes += 1
	f.service.replay(occurrence.occurrence_id); f.service.executor.execute({},occurrence,636,f.a); f.service.executor.publish(occurrence.occurrence_id)
	check(f.service.chronicle.size() == 1 and f.service.executor.rng.draws == draws and f.a.moodlets.get_entry("angry") == entry, "Duplicate fact cannot refresh moodlet or re-record/reword")
	f.clock.total_minutes = 754
	check(fire(f).status == "no_match" and f.service.chronicle.size() == 1, "120-minute directed cooldown before boundary")
	f.clock.total_minutes = 755
	check(fire(f).status == "completed" and f.service.chronicle.size() == 2 and f.a.moodlets.find({"type":"angry"}).size() == 1 and f.a.moodlets.get_entry("angry").expires_at_minute == 875, "Exact boundary and new occurrence refresh one angry")
	var reverse: RefCounted = f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(reverse.confirmed_context().occurrence_id).status == "completed" and f.service.chronicle.size() == 3, "Opposite directed pair has independent cooldown")
	cleanup(f)

func atomic_refusals() -> void:
	for scenario in ["message","moodlet","chronicle","inactive"]:
		var f := quarrel_fixture(); var data := social_content(f); var definition: Dictionary = data.definitions[0]
		if scenario == "message": definition.effect_groups[0].effects[1].text = "{payload.missing}"
		if scenario == "moodlet": definition.effect_groups[0].effects[0].duration_minutes = -1
		if scenario == "chronicle": definition.text.chronicle = "{actor.missing}"
		load_content(f,data)
		if scenario == "inactive":
			f.service.executor.rng.on_draw = func(n):
				if n == 2: f.control.unregister_resident("b")
		var notices: Array = []
		f.service.chronicle.changed.connect(func(_id): notices.append("history"))
		f.a.memories.changed.connect(func(_id): notices.append("memory"))
		f.a.moodlets.changed.connect(func(_id): notices.append("moodlet"))
		f.service.resident_message.connect(func(_id,_name,_text): notices.append("chat"))
		check(fire(f).status != "completed" and f.service.chronicle.size() == 0 and f.a.memories.size() == 0 and f.a.moodlets.find({"type":"angry"}).is_empty() and notices.is_empty(), "No partial state or notices: " + scenario)
		check(f.service.cooldown_history().is_empty(), "Failed event has no cooldown")
		cleanup(f)

func live_action() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate(); root.add_child(world); world.game_time.set_process(false); world.game_logger.console_enabled = false
	var actor: Node = world.resident_runtimes[0]; var other: Node = world.resident_runtimes[1]
	MoodSetup.set_value(actor.data, 20); actor.data.set_traits([]); other.data.set_traits([])
	var definition: Dictionary = world.game_events.catalog.definitions_for("social.resolved").filter(func(d): return d.id == "social.rough_conversation")[0]
	check(world.game_events.catalog.load_data({"definitions":[definition]},world.game_events.facts), "Canonical event catalog")
	world.game_events.selector.rng = CountingRng.new(); world.game_events.executor.rng = SequenceRng.new(); world.social_events.rng = SocialRng.new(); world.social_events.rng.rolls = [0,0]
	var event: RefCounted = world.social_events.resolve(actor.data,other.data,SocialResult.Context.CONVERSATION)
	check(world.game_events.replay(event.confirmed_context().occurrence_id).status == "completed" and world.game_events.chronicle.size() == 1 and actor.data.moodlets.is_active("angry",world.game_time.total_minutes), "Canonical social→event→chronicle/angry pipeline")
	check(actor.moodlet_actions.collect_actions().any(func(action): return action.id == "VENT_ANGER"), "Quarrel unlocks existing VENT_ANGER with an available real tree")
	world.free(); await process_frame

func statistics() -> void:
	# Only the generic selection of consequences; no10k world instances.
	var f := quarrel_fixture(); var definition := definition_for(f,"social.rough_conversation")
	var rng := RandomNumberGenerator.new(); rng.seed = 78193; f.service.executor.rng = rng
	var counts := [0,0,0,0]
	for index in 10000:
		var choice: Dictionary = f.service.executor._choose(definition)
		var memory: bool = choice.items.any(func(item): return item.description.op == "memory.add")
		var angry: bool = choice.items.any(func(item): return item.description.op == "moodlet.add")
		check(choice.items.any(func(item): return item.description.op == "chat.say") == angry, "Shared bundle remains indivisible")
		counts[(0 if memory else 2) + (0 if angry else 1)] += 1
	check(absi(counts[0]-2400) < 200 and absi(counts[1]-3600) < 200 and absi(counts[2]-1600) < 200 and absi(counts[3]-2400) < 200, "Independent outcomes near24/36/16/24")
	print("Quarrel outcomes: ",counts)
	cleanup(f)
