extends "res://tests/test_social_game_events.gd"
const MoodSetup = preload("res://tests/mood_test_setup.gd")
const NEW_IDS := ["social.success_admiration", "social.warm_sympathy", "social.rough_conversation", "social.old_grudge", "social.character_contrast", "personal.skill_progress_advanced"]

func fixture(people: Array = []) -> Dictionary:
	var f := super.fixture(people)
	f.service._load_catalogs() # Production catalog, not the controlled historical fixture.
	return f

func definition_for(f: Dictionary, id: String) -> Dictionary:
	for trigger in ["social.resolved", "skill.raised"]:
		for definition in f.service.catalog.definitions_for(trigger):
			if definition.id == id: return definition
	return {}

func only(f: Dictionary, id: String) -> void:
	var definition := definition_for(f, id)
	check(not definition.is_empty(), "Production content contains " + id)
	load_content(f, {"definitions": [definition]})

func remember(f: Dictionary, changes: Dictionary = {}) -> void:
	var record := {"id": "old-chat", "type": "unpleasant_interaction", "topic": "conversation", "tags": ["negative", "social"], "target": {"kind": "resident", "id": "b"}, "text":"Событие из тестового сценария", "strength": 30, "permanent": false, "created_minute": 634, "source_occurrence_id": "fixture/previous-chat", "provenance": {"kind": "experienced"}}
	record.merge(changes, true)
	check(f.a.memories.add(record), "Existing memory prepared without inventing missing facts")

func prepare_story(f: Dictionary, id: String) -> void:
	match id:
		"social.success_admiration": prime(f); f.social.rng.rolls = [100, 50]
		"social.warm_sympathy": f.social.rng.rolls = [100, 100]
		"social.rough_conversation": f.social.rng.rolls = [0, 0]; MoodSetup.set_value(f.a, 20)
		"social.old_grudge": remember(f); f.social.rng.rolls = [0, 100]
		"social.character_contrast":
			f.a.add_trait(Traits.Type.SOCIABLE); f.b.add_trait(Traits.Type.INTROVERTED)
			f.social.rng.rolls = [50, 50]

func fire(f: Dictionary, context: int = SocialResult.Context.CONVERSATION) -> Dictionary:
	var source: RefCounted = f.social.resolve(f.a, f.b, context as SocialResult.Context)
	return f.service.replay(source.confirmed_context().occurrence_id)

func _run() -> void:
	positive_definitions()
	negative_definitions()
	competition()
	chances_and_cooldowns()
	actual_memory_chain()
	mechanical_catalog_parity()
	matrix()
	await actual_conversation()
	print("Event catalog content: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func positive_definitions() -> void:
	for id in NEW_IDS:
		var f:=fixture();prepare_story(f,id);only(f,id)
		var before: int=f.service.completed_events().size()
		var result: Dictionary
		if id=="personal.skill_progress_advanced":
			f.a.add_skill_xp(Skill.Type.GATHERING,1000);result=f.service.replay(f.service.last_occurrence().occurrence_id)
		else:result=fire(f)
		check(result.status=="completed" and result.definition_id==id and f.service.completed_events().size()==before+1,"Actual confirmed trigger selects "+id)
		check(result.main.id==("b" if id=="social.warm_sympathy" else "a"),"Declared main role unchanged")
		check(f.a.memories.size()==1,"One retained personal record, including reinforcement of old grudge")
		if id=="social.warm_sympathy":check(f.b.memories.size()==1 and f.a.mood==60 and f.b.mood==60,"Both canonical records and shared company")
		if id=="social.old_grudge":check(f.a.memories.find()[0].strength==40,"Old grudge reinforces chosen record by ten without appending")
		if id=="social.rough_conversation":check(f.a.memories.find()[0].strength==45 and f.a.moodlets.find({"type":"angry"}).size()==1,"Approved negative strength and unchanged anger group")
		cleanup(f)

func negative_definitions() -> void:
	var scenarios := {"social.success_admiration": ["no_pride", "expired", "negative_reaction"], "social.warm_sympathy": ["one_neutral"], "social.rough_conversation": ["one_neutral", "mood_high"], "social.old_grudge": ["missing", "wrong_target", "positive_memory", "zero_strength", "fresh", "hearsay", "positive_reaction"], "social.character_contrast": ["missing_trait", "reverse_traits", "work", "negative_reaction"], "personal.skill_progress_advanced": ["level_two"]}
	for id in scenarios:
		for scenario in scenarios[id]:
			var f := fixture()
			if id == "social.old_grudge":
				if scenario != "missing":
					var changes := {}
					if scenario == "wrong_target": changes.target = {"kind": "resident", "id": "someone_else"}
					if scenario == "positive_memory": changes.tags = ["positive"]
					if scenario == "zero_strength": changes.strength = 0
					if scenario == "fresh": changes.created_minute = 635
					if scenario == "hearsay": changes.provenance = {"kind": "hearsay", "reported_by": {"kind": "resident", "id": "reporter"}}
					remember(f, changes)
				if scenario == "positive_reaction": f.social.rng.rolls = [100, 100]
			elif id == "social.success_admiration":
				if scenario != "no_pride": prime(f)
				f.social.rng.rolls = [0, 100] if scenario == "negative_reaction" else [100, 50]
				if scenario == "expired": f.clock.total_minutes += 120
			else: prepare_story(f, id)
			if scenario == "mood_high": MoodSetup.set_value(f.a, 21)
			if scenario == "one_neutral": f.social.rng.rolls = [0 if id == "social.rough_conversation" else 100, 50]
			if scenario == "missing_trait": f.a.remove_trait(Traits.Type.SOCIABLE)
			if scenario == "reverse_traits":
				f.a.remove_trait(Traits.Type.SOCIABLE); f.b.remove_trait(Traits.Type.INTROVERTED)
				f.a.add_trait(Traits.Type.INTROVERTED); f.b.add_trait(Traits.Type.SOCIABLE)
			if scenario == "negative_reaction": f.social.rng.rolls = [0, 100]
			only(f, id)
			var before: int = f.service.completed_events().size()
			var diaries: int = f.a.memories.find().size() + f.b.memories.find().size()
			if id == "personal.skill_progress_advanced": f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 400)
			else: fire(f, SocialResult.Context.MEAL if scenario == "meal" else SocialResult.Context.WORK if scenario == "work" else SocialResult.Context.CONVERSATION)
			check(f.service.completed_events().size() == before and f.a.memories.find().size() + f.b.memories.find().size() == diaries, "Condition rejects " + id + "/" + scenario)
			cleanup(f)

