extends "res://tests/test_social_game_events.gd"
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
	var record := {"id": "old-chat", "type": "unpleasant_interaction", "topic": "conversation", "tags": ["negative", "social"], "target": {"kind": "resident", "id": "b"}, "strength": 30, "permanent": false, "created_minute": 634, "source_occurrence_id": "fixture/previous-chat", "provenance": {"kind": "experienced"}}
	record.merge(changes, true)
	check(f.a.memories.add(record), "Existing memory prepared without inventing missing facts")

func prepare_story(f: Dictionary, id: String) -> void:
	match id:
		"social.success_admiration": prime(f); f.social.rng.rolls = [100, 0]
		"social.warm_sympathy": f.social.rng.rolls = [100, 100]
		"social.rough_conversation": f.social.rng.rolls = [-100, -100]
		"social.old_grudge": remember(f); f.social.rng.rolls = [-100, 100]
		"social.character_contrast":
			f.a.add_trait(Traits.Type.SOCIABLE); f.b.add_trait(Traits.Type.INTROVERTED)
			f.social.rng.rolls = [0, 0]

func fire(f: Dictionary, context: int = SocialResult.Context.CONVERSATION) -> Dictionary:
	var source: RefCounted = f.social.resolve(f.a, f.b, context as SocialResult.Context)
	return f.service.replay(source.confirmed_context().occurrence_id)

