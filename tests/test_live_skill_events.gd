extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Diary = preload("res://scripts/diary_entry.gd")
const PlayerRegistry = preload("res://scripts/player_control.gd")
const Clock = preload("res://scripts/game_time.gd")
const Service = preload("res://scripts/game_event_service.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Definition = preload("res://scripts/building_definition.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Resources = preload("res://scripts/resource_type.gd")
class CountingRng extends RefCounted:
	var draws := 0
	var value := 0.0
	var on_draw: Callable
	func randf() -> float:
		draws += 1
		if on_draw.is_valid(): on_draw.call(draws)
		return value
class RejectingDiary extends Data:
	var accept := false
	func can_add_diary_entry(entry: Diary) -> bool:
		return accept and super.can_add_diary_entry(entry)
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void: call_deferred("_run")

func fixture(people: Array = []) -> Dictionary:
	var control := PlayerRegistry.new()
	if people.is_empty(): people = [Data.new("a", "Анна", 25), Data.new("b", "Борис", 30)]
	for person in people: control.register_resident(person)
	var clock := Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	clock.total_minutes = 635
	var service := Service.new()
	root.add_child(service)
	service.setup(control, clock, func(person): return not person.id.begins_with("inactive"))
	# This fixture tests the original single-definition R2-B3/B4b contract.
	# Full-catalog competition is exercised separately by test_event_catalog_content.
	service.catalog.load_data({"definitions": service.catalog.definitions_for("skill.raised").filter(func(definition): return definition.id == "personal.skill_progress")}, service.facts)
	var rng := CountingRng.new()
	service.selector.rng = rng
	return {"control": control, "clock": clock, "service": service, "rng": rng, "a": people[0], "b": people.back()}

func cleanup(f: Dictionary) -> void:
	f.rng.on_draw = Callable()
	for person in [f.a, f.b]:
		for signal_name in ["skill_changed", "skill_raised", "diary_changed"]:
			for connection in person.get_signal_connection_list(signal_name):
				person.disconnect(signal_name, connection.callable)
	f.service.free()
	f.clock.free()

func content(service: Node) -> Dictionary:
	return {"definitions": service.catalog.definitions_for("skill.raised")}

func _run() -> void:
	var f := fixture()
	var signals: Array = []
	f.a.skill_changed.connect(func(skill, amount, previous): signals.append([skill, amount, previous]))
	var raises: Array = []
	f.a.skill_raised.connect(func(id, skill, previous, next): raises.append([id, skill, previous, next]))
	check(f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 399), "Real XP mutation")
	check(raises.is_empty() and f.rng.draws == 0 and f.a.diary_entries.is_empty(), "XP within rank creates no trigger/event/RNG")
	var mood: int = f.a.mood
	check(f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 1), "Real rank crossing")
	check(raises == [[1, Skill.Type.CONSTRUCTION, 0, 1]], "One immutable transition snapshot")
	check(signals == [[Skill.Type.CONSTRUCTION, 399, 0], [Skill.Type.CONSTRUCTION, 1, 0]], "Existing skill_changed arguments/count preserved")
	check(f.a.diary_entries.size() == 1 and f.b.diary_entries.is_empty(), "Mandatory Diary belongs to the raised resident")
	var entry: RefCounted = f.a.diary_entries[0]
	check(entry.text == "Я замечаю прогресс в навыке «Строительство»: «Профан» → «Новичок»." and entry.created_minute == 635 and entry.importance == Diary.Importance.KEY, "Renderer, existing skill name, game minute and declared importance")
	check(f.a.get_skill_xp(Skill.Type.CONSTRUCTION) == 400 and f.a.mood == mood and f.a.relationships.is_empty(), "Diary does not add XP, mood or opinion")
	check(f.service.completed_events().size() == 1 and f.rng.draws == 2, "Core chance + weighted choice, one completed event")
	var occurrence: Dictionary = f.service.last_occurrence()
	check(occurrence.payload.skill == "construction" and occurrence.payload.previous_rank == 0 and occurrence.payload.new_rank == 1, "Typed source context")
	f.clock.total_minutes = 636
	f.a.skill_raised.emit(1, Skill.Type.CONSTRUCTION, 0, 1)
	check(f.service.replay(occurrence.occurrence_id).duplicate and f.rng.draws == 2 and f.a.diary_entries.size() == 1, "Duplicate delivery/replay does not roll or write again")
	f.control.unregister_resident("a")
	f.control.register_resident(f.a)
	f.a.skill_raised.emit(1, Skill.Type.CONSTRUCTION, 0, 1)
	check(f.rng.draws == 2 and f.a.diary_entries.size() == 1, "Re-registering the same resident does not rename/replay an old transition")
	var before_jump := raises.size()
	f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 20000)
	var count: int = raises.size()
	var draws: int = f.rng.draws
	f.a.add_skill_xp(Skill.Type.CONSTRUCTION, 1)
	check(count == before_jump + 1 and raises.back() == [2, Skill.Type.CONSTRUCTION, 1, 4] and raises.size() == count and f.rng.draws == draws and f.a.get_skill_rank(Skill.Type.CONSTRUCTION) == Skill.Rank.MASTER, "Multi-rank commit is one fact; Master rank cannot raise again")
	cleanup(f)
	# Nested existing callbacks must not reread the later rank or invert facts.
	f = fixture()
	var trace: Array = []
	f.a.skill_changed.connect(func(_skill, _amount, previous):
		trace.append("changed:%d" % previous)
		if previous == 0: f.a.add_skill_xp(Skill.Type.LOGISTICS, 600))
	f.a.skill_raised.connect(func(id, _skill, previous, next): trace.append([id, previous, next]))
	f.a.add_skill_xp(Skill.Type.LOGISTICS, 400)
	check(trace == ["changed:0", "changed:1", [1, 0, 1], [2, 1, 2]], "Post-commit facts follow existing notifications in commit order")
	check(f.a.diary_entries.size() == 2 and f.a.diary_entries[0].text.ends_with("«Профан» → «Новичок».") and f.a.diary_entries[1].text.ends_with("«Новичок» → «Любитель»."), "Each nested transition keeps its own old/new ranks")
	cleanup(f)
	# No chance/no match, and inactive or removed residents.
	for scenario in ["chance", "no_match", "inactive", "removed"]:
		f = fixture([Data.new("inactive-a" if scenario == "inactive" else "a", "Анна", 25)])
		if scenario == "chance": f.service.selector.set_chance("skill.raised", 0)
		if scenario == "no_match": check(f.service.catalog.load_data({"definitions": []}, f.service.facts), "Empty valid catalog")
		if scenario == "removed": f.control.unregister_resident(f.a.id)
		f.a.add_skill_xp(Skill.Type.GATHERING, 400)
		check(f.a.diary_entries.is_empty() and f.service.completed_events().is_empty() and f.service.cooldown_history().is_empty(), "No event for " + scenario)
		cleanup(f)
	# Invalid mandatory text does not commit or start cooldown.
	f = fixture()
	var data := content(f.service)
	data.definitions[0].text.diary_main = "{actor.missing}"
	data.definitions[0].cooldown = {"minutes": 60, "scope": [{"role": "actor"}]}
	check(f.service.catalog.load_data(data, f.service.facts), "Unknown runtime field is checked by renderer")
	f.a.add_skill_xp(Skill.Type.GATHERING, 400)
	occurrence = f.service.last_occurrence()
	check(f.service.replay(occurrence.occurrence_id).status == "text_failed" and f.a.diary_entries.is_empty() and f.service.completed_events().is_empty() and f.service.cooldown_history().is_empty(), "Text failure is not a completed event")
	draws = f.rng.draws
	f.service.replay(occurrence.occurrence_id)
	check(f.rng.draws == draws, "Failed formatting is also deduplicated")
	cleanup(f)
	# Diary validation is shared by legacy append and the new atomic prepare path.
	f = fixture([RejectingDiary.new("a", "Анна", 25)])
	f.a.add_skill_xp(Skill.Type.GATHERING, 400)
	check(f.service.replay(f.service.last_occurrence().occurrence_id).status == "diary_failed" and f.service.completed_events().is_empty(), "Rejected append cannot create a committed event")
	f.a.accept = true
	f.a.add_skill_xp(Skill.Type.GATHERING, 600)
	check(f.service.completed_events().size() == 1 and f.a.diary_entries.size() == 1, "Later distinct transition may succeed")
	cleanup(f)
	# Reentrant facts wait; all event data/metadata are committed before notifications.
	f = fixture()
	data = content(f.service)
	data.definitions[0].cooldown = {"minutes": 60, "scope": []}
	check(f.service.catalog.load_data(data, f.service.facts), "Definition cooldown")
	var pending: Array = []
	f.a.diary_changed.connect(func():
		pending.append(f.service.replay(f.service.last_occurrence().occurrence_id).status)
		f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
		f.b.add_skill_xp(Skill.Type.GATHERING, 400))
	f.a.add_skill_xp(Skill.Type.GATHERING, 400)
	check(pending == ["completed"] and f.a.diary_entries.size() == 1 and f.b.diary_entries.is_empty(), "Publication sees committed metadata; nested duplicate + other actor do not bypass cooldown")
	check(f.service.completed_events().size() == 1 and f.service.cooldown_history().size() == 1, "Only acknowledged event updates cooldown")
	f.clock.total_minutes += 60
	f.b.add_skill_xp(Skill.Type.GATHERING, 600)
	check(f.b.diary_entries.size() == 1 and f.service.completed_events().size() == 2, "Exact cooldown expiry permits a later transition")
	cleanup(f)
	# Main role is resolved independently from the trigger initiator.
	for remove_recipient in [false, true]:
		f = fixture()
		data = content(f.service)
		data.catalogs = {"recipient": {"kind": "resident", "id": "b"}}
		data.definitions[0].bind = [{"as": "recipient", "type": "resident_ref", "value": {"catalog": "recipient"}}]
		data.definitions[0].main_role = "recipient"
		data.definitions[0].text.diary_main = "{recipient.name}: {payload.skill_name}"
		check(f.service.catalog.load_data(data, f.service.facts), "Generic recipient binding, no separate selector")
		if remove_recipient: f.rng.on_draw = func(n):
			if n == 2: f.control.unregister_resident("b")
		f.a.add_skill_xp(Skill.Type.GATHERING, 400)
		check(f.a.diary_entries.is_empty(), "Initiator is not automatically the Diary owner")
		check(f.b.diary_entries.size() == (0 if remove_recipient else 1), "Recipient is revalidated after selection")
		cleanup(f)
	await live_builder_cycle()
	await canonical_diary()
	all_skills_and_rank_payloads()
	print("Live skill events: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func all_skills_and_rank_payloads() -> void:
	var f := fixture()
	var count := 0
	for skill in Skill.Type.values():
		f.a.add_skill_xp(skill, 400)
		count += 1
		var payload: Dictionary = f.service.last_occurrence().payload
		check(payload.skill == Skill.Type.keys()[skill].to_lower() and payload.previous_rank == Skill.Rank.PROFANE and payload.new_rank == Skill.Rank.NOVICE, "Every new skill uses the same rank event contract")
		check(payload.previous_rank_name == "Профан" and payload.new_rank_name == "Новичок" and not payload.has("new_level"), "Event payload names titles and has no legacy level")
		check(f.a.diary_entries.size() == count and f.a.diary_entries.back().text.contains(Skill.display_name(skill)) and not f.a.diary_entries.back().text.contains("XP"), "One title-only diary per actual new-skill rank")
	var snapshots := preload("res://scripts/resident_event_facts.gd").snapshot(f.a, f.b, 635)
	for skill in Skill.Type.values():
		var key: String = Skill.Type.keys()[skill].to_lower()
		check(snapshots.read({"kind": "resident", "id": f.a.id}, "skill.rank", key).value == Skill.Rank.NOVICE, "Social facts cover every new skill")
	var draws: int = f.rng.draws
	for transition in [[-1, 0, 1], [99, -1, 1], [100, 0, 5], [101, 2, 2], [102, 2, 1]]:
		f.a.skill_raised.emit(transition[0], Skill.Type.MINING, transition[1], transition[2])
	check(f.rng.draws == draws and f.a.diary_entries.size() == count, "Invalid or non-increasing rank notifications cannot create events")
	cleanup(f)

func live_builder_cycle() -> void:
	var scene := Setup.make_scene(self)
	scene.game_time.debug_next_phase()
	var actor: Node = scene.resident_runtimes[1]
	scene.player_control.assign_profession(actor.data.id, Profession.Type.BUILDER)
	actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 392)
	var definition: RefCounted = Definition.for_type(BuildingType.Type.HOME)
	definition.construction_requirements = {Resources.Type.PLANK: 1}
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	scene.placement.select(definition)
	scene.placement.update_position(Vector2(-500, 200))
	var site: RefCounted = scene.placement.confirm()
	site.add_delivered_material(Resources.Type.PLANK, 1)
	check(actor.builder.request_work(), "Actual Builder controller accepts a real site")
	preload("res://tests/handling_test_step.gd").move_domain(actor, 100)
	check(actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 392 and actor.data.diary_entries.is_empty(), "Starting work grants neither XP nor achievement")
	scene.game_time.debug_skip_minutes(60)
	check(actor.data.get_skill_xp(Skill.Type.CONSTRUCTION) == 400 and actor.data.get_skill_rank(Skill.Type.CONSTRUCTION) == 1, "Unchanged completed Builder cycle awards actual XP")
	check(actor.data.diary_entries.size() == 1 and scene.game_events.completed_events().size() == 1 and actor.data.diary_entries[0].text.contains("Строительство"), "Work completion reaches JSON engine and Diary in live scene assembly")
	var stranger := Data.new("not-registered", "Неизвестный", 20)
	stranger.add_skill_xp(Skill.Type.GATHERING, 400)
	check(stranger.diary_entries.is_empty(), "Unregistered data cannot receive a game event")
	actor.queue_free()
	actor.data.add_skill_xp(Skill.Type.CONSTRUCTION, 600)
	check(actor.data.diary_entries.size() == 1, "Queued-for-deletion runtime is not active even while data remains registered")
	scene.free()
	await process_frame

func canonical_diary() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	var person: RefCounted = world.residents[0]
	world.resident_selection.select(person)
	person.add_skill_xp(Skill.Type.CONSTRUCTION, 400)
	check(person.diary_entries.size() == 1 and world.game_events.completed_events().size() == 1, "Canonical Main3D is wired to the live event service")
	check(world.resident_card_view().get_node("%Diary").text.contains(person.diary_entries[0].text), "Existing ResidentCard updates from the new Diary entry without UI changes")
	var newcomer := Data.new("event-new", "Новый", 25)
	var runtime: Node = world.register_spawned_resident(newcomer, Vector3(0, 0, -25))
	check(runtime != null, "Actual spawned runtime registered")
	newcomer.add_skill_xp(Skill.Type.LOGISTICS, 400)
	check(newcomer.diary_entries.size() == 1 and newcomer.diary_entries[0].text.contains("Логистика"), "Newly registered residents use the same trigger adapter")
	world.player_control.unregister_resident(newcomer.id)
	newcomer.add_skill_xp(Skill.Type.LOGISTICS, 600)
	check(newcomer.diary_entries.size() == 1, "Removed resident data stays silent without changing global lifecycle")
	world.free()
	await process_frame
