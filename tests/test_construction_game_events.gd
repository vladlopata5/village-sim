extends "res://tests/test_staged_builder.gd"
const PlayerRegistry = preload("res://scripts/player_control.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Clock = preload("res://scripts/game_time.gd")
const GameEvents = preload("res://scripts/game_event_service.gd")
class ControlledRng extends RefCounted:
	var value := 0.0
	var draws := 0
	var on_draw: Callable
	func randf() -> float:
		draws += 1
		if on_draw.is_valid(): on_draw.call()
		return value

func unit() -> Dictionary:
	var control := PlayerRegistry.new()
	var a := Resident.new("a", "Анна", 25); var b := Resident.new("b", "Борис", 30)
	for person in [a, b, Resident.new("inactive", "Неактивный", 20)]: control.register_resident(person)
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.total_minutes = 635
	var events := GameEvents.new(); root.add_child(events)
	events.setup(control, clock, func(person): return person.id != "inactive")
	events.candidate_picker.rng = ControlledRng.new(); events.selector.rng = ControlledRng.new(); events.executor.rng = ControlledRng.new()
	return {"control": control, "clock": clock, "events": events, "a": a, "b": b}

func cleanup_unit(f: Dictionary) -> void:
	f.events.candidate_picker.rng.on_draw = Callable()
	for person in [f.a, f.b]:
		for connection in person.memories.changed.get_connections(): person.memories.changed.disconnect(connection.callable)
		for name in [ "skill_changed", "skill_raised"]:
			for connection in person.get_signal_connection_list(name): person.disconnect(name, connection.callable)
	f.events.free(); f.clock.free()

func simple_site(f: Dictionary, id: StringName = &"site", type: int = T.HOME) -> RefCounted:
	var definition = D.for_type(type)
	definition.construction_requirements = {}; definition.construction_work_required = 1; definition.max_builders = 8
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	var site := B.new(id, definition, Vector2.ZERO, B.State.UNDER_CONSTRUCTION)
	f.events.observe_construction(site)
	f.events.observe_construction(site)
	return site

func finish(site: RefCounted, minute: int = 635) -> bool:
	return site.add_construction_work(1) and site.complete_construction(minute)

func result(f: Dictionary) -> Dictionary:
	return f.events.replay(f.events.last_occurrence().occurrence_id)

func construction_events(events: Node) -> Array:
	return events.completed_events().values().filter(func(row): return row.definition_id == "personal.construction_finished")

func run() -> void:
	choice_and_snapshot()
	completion_callbacks()
	filtering_and_no_retry()
	guards_and_failures()
	excluded_transitions()
	await actual_builders()
	print("Construction game events: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func choice_and_snapshot() -> void:
	for pick in [0.0, 1.0]:
		for effect in [0.0, 1.0]:
			var f := unit(); var site := simple_site(f)
			check(site.construction_completed.get_connections().size() == 1, "Observing one site twice does not duplicate subscriptions")
			check(site.claim_builder_slot("a") and site.claim_builder_slot("b"), "Snapshot uses actual accepted builder claims")
			var observed: Array = []
			var changed := func():
				if site.is_built(): observed.append(site.active_builder_ids)
			site.construction_changed.connect(changed)
			var facts: Array = []
			site.construction_completed.connect(func(snapshot): facts.append(snapshot.duplicate(true)))
			f.events.candidate_picker.rng.value = pick; f.events.executor.rng.value = effect
			check(finish(site), "Real BuildingInstance commits its initial construction")
			var context: Dictionary = f.events.last_occurrence()
			var selected: RefCounted = f.a if pick == 0 else f.b
			var other: RefCounted = f.b if pick == 0 else f.a
			check(observed == [[]] and site.active_builder_ids.is_empty() and context.payload.assigned_builder_ids == ["a", "b"], "Completed-state callbacks see cleared claims, trigger keeps the pre-clear list")
			check(context.minute == 635 and context.building == {"kind": "building", "id": "site"} and context.payload.building_type == "HOME" and context.payload.timestamp_source == "caller", "Building identity/type and exact caller game minute are captured")
			check(context.actor.id == selected.id and result(f).main.id == selected.id and selected.memories.find().size() == 1 and other.memories.find().is_empty(), "Exactly one randomly chosen assigned resident owns the mandatory diary")
			check(selected.moodlets.size() == (1 if effect == 0 else 0) and selected.memories.size() == 1 and other.moodlets.size() == 0, "Optional JSON satisfaction does not affect other residents")
			if effect == 0:
				var state: Dictionary = selected.moodlets.find()[0]
				check(state.type == "work_satisfaction" and state.target == context.building and state.expires_at_minute == 755 and state.modifiers.is_empty(), "Satisfaction retains actual building target and JSON duration, with inert modifiers")
			check(f.events.candidate_picker.rng.draws == 1 and f.events.selector.rng.draws == 2 and f.events.executor.rng.draws == 2, "Independent picker/selector/effect streams consume precisely one choice")
			site.construction_completed.emit(facts[0])
			check(not site.complete_construction(636) and construction_events(f.events).size() == 1 and selected.memories.find().size() == 1 and f.events.candidate_picker.rng.draws == 1, "Repeated domain completion/notification cannot reroll or duplicate effects")
			site.construction_changed.disconnect(changed)
			cleanup_unit(f)

func completion_callbacks() -> void:
	var f := unit(); var site := simple_site(f, &"callback-site", T.STORAGE)
	site.claim_builder_slot("a")
	var notifications := [0]
	var clock_change := func():
		if site.is_built():
			notifications[0] += 1
			f.clock.total_minutes = 700
			site.release_builder_slot("a")
	site.construction_changed.connect(clock_change)
	check(finish(site, 635) and notifications[0] == 1 and result(f).status == "completed", "Existing completion cleanup callbacks run before the event without losing assignments")
	check(f.events.last_occurrence().payload.assigned_builder_ids == ["a"] and f.events.last_occurrence().minute == 635 and f.clock.total_minutes == 700, "Caller completion time survives synchronous later clock changes")
	site.construction_changed.disconnect(clock_change)
	cleanup_unit(f)

func filtering_and_no_retry() -> void:
	for ids in [[], ["missing"], ["inactive"], ["missing", "inactive", "b"]]:
		var f := unit(); var site := simple_site(f)
		for id in ids: check(site.claim_builder_slot(id), "Domain claim precedes registry/activity filtering")
		check(finish(site), "Building completes independently of eligible residents")
		if ids.has("b"):
			check(result(f).status == "completed" and f.b.memories.find().size() == 1 and f.a.memories.find().is_empty() and f.events.last_occurrence().payload.eligible_candidate_count == 1, "Only the active valid builder remains eligible")
		else: check(result(f).status == "no_candidates" and construction_events(f.events).is_empty() and f.events.candidate_picker.rng.draws == 0 and f.events.selector.rng.draws == 0, "No candidates is a safe terminal attempt without RNG")
		cleanup_unit(f)
	var single_choice := unit(); var single_site := simple_site(single_choice)
	single_site.claim_builder_slot("a"); single_site.claim_builder_slot("b")
	var event_definitions: Array = single_choice.events.catalog.definitions_for("construction.completed")
	event_definitions[0].when = {"eq": [{"field": [{"role": "actor"}, "id"]}, "b"]}
	check(single_choice.events.catalog.load_data({"definitions": event_definitions}, single_choice.events.facts), "JSON can be eligible for only the unchosen candidate")
	check(finish(single_site) and result(single_choice).status == "no_match" and single_choice.events.last_occurrence().actor.id == "a", "Chosen resident without a matching story ends the attempt")
	check(single_choice.events.candidate_picker.rng.draws == 1 and single_choice.events.selector.rng.draws == 1 and single_choice.a.memories.find().is_empty() and single_choice.b.memories.find().is_empty(), "No fallback search/reroll for the otherwise eligible second resident")
	cleanup_unit(single_choice)
	var generic := unit()
	var picked: Dictionary = generic.events.candidate_picker.choose([null, 4, {"kind": "building", "id": "a"}, {"kind": "resident", "id": "a"}, {"kind": "resident", "id": "a"}], generic.control, func(person): return person.id == "a")
	check(picked.status == "chosen" and picked.candidate_count == 1 and picked.reference.id == "a", "Generic world-candidate mechanism validates refs and removes duplicates")
	cleanup_unit(generic)

func guards_and_failures() -> void:
	for scenario in ["chance_zero", "empty", "invalid_rng", "removed_on_draw", "bad_effect", "wrong_main"]:
		var f := unit(); var site := simple_site(f)
		site.claim_builder_slot("a"); site.claim_builder_slot("b")
		var event_definitions: Array = f.events.catalog.definitions_for("construction.completed")
		if scenario == "chance_zero": f.events.selector.set_chance("construction.completed", 0)
		if scenario == "empty": event_definitions = []
		if scenario == "invalid_rng": f.events.candidate_picker.rng.value = NAN
		if scenario == "removed_on_draw": f.events.candidate_picker.rng.on_draw = func(): f.control.unregister_resident("a")
		if scenario == "bad_effect": event_definitions[0].effects[0].duration_minutes = -1
		if scenario == "wrong_main":
			event_definitions[0].roles.other = {"type": "resident", "from": "ctx.payload.other"}
			event_definitions[0].main_role = "other"
			# A binding supplies another real resident without changing the world fact.
			event_definitions[0].roles.erase("other")
			event_definitions[0].bind = [{"as": "other", "type": "resident_ref", "value": {"catalog": "other"}}]
		var data := {"definitions": event_definitions}
		if scenario == "wrong_main": data["catalogs"] = {"other": {"kind": "resident", "id": "b"}}
		check(f.events.catalog.load_data(data, f.events.facts), "Controlled refusal scenario: " + scenario)
		check(finish(site) and result(f).status != "completed", "Domain construction succeeds despite event refusal: " + scenario)
		check(f.a.memories.find().is_empty() and f.b.memories.find().is_empty() and f.a.moodlets.size() == 0 and f.events.cooldown_history().is_empty(), "Refusal has no partial diary/state/cooldown: " + scenario)
		check(f.events.candidate_picker.rng.draws == 1, "A failed chosen attempt does not retry another resident: " + scenario)
		cleanup_unit(f)
	var cooldown_case := unit(); var first_site := simple_site(cooldown_case)
	first_site.claim_builder_slot("a")
	var definition: Dictionary = cooldown_case.events.catalog.definitions_for("construction.completed")[0]
	definition.cooldown = {"minutes": 60, "scope": [{"role": "actor"}]}
	check(cooldown_case.events.catalog.load_data({"definitions": [definition]}, cooldown_case.events.facts), "Actor-local completion cooldown")
	var observed: Array = []
	cooldown_case.a.memories.changed.connect(func(_entry_id): observed.append([first_site.is_built(), cooldown_case.a.moodlets.size(), cooldown_case.events.replay(cooldown_case.events.last_occurrence().occurrence_id).status, cooldown_case.events.cooldown_history().size()]))
	check(finish(first_site) and observed == [[true, 1, "completed", 1]], "Construction callback observes the entire committed diary/moodlet bundle and metadata")
	var second := simple_site(cooldown_case, &"second"); second.claim_builder_slot("a")
	check(finish(second) and result(cooldown_case).status == "no_match" and cooldown_case.a.memories.find().size() == 1, "Another building is a new fact, but actor cooldown still applies")
	cooldown_case.clock.total_minutes += 60
	var third := simple_site(cooldown_case, &"third"); third.claim_builder_slot("a")
	check(finish(third, cooldown_case.clock.total_minutes) and result(cooldown_case).status == "completed" and cooldown_case.a.memories.find().size() == 2, "Exact cooldown boundary permits a new completed building fact")
	cleanup_unit(cooldown_case)

func excluded_transitions() -> void:
	var f := unit(); var site := simple_site(f)
	site.claim_builder_slot("a")
	check(not site.complete_construction(635) and f.events.last_occurrence().is_empty(), "Unfinished construction never emits a completion fact")
	check(site.set_work_direction(B.WorkDirection.DEMOLISH) and not site.complete_construction(635) and f.events.last_occurrence().is_empty(), "Cancelled/reversed construction never emits completion")
	var restored := B.new(&"restored", D.for_type(T.HOME))
	f.events.observe_construction(restored)
	check(restored.set_work_direction(B.WorkDirection.DEMOLISH) and restored.set_work_direction(B.WorkDirection.BUILD), "Existing D1 restoration path")
	restored.work_paused = false
	check(restored.complete_construction(635) and construction_events(f.events).is_empty(), "Restoration of an existing building does not create initial-construction event")
	var upgraded := B.new(&"upgrade", D.for_type(T.HOME))
	f.events.observe_construction(upgraded)
	check(upgraded.begin_upgrade(), "Existing B2 upgrade begins")
	upgraded.work_paused = false
	for stage in upgraded.construction_definition().construction_stages:
		for resource in stage.materials: check(upgraded.add_delivered_material(resource, stage.materials[resource]), "Actual upgrade materials supplied")
		check(upgraded.add_construction_work(stage.work_minutes), "Actual upgrade work supplied")
	check(upgraded.complete_construction(635) and upgraded.level == 2 and construction_events(f.events).is_empty(), "Upgrade completion is excluded without changing B2 behavior")
	# Keep the same first-build subscription alive through later project phases.
	var tracked := simple_site(f, &"tracked-lifecycle")
	var facts: Array = []
	tracked.construction_completed.connect(func(snapshot): facts.append(snapshot))
	tracked.claim_builder_slot("a")
	check(finish(tracked) and facts.size() == 1, "Observed initial construction publishes its one real fact")
	check(tracked.set_work_direction(B.WorkDirection.DEMOLISH) and tracked.set_work_direction(B.WorkDirection.BUILD), "Previously observed object enters restoration")
	tracked.work_paused = false; tracked.claim_builder_slot("a")
	check(tracked.complete_construction(636) and facts.size() == 1, "An existing first-build subscription stays silent during restoration")
	check(tracked.begin_upgrade(), "Previously observed object enters actual upgrade")
	tracked.work_paused = false
	for stage in tracked.construction_definition().construction_stages:
		for resource in stage.materials: check(tracked.add_delivered_material(resource, stage.materials[resource]), "Tracked upgrade material")
		check(tracked.add_construction_work(stage.work_minutes), "Tracked upgrade work")
	check(tracked.complete_construction(637) and tracked.level == 2 and facts.size() == 1 and f.events.candidate_picker.rng.draws == 1, "Upgrade emits no extra construction fact or candidate lottery on the same observed instance")
	cleanup_unit(f)

func actual_builders() -> void:
	var world := F.create(self)
	var site := place(world, T.SAWMILL, Vector3(-12, 0, 16)); supply(world, site)
	var actors := workers(world)
	world.game_events.candidate_picker.rng = ControlledRng.new(); world.game_events.candidate_picker.rng.value = 1
	world.game_events.executor.rng = ControlledRng.new()
	var snapshots: Array = []
	site.construction_completed.connect(func(snapshot): snapshots.append(snapshot.duplicate(true)))
	check(world._request_work(actors[0]) and world._request_work(actors[1]), "Both actual Builder controllers claim the real site")
	await drive(world, site, actors)
	var events := construction_events(world.game_events)
	check(site.is_built() and site.active_builder_ids.is_empty() and snapshots.size() == 1, "Actual staged physical work completes once and clears claims")
	check(snapshots[0].assigned_builder_ids.size() == 2 and snapshots[0].assigned_builder_ids.has(actors[0].data.id) and snapshots[0].assigned_builder_ids.has(actors[1].data.id), "Both assigned builders survive the pre-clear snapshot")
	check(events.size() == 1 and events[0].main.id in snapshots[0].assigned_builder_ids and world.game_events.candidate_picker.rng.draws == 1, "Actual construction produces only one event for one recorded assigned worker")
	check(events[0].minute == snapshots[0].minute and world.game_events.last_occurrence().payload.timestamp_source == "caller", "Live Builder supplies the exact completion minute")
	var selected: RefCounted = world.player_control.get_resident(events[0].main.id)
	check(selected.memories.find().any(func(entry): return entry.text.begins_with("Мне приятно видеть завершённую стройку")) and selected.moodlets.find({"type": "work_satisfaction"}).size() == 1, "Selected real resident owns the diary and optional satisfaction")
	check(world._activated_buildings.has(site.id) and world.logistics._buildings.has(site.id), "Ordinary building/production activation remains intact")
	for resource in [R.LOG, R.STONE]: check(site.get_construction_reserved_in(resource) == 0 and world.warehouse_data.resources.get_reserved_out(resource) == 0, "Actual material reservations are released normally")
	world.free(); await process_frame