func competition() -> void:
	for value in [0.0, 1.0]:
		var f := fixture(); prime(f); f.social.rng.rolls = [100, 100]; f.rng.value = value
		var before: int = f.service.completed_events().size()
		var result := fire(f)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == ["social.success_admiration", "social.warm_sympathy"] and result.definition_id == ("social.success_admiration" if value == 0 else "social.warm_sympathy"), "Multiple suitable new definitions use one weighted choice")
		check(f.service.completed_events().size() == before + 1 and selection.duplicate, "Adding definitions does not add events per opportunity")
		cleanup(f)
	for value in [0.0, 0.3, 0.6, 1.0]:
		var f := fixture(); prime(f); remember(f); remember(f, {"id": "another-old-chat"}); MoodSetup.set_value(f.a, 20); f.social.rng.rolls = [0, 0]; f.rng.value = value
		var result := fire(f)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == ["social.bad_conversation", "social.old_grudge", "social.rough_conversation", "social.success_envy"] and result.definition_id == selection.eligible[mini(int(value * 4),3)], "New memory/history stories compete with existing envy without extra memory tickets")
		cleanup(f)
	var skill_fixture := fixture()
	skill_fixture.a.add_skill_xp(Skill.Type.CONSTRUCTION, 400)
	var skill_result: Dictionary = skill_fixture.service.replay(skill_fixture.service.last_occurrence().occurrence_id)
	check(skill_result.definition_id == "personal.skill_progress", "Below threshold only the ordinary skill story is eligible")
	skill_fixture.rng.value = 1.0
	skill_fixture.a.add_skill_xp(Skill.Type.CONSTRUCTION, 600)
	skill_result = skill_fixture.service.replay(skill_fixture.service.last_occurrence().occurrence_id)
	var skill_selection: Dictionary = skill_fixture.service.selector.run(skill_fixture.service.last_occurrence())
	check(skill_selection.eligible == ["personal.skill_progress", "personal.skill_progress_advanced"] and skill_result.definition_id == "personal.skill_progress_advanced" and skill_fixture.a.memories.find().size() == 2, "Threshold achievement competes with ordinary story, never runs additionally")
	cleanup(skill_fixture)
	for xp in [1800, 3000]:
		var titled := fixture(); titled.rng.value = 1.0
		titled.a.add_skill_xp(Skill.Type.FORESTRY, xp)
		var result: Dictionary = titled.service.replay(titled.service.last_occurrence().occurrence_id)
		check(result.definition_id == "personal.skill_progress_advanced" and titled.a.memories.find().back().text.contains(Skill.rank_name(titled.a.get_skill_rank(Skill.Type.FORESTRY))), "Experienced and Master also qualify, using title-only text")
		cleanup(titled)
	for followup in ["social.success_admiration", "social.success_envy"]:
		var full := fixture(); full.rng.value = 1.0
		full.b.add_skill_xp(Skill.Type.LOGISTICS, 1000)
		check(full.b.moodlets.find()[0].context._event.definition_id == "personal.skill_progress_advanced", "Real advanced story supplies a valid pride origin")
		only(full, followup); full.social.rng.rolls = [100 if followup == "social.success_admiration" else 0, 50]
		check(fire(full).definition_id == followup and full.a.moodlets.find()[0].context.skill == "logistics", "Both admiration and existing envy recognize pride from the new achievement")
		cleanup(full)

