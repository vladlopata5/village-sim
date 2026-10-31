extends "res://tests/test_social_game_events.gd"
const Presenter = preload("res://scripts/social_narrative_presenter.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
var runtime_feed: Array = []

func _run() -> void:
	mechanical_parity()
	toggle_and_fallback()
	nested_commits()
	await real_controllers()
	check(runtime_feed.is_empty(), "Actual conversation, meal and builder paths emit no legacy messages when disabled")
	await diary_cleanup()
	print("Social narrative separation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func legacy_entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/social_events/entries.json")).map(func(raw): return Entry.new(raw))

func mechanical_parity() -> void:
	for actor_trait in [-1,Traits.Type.HOTHEADED,Traits.Type.CALM,Traits.Type.SOCIABLE]:
		for seed_value in [17,77,901]:
			var traces: Array = []
			for enabled in [true,false]:
				var f := fixture(); prime(f)
				if actor_trait >= 0: f.a.add_trait(actor_trait)
				f.a.opinion_rng.seed = 101; f.b.opinion_rng.seed = 102
				f.social.entries = legacy_entries(); f.social.diary_chance = 1
				f.social.rng = RandomNumberGenerator.new()
				f.social.set_seed(seed_value); f.social.legacy_stories_enabled = enabled
				var presentation_state: int = f.social.narrative_rng.state
				var feed: Array = []; var contexts: Array = []; var completed: Array = []
				f.social.feed_message.connect(func(text): feed.append(text))
				f.social.interaction_committed.connect(func(interaction): contexts.append(interaction.confirmed_context()))
				f.service.event_completed.connect(func(result): completed.append(result))
				for index in 60:
					var result: RefCounted = f.social.resolve(f.a,f.b,(index%3) as SocialResult.Context,["EATING","WORKING","WORKER","TALKING"],["WORKING","WORKER","VISITOR","TALKING"],&"site")
					if not enabled: check(result.selected_entry_id.is_empty() and not result.reversed_orientation, "Disabled narrative never selects a legacy entry or orientation")
				check(contexts.size() == 60 and completed.size() > 0, "Every interaction publishes one fact and real universal JSON follow-ups still execute")
				check(not feed.is_empty() if enabled else feed.is_empty(), "Switch controls legacy feed, including generic presentation")
				check(f.social.narrative_rng.state != presentation_state if enabled else f.social.narrative_rng.state == presentation_state, "Only enabled legacy presentation consumes its own RNG")
				if not enabled:
					check(f.a.diary_entries.size() == completed.size() and f.b.diary_entries.size() == 1, "Disabled legacy writes no diaries; mandatory EventEngine diaries and original skill diary remain")
				traces.append([contexts,completed,f.a.memories.find(),f.a.moodlets.find(),f.a.get_opinion("b"),f.b.get_opinion("a"),f.social.rng.state,f.a.opinion_rng.state,f.b.opinion_rng.state,f.service.executor.rng.draws,f.rng.draws])
				cleanup(f)
			check(traces[0] == traces[1], "Enabled/disabled parity of complete social.resolved payload, universal events, mechanics and RNG: trait=%d seed=%d" % [actor_trait,seed_value])

