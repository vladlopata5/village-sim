extends "res://tests/test_event_effects.gd"
const SocialService = preload("res://scripts/social_event_service.gd")
const SocialResult = preload("res://scripts/social_event.gd")
const PairFacts = preload("res://scripts/resident_event_facts.gd")
const Traits = preload("res://scripts/trait_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Need = preload("res://scripts/need_type.gd")
class LegacyRng extends RefCounted:
	var probability := 0.0
	var rolls: Array = [-100, 100]
	var cursor := 0
	var chances := 0
	func randf() -> float:
		chances += 1
		return probability
	func randi_range(low: int, high: int) -> int:
		if low != -100 or high != 100: return low
		var roll: int = rolls[cursor % rolls.size()]
		cursor += 1
		return roll
class PairRegistry extends PlayerRegistry:
	var population_reads := 0
	func get_residents() -> Array:
		population_reads += 1
		return super.get_residents()

func fixture(people: Array = []) -> Dictionary:
	if people.is_empty(): people = [Data.new("a", "Марина", 25), Data.new("b", "Степан", 30)]
	var control := PairRegistry.new()
	for person in people: control.register_resident(person)
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.total_minutes = 635
	var service := Service.new(); root.add_child(service)
	service.setup(control, clock, func(person): return not person.id.begins_with("inactive"))
	# Keep the R2-B5 regression's controlled two-definition catalog. New content
	# competes in production and in test_event_catalog_content, not in this fixture.
	var historical: Array = []
	for trigger in ["skill.raised", "social.resolved"]:
		historical.append_array(service.catalog.definitions_for(trigger).filter(func(definition): return definition.id in ["personal.skill_progress", "social.success_envy"]))
	service.catalog.load_data({"definitions": historical}, service.facts)
	service.selector.set_chance("social.resolved", 1)
	service.selector.rng = CountingRng.new(); service.executor.rng = SequenceRng.new()
	var social := SocialService.new(); root.add_child(social); social.clock = clock; social.rng = LegacyRng.new()
	service.attach_social(social)
	return {"control": control, "clock": clock, "service": service, "social": social, "rng": service.selector.rng, "a": people[0], "b": people.back()}

func cleanup(f: Dictionary) -> void:
	f.social.free()
	super.cleanup(f)

func prime(f: Dictionary, person: RefCounted = null, skill: int = Skill.Type.GATHERING) -> void:
	if person == null: person = f.b
	person.add_skill_xp(skill as Skill.Type, 400) # Actual skill.raised produces the real pride context.
	f.service.selector.rng = CountingRng.new(); f.rng = f.service.selector.rng
	f.service.executor.rng = SequenceRng.new()

func social_content(f: Dictionary) -> Dictionary:
	return {"definitions": f.service.catalog.definitions_for("social.resolved")}

func social_count(f: Dictionary) -> int:
	return f.service.completed_events().values().filter(func(row): return row.definition_id == "social.success_envy").size()

func _run() -> void:
	confirmed_results()
	hotheaded_result()
	calm_result()
	conditions()
	facts_and_reverse_main()
	compatibility_and_identity()
	json_facts_and_guards()
	await real_controllers()
	print("Social game events: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func hotheaded_result() -> void:
	var f := fixture(); prime(f)
	f.a.add_trait(Traits.Type.HOTHEADED)
	var rounding := CountingRng.new(); f.a.opinion_rng = rounding
	var result: RefCounted = f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
	var payload: Dictionary = result.confirmed_context().payload
	check(payload.opinion_delta_1 == -1 and payload.applied_delta_1 == -2 and payload.opinion_after_1 == -2 and f.a.get_opinion("b") == -2 and f.b.get_opinion("a") == 1 and rounding.draws == 1, "HOTHEADED commits exactly one rounded directed change before JSON follow-up")
	check(social_count(f) == 1 and f.a.memories.size() == 1 and f.a.moodlets.size() == 1 and f.a.memories.find().size() == 1, "Existing event effects apply once without scaling opinion again")
	var event_draws: int = f.rng.draws; var effect_draws: int = f.service.executor.rng.draws
	f.social.interaction_committed.emit(result)
	check(social_count(f) == 1 and rounding.draws == 1 and f.rng.draws == event_draws and f.service.executor.rng.draws == effect_draws and f.a.get_opinion("b") == -2, "Duplicate event notification neither rerolls nor changes opinion")
	cleanup(f)

func calm_result() -> void:
	for draw in [0.0, 0.9]:
		var f := fixture(); prime(f)
		f.a.add_trait(Traits.Type.CALM)
		var rounding := SequenceRng.new(); rounding.values = [draw]; f.a.opinion_rng = rounding
		var result: RefCounted = f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
		var payload: Dictionary = result.confirmed_context().payload
		var expected := -1 if draw < 0.75 else 0
		check(payload.opinion_delta_1 == -1 and payload.applied_delta_1 == expected and payload.opinion_before_1 == 0 and payload.opinion_after_1 == expected and f.a.get_opinion("b") == expected and f.b.get_opinion("a") == 1 and rounding.draws == 1, "CALM JSON context keeps zero outcome and independent reverse reaction")
		check(social_count(f) == 1 and f.a.memories.size() == 1 and f.a.memories.find().size() == 1, "Original event conditions still use social reaction when opinion rounds to zero")
		var event_draws: int = f.rng.draws; var effect_draws: int = f.service.executor.rng.draws
		f.social.interaction_committed.emit(result)
		check(social_count(f) == 1 and rounding.draws == 1 and f.rng.draws == event_draws and f.service.executor.rng.draws == effect_draws and f.a.get_opinion("b") == expected, "Duplicate notification never rerolls CALM zero/nonzero outcomes")
		cleanup(f)

func confirmed_results() -> void:
	for context in SocialResult.Context.values():
		var f := fixture(); prime(f)
		var population_reads: int = f.control.population_reads
		var result: RefCounted = f.social.resolve(f.a, f.b, context, ["VISITOR"], ["WORKER"], &"kitchen")
		var confirmed: Dictionary = result.confirmed_context()
		check(confirmed.trigger == "social.resolved" and confirmed.actor.id == "a" and confirmed.other.id == "b" and confirmed.minute == 635, "Confirmed identity, initiator and game minute")
		check(confirmed.payload.interaction == SocialResult.Context.keys()[context] and confirmed.payload.reaction_1 == "NEGATIVE" and confirmed.payload.reaction_2 == "POSITIVE" and confirmed.payload.location_id == "kitchen", "Common adapter receives real result for " + str(context))
		check(confirmed.payload.opinion_delta_1 == -1 and confirmed.payload.applied_delta_1 == -1 and f.a.get_opinion("b") == -1 and f.b.get_opinion("a") == 1, "Only legacy directional changes apply once")
		check(social_count(f) == 1 and f.a.memories.find().size() == 1 and f.a.memories.size() == 1 and f.a.moodlets.size() == 1, "Social JSON produces mandatory diary and independent states")
		var memory: Dictionary = f.a.memories.find()[0]; var moodlet: Dictionary = f.a.moodlets.find()[0]
		check(memory.type == "success_envy" and memory.topic == "gathering" and memory.target.id == "b" and memory.strength == 35 and not memory.permanent and memory.source_occurrence_id == confirmed.occurrence_id, "Envy owner/target, exact skill and real social provenance")
		check(moodlet.target.id == "b" and moodlet.context.skill == "gathering" and moodlet.expires_at_minute == 755 and moodlet.modifiers.is_empty(), "JSON envy lasts 120 minutes without behavior modifiers")
		check(f.a.memories.find()[0].text == "Я завидую Степану: он лучше владеет навыком «Собирательство».", "Shared renderer uses actual skill name and participants")
		check(f.control.population_reads == population_reads, "New pair processing does not enumerate the settlement")
		check(not f.service.facts.read(confirmed.other, "moodlets.active").known, "No persistent duplicate of the pair stores in engine facts")
		var draws: int = f.rng.draws; var effect_draws: int = f.service.executor.rng.draws
		confirmed.payload.reaction_1 = "POSITIVE"
		f.social.interaction_committed.emit(result)
		check(social_count(f) == 1 and f.rng.draws == draws and f.service.executor.rng.draws == effect_draws and f.a.get_opinion("b") == -1 and f.a.memories.find().size() == 1, "Duplicate result neither rerolls nor reapplies legacy/new mechanics")
		check(result.confirmed_context().payload.reaction_1 == "NEGATIVE", "Read-only confirmed context remains immutable")
		cleanup(f)
	var bounded_fixture := fixture()
	bounded_fixture.a.set_opinion("b", 100); bounded_fixture.b.set_opinion("a", -100); bounded_fixture.social.rng.rolls = [100, -100]
	var bounded: Dictionary = bounded_fixture.social.resolve(bounded_fixture.a, bounded_fixture.b, SocialResult.Context.WORK).confirmed_context().payload
	check(bounded.opinion_delta_1 == 1 and bounded.applied_delta_1 == 0 and bounded.opinion_delta_2 == -1 and bounded.applied_delta_2 == 0, "Requested social deltas are distinct from clamped actual deltas")
	cleanup(bounded_fixture)

func conditions() -> void:
	for scenario in ["positive", "neutral", "no_pride", "expired", "unrelated_pride", "same_skill", "same_rank_different_xp", "lower_other_skill", "chance_zero", "empty_catalog", "inactive_other"]:
		var f := fixture()
		if scenario != "no_pride": prime(f)
		if scenario == "positive": f.social.rng.rolls = [100, 100]
		if scenario == "neutral": f.social.rng.rolls = [0, 100]
		if scenario == "expired": f.clock.total_minutes += 120
		if scenario == "unrelated_pride":
			var unrelated: Dictionary = f.b.moodlets.find()[0]
			f.b.moodlets.remove(unrelated.id); unrelated.id = "unrelated"
			unrelated.context._event.definition_id = "another.event"
			check(f.b.moodlets.add(unrelated), "Another event may legitimately have a pride type")
		if scenario in ["same_skill", "lower_other_skill"]:
			f.a.add_skill_xp(Skill.Type.GATHERING, 400)
			f.b.add_skill_xp(Skill.Type.CONSTRUCTION, 3000)
			for state in f.b.moodlets.find():
				if state.context.skill == "construction": f.b.moodlets.remove(state.id)
			if scenario == "lower_other_skill": f.a.add_skill_xp(Skill.Type.GATHERING, 600)
		if scenario == "same_rank_different_xp":
			f.a.add_skill_xp(Skill.Type.GATHERING, 500)
			f.b.add_skill_xp(Skill.Type.GATHERING, 500)
		if scenario == "chance_zero": f.service.selector.set_chance("social.resolved", 0)
		if scenario == "empty_catalog": load_content(f, {"definitions": []})
		if scenario == "inactive_other": f.control.unregister_resident("b")
		var diaries: int = f.a.memories.find().size(); var memories: int = f.a.memories.size(); var moods: int = f.a.moodlets.size()
		var before: int = f.a.get_opinion("b")
		var result: RefCounted = f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
		check(social_count(f) == 0 and f.a.memories.find().size() == diaries and f.a.memories.size() == memories and f.a.moodlets.size() == moods, "No extra event for " + scenario)
		check(f.a.get_opinion("b") == clampi(before + result.opinion_delta_1, -100, 100), "Legacy result still applies when follow-up fails: " + scenario)
		cleanup(f)
	# New pride replaces the old skill context, still yielding one event ticket.
	var multiple := fixture(); prime(multiple); prime(multiple, multiple.b, Skill.Type.CONSTRUCTION)
	multiple.social.resolve(multiple.a, multiple.b, SocialResult.Context.CONVERSATION)
	var context: Dictionary = multiple.service.last_occurrence()
	var selection: Dictionary = multiple.service.selector.run(context)
	check(selection.duplicate and selection.eligible == ["social.success_envy"] and selection.definitions_checked == 1 and multiple.b.moodlets.size() == 1 and selection.bindings.skill == "construction", "Latest pride supplies one skill context and one event ticket")
	check(multiple.a.memories.find()[0].topic == selection.bindings.skill and multiple.b.moodlets.get_entry(selection.bindings.success.id).context.skill == selection.bindings.skill, "Chosen fact and consequence refer to the same pride skill")
	cleanup(multiple)

func facts_and_reverse_main() -> void:
	var f := fixture(); prime(f)
	f.a.add_trait(Traits.Type.LAZY); f.a.set_opinion("b", 7); f.b.set_opinion("a", -4)
	var facts: RefCounted = PairFacts.snapshot(f.a, f.b, 635)
	var a := {"kind": "resident", "id": "a"}; var b := {"kind": "resident", "id": "b"}
	check(facts.read(a, "traits").value == ["lazy"] and facts.read(a, "opinion", b).value == 7 and facts.read(b, "opinion", a).value == -4, "Current traits and directed opinions are read-only facts")
	check(facts.read(b, "skill.rank", "gathering").value == Skill.Rank.NOVICE and facts.read(b, "skill.name", "gathering").value == "Собирательство" and facts.read(b, "moodlets.active").value.size() == 1 and facts.read(b, "memories").value.size() == 1, "Skills, active states and memories come from existing resident stores")
	var read: Dictionary = facts.read(b, "memories"); read.value.page(0)[0].strength = 0
	check(f.b.memories.find()[0].strength == 30 and facts._entities.size() == 2, "Projected values are detached; only two resident identities are present")
	# A committed delta remains a fact even if an existing callback later edits opinion.
	f.a.set_opinion("b", 0)
	var callback := func(_other):
		if f.a.get_opinion("b") == -1: f.a.set_opinion("b", 20)
	f.a.relationship_changed.connect(callback)
	var result: RefCounted = f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
	f.a.relationship_changed.disconnect(callback)
	check(result.confirmed_context().payload.opinion_after_1 == -1 and PairFacts.snapshot(f.a, f.b, 635).read(a, "opinion", b).value == 20, "Confirmed interaction result is distinct from current facts after callbacks")
	cleanup(f)
	# Same generic schema with second resident as main, without reversing the trigger.
	f = fixture(); prime(f, f.a)
	f.social.rng.rolls = [100, -100]
	var data := social_content(f)
	var definition: Dictionary = data.definitions[0]
	definition.main_role = "other"
	definition.when = {"eq": [{"ctx": "payload.reaction_2"}, "NEGATIVE"]}
	definition.bind = swap_roles(definition.bind)
	definition.effects = swap_roles(definition.effects)
	definition.effects[0].text = "{other.name} завидует {actor.name}: {skill_name}"
	load_content(f, data)
	var before: int = f.a.memories.find().size()
	result = f.social.resolve(f.a, f.b, SocialResult.Context.MEAL)
	check(result.confirmed_context().actor.id == "a" and f.service.replay(result.confirmed_context().occurrence_id).main.id == "b", "JSON main_role can differ from the social initiator")
	check(f.b.memories.find().size() == 1 and f.a.memories.find().size() == before and f.b.memories.find()[0].target.id == "a" and f.b.moodlets.find()[0].target.id == "a", "Reverse story has correct diary/effect owners and targets")
	cleanup(f)

func swap_roles(value: Variant) -> Variant:
	if value is Dictionary:
		var copy: Dictionary = {}
		for key in value:
			copy[key] = ("other" if value[key] == "actor" else "actor") if key == "role" else swap_roles(value[key])
		return copy
	if value is Array:
		var copy: Array = []
		for item in value: copy.append(swap_roles(item))
		return copy
	return value

func compatibility_and_identity() -> void:
	# Universal stories never perturb ordinary reaction mechanics or its RNG.
	var traces: Array = []
	for enabled_followup in [false, true]:
		var f := fixture(); prime(f)
		f.social.rng = RandomNumberGenerator.new()
		f.social.set_seed(77)
		if not enabled_followup: f.service.selector.set_chance("social.resolved", 0)
		var events: Array = []
		for i in 30:
			var result: RefCounted = f.social.resolve(f.a, f.b, (i % 3) as SocialResult.Context)
			events.append([result.roll_1, result.roll_2, result.reaction_1, result.reaction_2, result.opinion_delta_1, result.opinion_delta_2, result.confirmed_context()])
		check(f.a.memories.find().size()==social_count(f),"Only completed universal follow-ups create initiator diaries")
		traces.append([events,f.social.rng.state,f.a.get_opinion("b"),f.b.get_opinion("a")])
		cleanup(f)
	check(traces[0] == traces[1], "Enabled follow-up preserves exact rolls, confirmed contexts, RNG state and directed relations")
	var repeated := fixture(); prime(repeated)
	var one: RefCounted = repeated.social.resolve(repeated.a, repeated.b, SocialResult.Context.CONVERSATION)
	var two: RefCounted = repeated.social.resolve(repeated.a, repeated.b, SocialResult.Context.CONVERSATION)
	check(one.confirmed_context().occurrence_id != two.confirmed_context().occurrence_id and social_count(repeated) == 2, "Same pair/minute/reaction may be two independent confirmed attempts")
	cleanup(repeated)

func configure_world(scene: Node) -> void:
	scene.game_time.set_process(false); scene.game_time.total_minutes = 635
	scene.game_logger.console_enabled = false
	scene.social_events.enabled = true
	scene.social_events.rng = LegacyRng.new()
	scene.game_events.selector.set_chance("social.resolved", 1)
	scene.game_events.executor.rng = SequenceRng.new()

func json_facts_and_guards() -> void:
	var f := fixture(); prime(f); f.a.add_trait(Traits.Type.LAZY)
	var data := social_content(f); var definition: Dictionary = data.definitions[0]
	definition.when = {"all": [definition.when, {"eq": [{"fact": [{"role": "actor"}, "opinion", {"role": "other"}]}, -1]}, {"exists": {"from": {"fact": [{"role": "actor"}, "traits"]}, "as": "candidate", "where": {"eq": [{"local": "candidate"}, "lazy"]}}}, {"exists": {"from": {"fact": [{"role": "other"}, "memories"]}, "as": "candidate", "where": {"eq": [{"field": [{"local": "candidate"}, "type"]}, "skill_progress"]}}}]}
	load_content(f, data)
	f.social.resolve(f.a, f.b, SocialResult.Context.WORK)
	check(social_count(f) == 1, "Real JSON reads current directed opinion, traits and existing memories")
	cleanup(f)
	f = fixture(); prime(f); data = social_content(f)
	data.definitions[0].cooldown = {"minutes": 60, "scope": [{"role": "actor"}, {"role": "other"}]}
	load_content(f, data)
	f.social.resolve(f.a, f.b, SocialResult.Context.MEAL)
	f.social.resolve(f.a, f.b, SocialResult.Context.MEAL)
	check(social_count(f) == 1 and f.a.get_opinion("b") == -2 and f.service.executor.rng.draws == 2, "Follow-up cooldown never suppresses ordinary social reactions")
	f.clock.total_minutes += 60
	f.social.resolve(f.a, f.b, SocialResult.Context.MEAL)
	check(social_count(f) == 2 and f.a.get_opinion("b") == -3, "Pair-scoped cooldown expires exactly; pride still belongs to its actual skill")
	cleanup(f)
	f = fixture(); prime(f)
	var replacement := Data.new("b", "Новый житель", 30)
	var replace := func(_result):
		f.control.unregister_resident("b")
		f.control.register_resident(replacement)
		replacement.add_skill_xp(Skill.Type.GATHERING, 400)
	f.social.event_resolved.connect(replace)
	f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
	check(social_count(f) == 0 and f.a.memories.find().is_empty() and replacement.memories.find().size() == 1, "Old confirmed result cannot target a replacement data object with reused ID")
	f.social.event_resolved.disconnect(replace)
	cleanup(f)
	f = fixture(); prime(f)
	var snapshots: Array = []
	var captured: Array = []
	f.social.event_resolved.connect(func(result): captured.append(result))
	f.a.memories.changed.connect(func(_entry_id):
		var context: Dictionary = f.service.last_occurrence()
		snapshots.append([f.a.memories.size(), f.a.moodlets.size(), f.service.replay(context.occurrence_id).status])
		f.social.interaction_committed.emit(captured[0]))
	f.social.resolve(f.a, f.b, SocialResult.Context.CONVERSATION)
	check(snapshots == [[1, 1, "completed"]] and social_count(f) == 1 and f.rng.draws == 2 and f.service.executor.rng.draws == 2, "Real social follow-up publishes complete bundle/metadata; reentrant duplicate is silent")
	cleanup(f)
	f = fixture(); prime(f); data = social_content(f)
	data.definitions[0].effects[1].duration_minutes = -1
	load_content(f, data)
	var failed: RefCounted = f.social.resolve(f.a, f.b, SocialResult.Context.WORK)
	check(f.service.replay(failed.confirmed_context().occurrence_id).status == "prepare_failed" and f.a.get_opinion("b") == -1 and f.b.get_opinion("a") == 1, "Failed extra event never rolls back or duplicates committed legacy relations")
	check(f.a.memories.find().is_empty() and f.a.memories.size() == 0 and f.a.moodlets.size() == 0 and f.service.selector.facts == f.service.facts and f.service.executor._facts == f.service.facts, "Social preparation failure leaves no partial bundle or retained pair registry")
	cleanup(f)
	f = fixture(); prime(f)
	var nested := [false]; var commits: Array = []
	var recurse := func(_other):
		if not nested[0]:
			nested[0] = true
			f.social.resolve(f.a, f.b, SocialResult.Context.MEAL)
	f.a.relationship_changed.connect(recurse)
	f.social.interaction_committed.connect(func(result): commits.append([int(JSON.parse_string(result.confirmed_context().occurrence_id)[1]), f.a.get_opinion("b"), f.b.get_opinion("a")]))
	f.social.resolve(f.a, f.b, SocialResult.Context.WORK)
	f.a.relationship_changed.disconnect(recurse)
	check(commits == [[2, -2, 2], [1, -2, 2]] and social_count(f) == 2 and f.social.rng.cursor == 4, "Reentrant legacy commit order: %s; follow-ups=%d; rolls=%d" % [commits, social_count(f), f.social.rng.cursor])
	cleanup(f)

func real_controllers() -> void:
	var scene := Setup.make_scene(self); configure_world(scene)
	var actor: Node = scene.resident_runtimes[1]; var target: Node = scene.resident_runtimes[3]
	target.data.add_skill_xp(Skill.Type.GATHERING, 400)
	var contexts: Array = []
	scene.social_events.interaction_committed.connect(func(result): contexts.append(result.confirmed_context()))
	actor.data.get_need(Need.Type.SOCIAL).value = 100; target.data.get_need(Need.Type.SOCIAL).value = 100
	check(actor.social.try_social_at(StringName(target.data.id), 8000), "Actual social controller begins conversation")
	actor.view._process(100)
	check(contexts.size() == 2 and contexts[0].occurrence_id != contexts[1].occurrence_id and scene.social_events.rng.chances == 2, "Both original conversation start attempts remain independent")
	check(actor.data.memories.find({"type": "success_envy"}).size() == 1 and actor.data.memories.find().size() == 1, "Actual conversation reaches universal JSON/effects")
	actor.social._on_minute(636)
	check(contexts.size() == 2, "Conversation minute ticks do not create new universal triggers")
	scene.free(); await process_frame
	scene = Setup.make_scene(self); configure_world(scene)
	actor = scene.resident_runtimes[1]; target = scene.resident_runtimes[3]
	target.data.add_skill_xp(Skill.Type.GATHERING, 400)
	target.data.activity = Activity.Type.WORKING; target.decision._work_cycle_active = true; target.decision._work_assignment = {"location_id": scene.kitchen_data.id}
	scene.kitchen_data.resources.add(Resources.Type.FOOD, 5); actor.data.hunger = 50
	contexts = []
	scene.social_events.interaction_committed.connect(func(result): contexts.append(result.confirmed_context()))
	check(actor.needs.try_eat(8000) and contexts.is_empty(), "Real meal route does not trigger before paid arrival")
	actor.view._process(100)
	check(contexts.size() == 1 and contexts[0].payload.interaction == "MEAL" and contexts[0].payload.location_id == String(scene.kitchen_data.id), "Actual meal_begun uses common adapter and real location")
	check(actor.data.memories.find({"type": "success_envy"}).size() == 1, "Actual meal applies generic consequences")
	scene.free(); await process_frame
	scene = Setup.make_scene(self); configure_world(scene)
	actor = scene.resident_runtimes[1]; target = scene.resident_runtimes[3]
	scene.player_control.assign_profession(actor.data.id, Profession.Type.BUILDER); scene.player_control.assign_profession(target.data.id, Profession.Type.BUILDER)
	target.data.add_skill_xp(Skill.Type.CONSTRUCTION, 400)
	var definition: RefCounted = Definition.for_type(BuildingType.Type.HOME)
	definition.construction_requirements = {Resources.Type.PLANK: 1}
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	scene.placement.select(definition); scene.placement.update_position(Vector2(-500, 200))
	var site: RefCounted = scene.placement.confirm(); site.add_delivered_material(Resources.Type.PLANK, 1)
	check(target.builder.request_work(), "Peer accepts real builder work")
	preload("res://tests/handling_test_step.gd").move_domain(target, 100)
	contexts = []
	scene.social_events.interaction_committed.connect(func(result): contexts.append(result.confirmed_context()))
	check(actor.builder.request_work(), "Initiator accepts another actual builder slot")
	preload("res://tests/handling_test_step.gd").move_domain(actor, 100)
	check(contexts.any(func(context): return context.actor.id == actor.data.id and context.payload.interaction == "WORK" and context.payload.location_id == String(site.id)), "Actual work_cycle_started reaches common post-commit adapter")
	check(actor.data.memories.find({"type": "success_envy"}).size() == 1 and actor.data.memories.find({"type": "success_envy"})[0].topic == "construction", "Real work uses peer's actual construction pride")
	scene.free(); await process_frame