func _run() -> void:
	positive_definitions()
	negative_definitions()
	competition()
	chances_and_cooldowns()
	actual_memory_chain()
	legacy_catalog_parity()
	matrix()
	await actual_conversation()
	print("Event catalog content: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func positive_definitions() -> void:
	for id in NEW_IDS:
		var f := fixture()
		check(f.service.catalog.definitions_for("social.resolved").size() + f.service.catalog.definitions_for("skill.raised").size() == 8, "The R2-B6 trigger buckets retain eight definitions, including exactly six additions")
		prepare_story(f, id)
		only(f, id)
		var before: int = f.service.completed_events().size()
		var result: Dictionary
		if id == "personal.skill_progress_advanced":
			f.a.add_skill_xp(Skill.Type.GATHERING, 30)
			result = f.service.replay(f.service.last_occurrence().occurrence_id)
		else: result = fire(f)
		check(result.status == "completed" and result.definition_id == id and f.service.completed_events().size() == before + 1, "One real confirmed trigger selects " + id)
		check(result.main.id == ("b" if id == "social.warm_sympathy" else "a"), "JSON main role for " + id)
		if id == "social.warm_sympathy":
			check(f.b.diary_entries.size() == 1 and f.a.diary_entries.size() == 1 and result.secondary_diary, "Sympathy: distinct main and optional actor diaries")
		else: check(f.a.diary_entries.size() == 1, "Exactly one mandatory diary for " + id)
		match id:
			"social.success_admiration": check(f.a.moodlets.find()[0].type == "admiration" and f.a.memories.size() == 0 and f.a.moodlets.find()[0].context.skill == "gathering", "Admiration is a skill-bound moodlet, no artificial memory")
			"social.rough_conversation": check(f.a.memories.find()[0].target.id == "b" and f.a.memories.find()[0].tags.has("negative") and f.a.moodlets.size() == 0, "Rough talk creates only the optional negative memory")
			"social.old_grudge": check(f.a.memories.size() == 1 and f.a.memories.find()[0].strength == 30 and f.a.moodlets.size() == 0, "Existing grudge affects selection without reinforcement or extra consequences")
			"personal.skill_progress_advanced": check(f.a.moodlets.find()[0].type == "pride" and f.a.moodlets.find()[0].context.skill == "gathering" and f.a.memories.size() == 0, "Advanced achievement has pride only, from the actual skill")
			_: check(f.a.memories.size() == 0 and f.b.memories.size() == 0 and f.a.moodlets.size() == 0 and f.b.moodlets.size() == 0, "Narrative-only event has no mechanical filler")
		cleanup(f)

func negative_definitions() -> void:
	var scenarios := {"social.success_admiration": ["no_pride", "expired", "negative_reaction"], "social.warm_sympathy": ["one_neutral"], "social.rough_conversation": ["one_neutral", "meal"], "social.old_grudge": ["missing", "wrong_target", "positive_memory", "zero_strength", "fresh", "hearsay", "positive_reaction"], "social.character_contrast": ["missing_trait", "reverse_traits", "work", "negative_reaction"], "personal.skill_progress_advanced": ["level_two"]}
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
				f.social.rng.rolls = [-100, 100] if scenario == "negative_reaction" else [100, 0]
				if scenario == "expired": f.clock.total_minutes += 120
			else: prepare_story(f, id)
			if scenario == "one_neutral": f.social.rng.rolls = [-100 if id == "social.rough_conversation" else 100, 0]
			if scenario == "missing_trait": f.a.remove_trait(Traits.Type.SOCIABLE)
			if scenario == "reverse_traits":
				f.a.remove_trait(Traits.Type.SOCIABLE); f.b.remove_trait(Traits.Type.INTROVERTED)
				f.a.add_trait(Traits.Type.INTROVERTED); f.b.add_trait(Traits.Type.SOCIABLE)
			if scenario == "negative_reaction": f.social.rng.rolls = [-100, 100]
			only(f, id)
			var before: int = f.service.completed_events().size()
			var diaries: int = f.a.diary_entries.size() + f.b.diary_entries.size()
			if id == "personal.skill_progress_advanced": f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 20)
			else: fire(f, SocialResult.Context.MEAL if scenario == "meal" else SocialResult.Context.WORK if scenario == "work" else SocialResult.Context.CONVERSATION)
			check(f.service.completed_events().size() == before and f.a.diary_entries.size() + f.b.diary_entries.size() == diaries, "Condition rejects " + id + "/" + scenario)
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
	for value in [0.0, 0.5, 1.0]:
		var f := fixture(); prime(f); remember(f); remember(f, {"id": "another-old-chat"}); f.social.rng.rolls = [-100, -100]; f.rng.value = value
		var result := fire(f)
		var selection: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selection.eligible == ["social.old_grudge", "social.rough_conversation", "social.success_envy"] and result.definition_id == selection.eligible[int(value * 2)], "New memory/history stories compete with existing envy without extra memory tickets")
		cleanup(f)
	var skill_fixture := fixture()
	skill_fixture.a.add_skill_xp(Skill.Type.CONSTRUCTION, 20)
	var skill_result: Dictionary = skill_fixture.service.replay(skill_fixture.service.last_occurrence().occurrence_id)
	check(skill_result.definition_id == "personal.skill_progress", "Below threshold only the ordinary skill story is eligible")
	skill_fixture.rng.value = 1.0
	skill_fixture.a.add_skill_xp(Skill.Type.CONSTRUCTION, 10)
	skill_result = skill_fixture.service.replay(skill_fixture.service.last_occurrence().occurrence_id)
	var skill_selection: Dictionary = skill_fixture.service.selector.run(skill_fixture.service.last_occurrence())
	check(skill_selection.eligible == ["personal.skill_progress", "personal.skill_progress_advanced"] and skill_result.definition_id == "personal.skill_progress_advanced" and skill_fixture.a.diary_entries.size() == 2, "Threshold achievement competes with ordinary story, never runs additionally")
	cleanup(skill_fixture)
	for followup in ["social.success_admiration", "social.success_envy"]:
		var full := fixture(); full.rng.value = 1.0
		full.b.add_skill_xp(Skill.Type.LOGISTICS, 30)
		check(full.b.moodlets.find()[0].context._event.definition_id == "personal.skill_progress_advanced", "Real advanced story supplies a valid pride origin")
		only(full, followup); full.social.rng.rolls = [100 if followup == "social.success_admiration" else -100, 0]
		check(fire(full).definition_id == followup and full.a.moodlets.find()[0].context.skill == "logistics", "Both admiration and existing envy recognize pride from the new achievement")
		cleanup(full)