func toggle_and_fallback() -> void:
	var f := fixture()
	check(f.social.legacy_stories_enabled and f.social.narrative is Presenter and f.social.entries == f.social.narrative.entries, "Legacy presentation remains enabled by default, with one data owner")
	f.service.selector.set_chance("social.resolved",0)
	var story := Entry.new({"id":"controlled","feed_text_a":"%A% говорит с %B%","diary_text_a":"Дневник %A%","diary_importance":1})
	f.social.entries = [story]; f.social.diary_chance = 1
	f.social.rng = RandomNumberGenerator.new()
	f.social.narrative_rng = RandomNumberGenerator.new(); f.social.set_seed(42)
	var feed: Array = []; var contexts: Array = []
	f.social.feed_message.connect(func(text): feed.append(text))
	f.social.interaction_committed.connect(func(interaction): contexts.append(interaction.confirmed_context()))
	f.social.legacy_stories_enabled = false
	var before: int = f.social.narrative_rng.state
	var result: RefCounted = f.social.resolve(f.a,f.b,SocialResult.Context.WORK)
	check(feed.is_empty() and f.a.diary_entries.is_empty() and f.b.diary_entries.is_empty() and f.social.narrative_rng.state == before and contexts.size() == 1, "Disabled stories suppress feed/diary without suppressing mechanics or fact")
	var opinion: int = f.a.get_opinion("b")
	check(f.social.present(result,f.a,f.b,[],[]) == {"feed":0,"diary":0} and f.a.get_opinion("b") == opinion and contexts.size() == 1, "Disabled direct presentation is a harmless no-op")
	f.social.legacy_stories_enabled = true
	f.social.resolve(f.a,f.b,SocialResult.Context.WORK)
	check(feed.size() == 1 and f.a.diary_entries.size()+f.b.diary_entries.size() == 1 and f.social.narrative_rng.state != before and contexts.size() == 2, "Re-enabling resumes the old presenter through compatibility accessors")
	f.social.entries = []; f.social.legacy_stories_enabled = false
	f.social.resolve(f.a,f.b,SocialResult.Context.MEAL)
	check(feed.size() == 1 and contexts.size() == 3, "Empty entries cannot bypass disabled flag through old fallback messages")
	f.social.legacy_stories_enabled = true
	f.social.resolve(f.a,f.b,SocialResult.Context.MEAL)
	check(feed.size() == 3 and contexts.size() == 4, "Enabled empty catalog retains exactly two old fallback messages")
	f.social._publish_commits()
	check(contexts.size() == 4, "Draining the empty queue never republishes interactions")
	cleanup(f)

func nested_commits() -> void:
	var f := fixture(); prime(f); f.social.legacy_stories_enabled = false
	var nested := [false]; var facts: Array = []; var presented: Array = []
	var callback := func(_other):
		if not nested[0]:
			nested[0] = true
			f.social.resolve(f.a,f.b,SocialResult.Context.MEAL)
	f.a.relationship_changed.connect(callback)
	f.social.feed_message.connect(func(text): presented.append(text))
	f.social.interaction_committed.connect(func(result): facts.append([int(JSON.parse_string(result.confirmed_context().occurrence_id)[1]),f.a.get_opinion("b"),f.b.get_opinion("a")]))
	f.social.resolve(f.a,f.b,SocialResult.Context.WORK)
	f.a.relationship_changed.disconnect(callback)
	check(facts == [[2,-2,2],[1,-2,2]] and presented.is_empty() and social_count(f) == 2 and f.social.rng.cursor == 4, "Nested callbacks preserve original commit order and exactly one follow-up per interaction without legacy")
	var count: int = f.a.diary_entries.size(); var draws: int = f.service.executor.rng.draws
	f.social._publish_commits(); f.service.replay(f.service.last_occurrence().occurrence_id)
	check(facts.size() == 2 and f.a.diary_entries.size() == count and f.service.executor.rng.draws == draws, "Replay and repeated queue drain do not duplicate reactions or universal consequences")
	cleanup(f)

func configure_world(scene: Node) -> void:
	super.configure_world(scene)
	scene.social_events.legacy_stories_enabled = false
	scene.social_events.diary_chance = 1 # Would make old diary writes visible if the gate were bypassed.
	scene.social_events.feed_message.connect(func(text): runtime_feed.append(text))

func diary_cleanup() -> void:
	var scene := Setup.make_scene(self); configure_world(scene)
	var actor: RefCounted = scene.resident_runtimes[0].data
	actor.add_diary_entry(Diary.new("старое временное",Diary.Importance.TEMPORARY,634))
	actor.add_diary_entry(Diary.new("старое ключевое",Diary.Importance.KEY,634))
	scene.social_events._on_phase_changed("Утро")
	check(actor.diary_entries.size() == 1 and actor.diary_entries[0].text == "старое ключевое", "Disabling future old stories does not suspend existing diary lifecycle")
	scene.free(); await process_frame