func chances_and_cooldowns() -> void:
	for id in ["social.success_admiration", "social.warm_sympathy", "social.rough_conversation"]:
		for roll in [0.0, 1.0]:
			var f := fixture(); prepare_story(f, id); only(f, id); f.service.executor.rng.values = [roll, roll, roll, roll, roll, roll, roll]
			var result := fire(f)
			check(result.status == "completed", "Narrative succeeds independently of optional consequence")
			if id == "social.warm_sympathy": check(f.a.memories.find().size() == (1 if roll == 0 else 0) and f.b.memories.find().size() == (1 if roll == 0 else 0), "Both optional diaries use their own JSON probabilities")
			else: check(f.a.memories.size() + f.a.moodlets.find({"type":"admiration"}).size() + f.a.moodlets.find({"type":"angry"}).size() == (2 if roll == 0 else 0), "New content consequence can pass or fail without suppressing the diary")
			var draws: int = f.service.executor.rng.draws
			var token: String = f.service.last_occurrence().occurrence_id
			var diaries: int = f.a.memories.find().size() + f.b.memories.find().size()
			f.service.replay(token)
			check(f.service.executor.rng.draws == draws and f.a.memories.find().size() + f.b.memories.find().size() == diaries, "Replay creates no additional diaries or random checks")
			cleanup(f)
	for id in NEW_IDS:
		if id.begins_with("personal."): continue
		var f := fixture(); prepare_story(f, id); only(f, id)
		check(fire(f).status == "completed", "First local opportunity allowed")
		var diaries: int = f.a.memories.find().size() + f.b.memories.find().size()
		check(fire(f).status == "no_match" and f.a.memories.find().size() + f.b.memories.find().size() == diaries, "Local cooldown blocks repeating " + id)
		cleanup(f)
	var boundary := fixture(); prepare_story(boundary, "social.warm_sympathy")
	var minutes: int = int(definition_for(boundary, "social.warm_sympathy").cooldown.minutes)
	only(boundary, "social.warm_sympathy"); fire(boundary)
	boundary.clock.total_minutes += minutes - 1
	check(fire(boundary).status == "no_match", "Local cooldown remains active immediately before expiry")
	boundary.clock.total_minutes += 1
	check(fire(boundary).status == "completed", "Local cooldown permits the exact expiry boundary")
	cleanup(boundary)

func actual_memory_chain() -> void:
	var f := fixture(); MoodSetup.set_value(f.a, 20); f.social.rng.rolls = [0, 0]
	# Pick the intended existing story from the expanded weighted catalog.
	f.rng.value=1.0
	check(fire(f).definition_id == "social.rough_conversation" and f.a.memories.size() == 1, "Actual bad conversation stores a real negative memory")
	f.clock.total_minutes += 1; f.rng.value=.75
	check(fire(f).definition_id == "social.old_grudge" and f.a.memories.size() == 1 and f.a.get_opinion("b") == -2 and f.b.get_opinion("a") == -2, "Next unpleasant interaction can recall the existing memory without reinforcement or doubled relations")
	cleanup(f)

func matrix() -> void:
	for context in SocialResult.Context.values():
		for first in [0, 50, 100]:
			for second in [0, 50, 100]:
				var f := fixture()
				if second != 0: prime(f, f.b, context as Skill.Type)
				if first < 0: remember(f)
				f.a.add_trait(Traits.Type.SOCIABLE); f.b.add_trait(Traits.Type.INTROVERTED)
				f.social.rng.rolls = [first, second]
				var before: int = f.service.completed_events().size()
				var result: RefCounted = f.social.resolve(f.a, f.b, context)
				var after: int = f.service.completed_events().size()
				check(after - before in [0, 1] and f.a.get_opinion("b") == result.opinion_delta_1 and f.b.get_opinion("a") == result.opinion_delta_2, "Full catalog matrix keeps at most one event and exactly the legacy relations")
				var draws: int = f.rng.draws; var effect_draws: int = f.service.executor.rng.draws
				f.social.interaction_committed.emit(result)
				check(f.rng.draws == draws and f.service.executor.rng.draws == effect_draws and f.service.completed_events().size() == after, "Full catalog matrix deduplicates an actual confirmed result")
				cleanup(f)

