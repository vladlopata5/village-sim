extends "res://tests/test_social_game_events.gd"
const MECHANICAL_GOLDEN := "res://tests/fixtures/social_mechanics_golden.json"
func _run() -> void:
	var traces: Array = []
	for trait_type in [-1]+Traits.Type.values():
		for seed_value in [0,1,7,91,12345]: traces.append(mechanical_trace(seed_value,trait_type))
	var snapshot := {"source_head":"c44d212a199d382c40aff48347cfa66c1e199f45","interactions":2100,"traces":traces}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			var file := FileAccess.open(arg.trim_prefix("--capture="),FileAccess.WRITE)
			file.store_string(JSON.stringify(snapshot,"  "))
			print("Captured pre-removal social mechanics:2100 interactions")
			quit(1 if failures else 0); return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MECHANICAL_GOLDEN))
	check(expected.source_head == snapshot.source_head and int(expected.interactions) == 2100, "Golden provenance and complete interaction count")
	check(expected.traces.size() == traces.size(), "Every pre-removal seed/trait case retained")
	for i in mini(expected.traces.size(),traces.size()):
		check(int(expected.traces[i].seed) == traces[i].seed and int(expected.traces[i].trait) == traces[i].trait and expected.traces[i].sha256 == traces[i].sha256, "Exact pre-removal rolls, reactions, directed opinions, RNG and confirmed payload: seed=%d trait=%d" % [traces[i].seed,traces[i].trait])
	await real_controllers()
	await diary_lifecycle()
	print("Social mechanics compatibility: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func mechanical_trace(seed_value: int, trait_type: int) -> Dictionary:
	var service := SocialService.new(); root.add_child(service)
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); service.clock = clock
	var a := Data.new("a","Анна",25); var b := Data.new("b","Борис",30)
	if trait_type >= 0: a.add_trait(trait_type)
	b.set_traits([Traits.Type.FOOLISH,Traits.Type.LAZY]); a.add_liked_trait(Traits.Type.FOOLISH)
	a.set_opinion("b",49); b.set_opinion("a",-50); a.opinion_rng.seed = 101; b.opinion_rng.seed = 102
	service.set_seed(seed_value)
	var contexts: Array = []; var trace: Array = []
	service.interaction_committed.connect(func(interaction): contexts.append(interaction.confirmed_context()))
	for i in 30:
		clock.total_minutes = 635+i
		var result: RefCounted = service.resolve(a,b,(i%3) as SocialResult.Context,["TALKING","WORKER"],["WORKING","VISITOR"],&"site")
		check(contexts.size() == i+1 and result.confirmed_context() == contexts.back(), "Exactly one immutable confirmed context per accepted interaction")
		trace.append([contexts.back(),a.get_opinion("b"),b.get_opinion("a"),str(service.rng.state),str(a.opinion_rng.state),str(b.opinion_rng.state)])
	service._publish_commits(); check(contexts.size() == 30, "Repeated drain does not duplicate confirmed interactions")
	service.free(); clock.free()
	return {"seed":seed_value,"trait":trait_type,"sha256":JSON.stringify(trace).sha256_text()}
func diary_lifecycle() -> void:
	var scene := Setup.make_scene(self); configure_world(scene)
	var actor: RefCounted = scene.resident_runtimes[0].data
	actor.add_diary_entry(Diary.new("временное",Diary.Importance.TEMPORARY,634))
	actor.add_diary_entry(Diary.new("ключевое",Diary.Importance.KEY,634))
	scene.social_events._on_phase_changed("Утро")
	check(actor.diary_entries.size() == 1 and actor.diary_entries[0].text == "ключевое", "General diary lifecycle survives removal of legacy stories")
	scene.free(); await process_frame