func chances_and_cooldowns() -> void:
	for id in ["social.success_admiration", "social.warm_sympathy", "social.rough_conversation"]:
		for roll in [0.0, 1.0]:
			var f := fixture(); prepare_story(f, id); only(f, id); f.service.executor.rng.values = [roll]
			var result := fire(f)
			check(result.status == "completed", "Narrative succeeds independently of optional consequence")
			if id == "social.warm_sympathy": check(f.a.diary_entries.size() == (1 if roll == 0 else 0) and f.b.diary_entries.size() == 1, "Optional second diary uses its own JSON probability")
			else: check(f.a.memories.size() + f.a.moodlets.size() == (1 if roll == 0 else 0), "New content consequence can pass or fail without suppressing the diary")
			var draws: int = f.service.executor.rng.draws
			var token: String = f.service.last_occurrence().occurrence_id
			var diaries: int = f.a.diary_entries.size() + f.b.diary_entries.size()
			f.service.replay(token)
			check(f.service.executor.rng.draws == draws and f.a.diary_entries.size() + f.b.diary_entries.size() == diaries, "Replay creates no additional diaries or random checks")
			cleanup(f)
	for id in NEW_IDS:
		if id.begins_with("personal."): continue
		var f := fixture(); prepare_story(f, id); only(f, id)
		check(fire(f).status == "completed", "First local opportunity allowed")
		var diaries: int = f.a.diary_entries.size() + f.b.diary_entries.size()
		check(fire(f).status == "no_match" and f.a.diary_entries.size() + f.b.diary_entries.size() == diaries, "Local cooldown blocks repeating " + id)
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
	var f := fixture(); f.social.rng.rolls = [-100, -100]
	check(fire(f).definition_id == "social.rough_conversation" and f.a.memories.size() == 1, "Actual bad conversation stores a real negative memory")
	f.clock.total_minutes += 1
	check(fire(f).definition_id == "social.old_grudge" and f.a.memories.size() == 1 and f.a.get_opinion("b") == -2 and f.b.get_opinion("a") == -2, "Next unpleasant interaction can recall the existing memory without reinforcement or doubled relations")
	cleanup(f)

func matrix() -> void:
	for context in SocialResult.Context.values():
		for first in [-100, 0, 100]:
			for second in [-100, 0, 100]:
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

func legacy_catalog_parity() -> void:
	var traces: Array = []
	for enabled_followup in [false, true]:
		var f := fixture(); prime(f)
		f.social.entries = JSON.parse_string(FileAccess.get_file_as_string("res://assets/social_events/entries.json")).map(func(raw): return preload("res://scripts/social_narrative_entry.gd").new(raw))
		f.social.rng = RandomNumberGenerator.new(); f.social.set_seed(77)
		f.service.selector.set_chance("social.resolved", 1 if enabled_followup else 0)
		var events: Array = []; var feed: Array = []; var diaries: Array = []
		var starts := [0, 0]
		f.social.feed_message.connect(func(text): feed.append(text))
		# This legacy notification precedes the generic post-commit hook. Capture
		# its actual diary additions, not a text-based guess about their origin.
		f.social.event_resolved.connect(func(result):
			events.append([result.roll_1, result.roll_2, result.reaction_1, result.reaction_2, result.opinion_delta_1, result.opinion_delta_2, result.selected_entry_id, result.reversed_orientation])
			var additions: Array = []
			for index in 2:
				var person: RefCounted = f.a if index == 0 else f.b
				additions.append(person.diary_entries.slice(starts[index]).map(func(entry): return [entry.text, entry.importance, entry.created_minute]))
			diaries.append(additions))
		for i in 30:
			starts[0] = f.a.diary_entries.size(); starts[1] = f.b.diary_entries.size()
			f.clock.total_minutes = 635 + i
			f.social.resolve(f.a, f.b, (i % 3) as SocialResult.Context)
		traces.append([events, feed, diaries, f.social.rng.state, f.social.narrative_rng.state, f.a.get_opinion("b"), f.b.get_opinion("a")])
		check(not enabled_followup or f.service.completed_events().size() > 1, "Parity scenario actually executes new content")
		cleanup(f)
	check(traces[0] == traces[1], "Full enabled catalog preserves exact legacy reactions, feed, diary attempts, relations and RNG states")

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
	check(contexts.size() == 2 and completed.size() == 2 and scene.social_events.rng.chances == 2, "Two old start opportunities still produce at most two universal events")
	for result in completed: check(result.definition_id == "social.warm_sympathy" and result.main.id == contexts[result.occurrence_id].other.id, "Production sympathy resolves the actual other participant as main")
	check(actor.data.diary_entries.size() == 2 and target.data.diary_entries.size() == 2 and actor.data.memories.size() == 0 and actor.data.moodlets.size() == 0, "Two distinct narrative events have main/secondary diaries without mechanical filler")
	scene.free(); await process_frame