func mechanical_catalog_parity() -> void:
	var traces: Array = []
	for enabled_followup in [false, true]:
		var f := fixture(); prime(f)
		f.social.rng = RandomNumberGenerator.new(); f.social.set_seed(77)
		f.service.selector.set_chance("social.resolved", 1 if enabled_followup else 0)
		var events: Array = []; var diaries: Array = []
		var starts := [0, 0]
		# This legacy notification precedes the generic post-commit hook. Capture
		# its actual diary additions, not a text-based guess about their origin.
		f.social.event_resolved.connect(func(result):
			events.append([result.roll_1, result.roll_2, result.reaction_1, result.reaction_2, result.opinion_delta_1, result.opinion_delta_2, result.confirmed_context()])
			var additions: Array = []
			for index in 2:
				var person: RefCounted = f.a if index == 0 else f.b
				additions.append(person.memories.find().slice(starts[index]).map(func(entry): return [entry.text, entry.importance, entry.created_minute]))
			diaries.append(additions))
		for i in 30:
			starts[0] = f.a.memories.find().size(); starts[1] = f.b.memories.find().size()
			f.clock.total_minutes = 635 + i
			# Match mood inputs to isolate story RNG and direct opinion changes.
			MoodSetup.set_value(f.a, 50.0)
			MoodSetup.set_value(f.b, 50.0)
			f.social.resolve(f.a, f.b, (i % 3) as SocialResult.Context)
		traces.append([events, diaries, f.social.rng.state, f.a.get_opinion("b"), f.b.get_opinion("a")])
		check(not enabled_followup or f.service.completed_events().size() > 1, "Parity scenario actually executes new content")
		cleanup(f)
	check(traces[0] == traces[1], "With equal mood, the full catalog preserves exact reactions, confirmed facts, lack of direct diary writes, relations and RNG state")

	var feedback := fixture()
	only(feedback, "social.warm_sympathy")
	feedback.social.rng.rolls = [100, 100]
	feedback.social.resolve(feedback.a, feedback.b, SocialResult.Context.CONVERSATION)
	check(feedback.a.mood == 60.0 and feedback.a.get_opinion("b") == 1, "Existing story supplies mood independently of directed opinion")
	feedback.social.rng.rolls = [73, 50]
	var next: RefCounted = feedback.social.resolve(feedback.a, feedback.b, SocialResult.Context.CONVERSATION)
	check(next.attitude_1_to_2 == 11.0 and next.reaction_1 == SocialResult.Reaction.POSITIVE and SocialService.reaction(1.0, 73.0) == SocialResult.Reaction.NEUTRAL, "Same roll can change reaction through mood from an existing story")
	cleanup(feedback)

func actual_conversation() -> void:
	var scene := Setup.make_scene(self); configure_world(scene)
	scene.social_events.rng.rolls = [100, 100]
	var actor: Node = scene.resident_runtimes[1]; var target: Node = scene.resident_runtimes[3]
	var contexts: Dictionary = {}; var completed: Array = []
	scene.social_events.interaction_committed.connect(func(result):
		var context: Dictionary = result.confirmed_context()
		contexts[context.occurrence_id] = context)
	scene.game_events.event_completed.connect(func(result): completed.append(result))
	actor.data.get_need(Need.Type.SOCIAL).value = 100; target.data.get_need(Need.Type.SOCIAL).value = 100
	check(actor.social.try_social_at(StringName(target.data.id), 8000), "Real controller begins a conversation with the production catalog")
	actor.view._process(100)
	check(contexts.size() == 2 and completed.size() == 1 and scene.social_events.rng.chances == 2, "Two real attempts remain; symmetric story cooldown blocks the second direction")
	for result in completed: check(result.definition_id == "social.warm_sympathy" and result.main.id == contexts[result.occurrence_id].other.id, "Production sympathy resolves the actual other participant as main")
	check(actor.data.memories.find().size() == 1 and target.data.memories.find().size() == 1 and actor.data.memories.size() == 1 and target.data.memories.size() == 1 and actor.data.moodlets.size() == 2 and actor.data.moodlets.get_entry("lonely").size() > 0 and actor.data.moodlets.find({"type":"pleasant_company"}).size() == 1, "One completed story has independent diaries/memories and company alongside the need state")
	scene.free(); await process_frame
