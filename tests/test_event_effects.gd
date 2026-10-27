extends "res://tests/test_live_skill_events.gd"
const Moodlets = preload("res://scripts/moodlet_store.gd")
class SequenceRng extends RefCounted:
	var values: Array = []
	var draws := 0
	var on_draw: Callable
	func randf() -> float:
		draws += 1
		if on_draw.is_valid(): on_draw.call(draws)
		return values[draws - 1] if draws <= values.size() else 0.0
class RejectingStore extends Moodlets:
	var validations := 0
	var reject_after := 0
	func prepare_add(record: Dictionary) -> Dictionary:
		validations += 1
		return {} if validations > reject_after else super.prepare_add(record)

func fixture(people: Array = []) -> Dictionary:
	var f := super.fixture(people)
	f.service.executor.rng = SequenceRng.new()
	return f

func cleanup(f: Dictionary) -> void:
	if f.service.executor.rng is SequenceRng: f.service.executor.rng.on_draw = Callable()
	for person in [f.a, f.b]:
		for store in [person.memories, person.moodlets]:
			for connection in store.get_signal_connection_list("changed"): store.disconnect("changed", connection.callable)
	super.cleanup(f)

func load_content(f: Dictionary, data: Dictionary) -> void:
	check(f.service.catalog.load_data(data, f.service.facts), "Catalog accepts test definition: " + str(f.service.catalog.errors))

func raise_level(f: Dictionary) -> Dictionary:
	f.a.add_skill_xp(Skill.Type.GATHERING, 10)
	return f.service.replay(f.service.last_occurrence().occurrence_id)

func _run() -> void:
	probabilities()
	groups()
	atomic_failures()
	failure_then_success()
	recipients_and_diaries()
	notifications_and_reentrancy()
	lifetimes_and_rng()
	await canonical_effects()
	print("Event effects: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func probabilities() -> void:
	for pair in [[0.1, 0.1], [0.1, 0.9], [0.9, 0.1], [0.9, 0.9], [0.6, 0.3]]:
		var f := fixture()
		f.service.executor.rng.values = pair
		var result := raise_level(f)
		var memory_count := 1 if pair[0] < 0.6 else 0
		var moodlet_count := 1 if pair[1] < 0.3 else 0
		check(result.status == "completed" and f.a.diary_entries.size() == 1, "Mandatory diary even if no mechanics pass")
		check(f.a.memories.size() == memory_count and f.a.moodlets.size() == moodlet_count, "Independent consequences: " + str(pair))
		check(f.rng.draws == 2 and f.service.executor.rng.draws == 2, "Separate streams: two selector draws, two effect draws")
		var context: Dictionary = f.service.last_occurrence()
		f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
		f.service.executor.execute({}, context, 635, f.a)
		f.service.executor.publish(context.occurrence_id)
		check(f.rng.draws == 2 and f.service.executor.rng.draws == 2 and f.a.diary_entries.size() == 1 and f.a.memories.size() == memory_count and f.a.moodlets.size() == moodlet_count, "Both coordinator and executor deduplicate; republish is harmless")
		if memory_count:
			var memory: Dictionary = f.a.memories.find()[0]
			check(memory.strength == 30 and not memory.permanent and memory.type == "skill_progress" and memory.topic == "gathering" and memory.provenance == {"kind": "experienced"}, "JSON strength/topic/provenance preserved")
			check(memory.source_occurrence_id == context.occurrence_id and memory.context._event.definition_id == "personal.skill_progress" and memory.context._event.slot == "effect/0", "Memory has real occurrence and definition provenance")
		if moodlet_count:
			var moodlet: Dictionary = f.a.moodlets.find()[0]
			check(moodlet.type == "pride" and moodlet.expires_at_minute == 755 and moodlet.modifiers.is_empty(), "JSON pride lifetime is 120 game minutes, with no gameplay modifiers")
		check(f.a.mood == 50 and f.a.relationships.is_empty() and f.a.get_skill_xp(Skill.Type.GATHERING) == 10, "No mood/opinion/XP feedback")
		cleanup(f)
	for probability in [0.0, 1.0]:
		for boundary in [0.0, 1.0]:
			var f := fixture(); var data := content(f.service)
			for effect in data.definitions[0].effects: effect.chance = probability
			load_content(f, data)
			f.service.executor.rng.values = [boundary, boundary]
			check(raise_level(f).status == "completed" and f.a.memories.size() == int(probability) and f.a.moodlets.size() == int(probability), "0/100 percent at inclusive RNG boundaries")
			cleanup(f)
	var empty := fixture(); var empty_data := content(empty.service); empty_data.definitions[0].effects = []
	load_content(empty, empty_data)
	check(raise_level(empty).status == "completed" and empty.a.diary_entries.size() == 1 and empty.service.executor.rng.draws == 0, "Diary-only event remains valid without consequence rolls")
	cleanup(empty)

func groups() -> void:
	for choice in [[0.1, 0], [0.25, 1], [0.7, 2], [1.0, 2]]:
		var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
		var first: Dictionary = definition.effects[0].duplicate(true); first.weight = 20; first.erase("chance"); first.kind = "first"
		var second := first.duplicate(true); second.weight = 10; second.kind = "second"
		definition.effects = [definition.effects[1]]; definition.effects[0].chance = 1
		definition.exclusive_groups = [{"id": "response", "chance": 1, "options": [first, second, {"op": "none", "weight": 70}]}]
		load_content(f, data); f.service.executor.rng.values = [0.0, 0.0, choice[0]]
		var result := raise_level(f)
		check(result.status == "completed" and result.exclusive_groups == [{"id": "response", "index": choice[1]}], "Normalized weighted selection: " + str(choice))
		check(f.a.memories.size() == (0 if choice[1] == 2 else 1) and f.a.moodlets.size() == 1 and f.service.executor.rng.draws == 3, "At most one group outcome, independent effect coexists, none creates nothing")
		cleanup(f)
	for scenario in ["chance_zero", "all_zero", "large", "option_chance"]:
		var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
		var option: Dictionary = definition.effects[0].duplicate(true); option.erase("chance"); option.weight = 1
		definition.effects = []
		definition.exclusive_groups = [{"id": "g", "chance": 1, "options": [{"op": "none", "weight": 0}, option]}]
		if scenario == "chance_zero": definition.exclusive_groups[0].chance = 0
		if scenario == "all_zero": definition.exclusive_groups[0].options[1].weight = 0
		if scenario == "large":
			definition.exclusive_groups[0].options[0].weight = 1.0e308
			definition.exclusive_groups[0].options[1].weight = 1.0e308
			f.service.executor.rng.values = [0.0, 1.0]
		if scenario == "option_chance": definition.exclusive_groups[0].options[1].chance = 0
		load_content(f, data)
		var result := raise_level(f)
		check(result.status == "completed" and f.a.memories.size() == (1 if scenario == "large" else 0), "Group handles " + scenario)
		check(f.service.executor.rng.draws == (3 if scenario == "option_chance" else 2 if scenario == "large" else 1), "Exactly documented draws for " + scenario)
		cleanup(f)

func atomic_failures() -> void:
	for scenario in ["duration", "strength", "missing_value", "reserved_context", "store", "stale_store", "diary", "collision", "recipient", "unsupported", "unsupported_group", "rng"]:
		var f := fixture([RejectingDiary.new("a", "Анна", 25), Data.new("b", "Борис", 30)] if scenario == "diary" else [])
		var data := content(f.service); var definition: Dictionary = data.definitions[0]
		for effect in definition.effects: effect.chance = 1
		definition.cooldown = {"minutes": 60, "scope": [{"role": "actor"}]}
		if scenario == "duration": definition.effects[1].duration_minutes = -1
		if scenario == "strength": definition.effects[0].strength = 101
		if scenario == "missing_value": definition.effects[1].definition = {"ctx": "payload.missing"}
		if scenario == "reserved_context": definition.effects[1].context = {"_event": {"id": "forged"}}
		if scenario in ["store", "stale_store"]:
			f.a.moodlets = RejectingStore.new("a")
			f.a.moodlets.reject_after = 1 if scenario == "stale_store" else 0
		if scenario == "collision":
			var id := JSON.stringify([JSON.stringify(["skill.raised", "a", 1, 1]), definition.id, definition.revision, "effect/0"])
			check(f.a.memories.add({"id": id, "type": "existing", "topic": "original", "strength": 7, "created_minute": 1, "source_occurrence_id": "original", "provenance": {"kind": "experienced"}}), "Prepare existing ID collision")
		if scenario == "recipient":
			definition.roles.other = {"type": "resident", "from": "ctx.payload.recipient", "active_required": true}
			# Use an explicit binding, because the real producer has no arbitrary recipient payload.
			definition.roles.erase("other")
			data.catalogs = {"recipient": {"kind": "resident", "id": "b"}}
			definition.bind = [{"as": "recipient", "type": "resident_ref", "value": {"catalog": "recipient"}}]
			definition.effects[1].owner = {"binding": "recipient"}
			f.service.executor.rng.on_draw = func(n):
				if n == 2: f.control.unregister_resident("b")
		if scenario in ["unsupported", "unsupported_group"]:
			var unsupported := {"op": "opinion.add", "owner": {"role": "actor"}, "target": {"role": "actor"}, "amount": 1, "chance": 0, "weight": 0}
			if scenario == "unsupported": definition.effects.append(unsupported)
			else: definition.exclusive_groups = [{"id": "unsupported", "options": [unsupported, {"op": "none", "weight": 1}]}]
		if scenario == "rng": f.service.executor.rng.values = [0.0, NAN]
		load_content(f, data)
		var notices: Array = []
		f.a.diary_changed.connect(func(): notices.append("diary"))
		f.a.memories.changed.connect(func(_id): notices.append("memory"))
		f.a.moodlets.changed.connect(func(_id): notices.append("moodlet"))
		var result := raise_level(f)
		check(result.status != "completed" and not result.errors.is_empty(), "Diagnostic refusal for " + scenario)
		check(f.a.diary_entries.is_empty() and f.a.moodlets.size() == 0 and f.a.memories.size() == (1 if scenario == "collision" else 0), "No partial writes on " + scenario)
		check(notices.is_empty() and f.service.completed_events().is_empty() and f.service.cooldown_history().is_empty(), "No partial notifications/completed/cooldown on " + scenario)
		var draws: int = f.service.executor.rng.draws
		f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
		check(f.service.executor.rng.draws == draws and f.a.diary_entries.is_empty(), "Failed occurrence cannot reroll: " + scenario)
		cleanup(f)

func failure_then_success() -> void:
	var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
	for effect in definition.effects: effect.chance = 1
	definition.cooldown = {"minutes": 60, "scope": [{"role": "actor"}]}
	definition.effects[1].duration_minutes = -1
	load_content(f, data)
	check(raise_level(f).status == "prepare_failed", "Initial prepare fails")
	definition.effects[1].duration_minutes = 120
	load_content(f, data)
	check(raise_level(f).status == "completed" and f.service.cooldown_history().size() == 1 and f.a.memories.size() == 1 and f.a.moodlets.size() == 1, "Failed prepare does not start cooldown or block a distinct trigger")
	var draws: int = f.service.executor.rng.draws
	check(raise_level(f).status == "no_match" and f.service.executor.rng.draws == draws and f.a.diary_entries.size() == 1, "Successful commit starts cooldown; rejected selection does not roll effects")
	f.clock.total_minutes += 60
	check(raise_level(f).status == "completed" and f.a.diary_entries.size() == 2 and f.a.memories.size() == 2 and f.a.moodlets.size() == 2, "Exact expiry permits a new complete event; no implicit memory reinforcement")
	cleanup(f)
	for who in ["a", "b"]:
		f = fixture(); data = content(f.service); definition = data.definitions[0]
		data.catalogs = {"recipient": {"kind": "resident", "id": "b"}}
		definition.bind = [{"as": "recipient", "type": "resident_ref", "value": {"catalog": "recipient"}}]
		definition.main_role = "recipient"
		f.service.executor.rng.on_draw = func(n):
			if n == 2: f.control.unregister_resident(who)
		load_content(f, data)
		check(raise_level(f).status != "completed" and f.a.diary_entries.is_empty() and f.b.diary_entries.is_empty() and f.a.memories.size() == 0 and f.a.moodlets.size() == 0, "Source/main disappearing during consequence rolls aborts all writes: " + who)
		cleanup(f)

func recipients_and_diaries() -> void:
	for probability in [0, 1]:
		var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
		data.catalogs = {"recipient": {"kind": "resident", "id": "b"}}
		definition.bind = [{"as": "recipient", "type": "resident_ref", "value": {"catalog": "recipient"}}]
		definition.main_role = "recipient"
		definition.text.diary_main = "{recipient.name}: главный участник"
		definition.text.diary_secondary = "{actor.name}: другой участник"
		definition.secondary_diary = {"role": "actor", "chance": probability}
		for effect in definition.effects: effect.chance = 1
		definition.effects[0].owner = {"binding": "recipient"}
		definition.effects[0].target = {"role": "actor"}
		definition.effects[0].provenance = {"kind": "hearsay", "reported_by": {"role": "actor"}}
		definition.effects[1].owner = {"role": "actor"}
		load_content(f, data)
		check(raise_level(f).status == "completed" and f.b.diary_entries.size() == 1 and f.a.diary_entries.size() == probability, "Main != actor and optional secondary diary probability")
		check(f.b.diary_entries[0].text == "Борис: главный участник" and (probability == 0 or f.a.diary_entries[0].text == "Анна: другой участник"), "Separate participant texts through common renderer")
		check(f.b.memories.size() == 1 and f.a.memories.size() == 0 and f.a.moodlets.size() == 1 and f.b.moodlets.size() == 0, "Effects honor roles/bindings, not implicit main owner")
		check(f.b.memories.find()[0].provenance.reported_by.id == "a" and f.b.memories.find()[0].target.id == "a", "Target and hearsay references resolved as data")
		cleanup(f)
	for probability in [0, 1]:
		var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
		data.catalogs = {"other": {"kind": "resident", "id": "b"}}
		definition.bind = [{"as": "other", "type": "resident_ref", "value": {"catalog": "other"}}]
		definition.secondary_diary = {"role": "other", "chance": probability}
		definition.text.diary_secondary = "{other.missing}"
		load_content(f, data)
		check((raise_level(f).status == "completed") == (probability == 0), "Only selected secondary text is required; selected bad text aborts whole event")
		check(f.a.diary_entries.size() == (1 if probability == 0 else 0), "No main-only commit when selected secondary cannot render")
		cleanup(f)

func notifications_and_reentrancy() -> void:
	var f := fixture(); var data := content(f.service); var definition: Dictionary = data.definitions[0]
	for effect in definition.effects: effect.chance = 1
	definition.cooldown = {"minutes": 60, "scope": []}
	load_content(f, data)
	var snapshots: Array = []
	var observe := func():
		snapshots.append([f.a.diary_entries.size(), f.a.memories.size(), f.a.moodlets.size(), f.service.completed_events().size(), f.service.cooldown_history().size(), f.service.replay(f.service.last_occurrence().occurrence_id).status])
	f.a.diary_changed.connect(func():
		observe.call()
		f.service.executor.publish(f.service.last_occurrence().occurrence_id)
		f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
		f.b.add_skill_xp(Skill.Type.GATHERING, 10))
	f.a.memories.changed.connect(func(_id): observe.call())
	f.a.moodlets.changed.connect(func(_id): observe.call())
	f.a.add_skill_xp(Skill.Type.GATHERING, 10)
	check(snapshots == [[1, 1, 1, 1, 1, "completed"], [1, 1, 1, 1, 1, "pending"], [1, 1, 1, 1, 1, "pending"]], "Every callback sees ALL event data and metadata; nested other occurrence is pending until publication completes")
	check(f.b.diary_entries.is_empty() and f.b.memories.size() == 0 and f.service.completed_events().size() == 1 and f.service.executor.rng.draws == 2, "Nested other resident cannot bypass shared cooldown")
	f.clock.total_minutes += 60
	f.b.add_skill_xp(Skill.Type.GATHERING, 10)
	check(f.b.diary_entries.size() == 1 and f.b.memories.size() == 1 and f.b.moodlets.size() == 1 and f.service.completed_events().size() == 2, "Exact cooldown boundary commits a later complete bundle")
	cleanup(f)

func lifetimes_and_rng() -> void:
	for lifetime in ["duration", "absolute", "indefinite"]:
		var f := fixture(); var data := content(f.service); var effect: Dictionary = data.definitions[0].effects[1]
		if lifetime == "absolute": effect.erase("duration_minutes"); effect.expires_at_minute = 640.0
		if lifetime == "indefinite": effect.erase("duration_minutes")
		load_content(f, data); raise_level(f)
		var entry: Dictionary = f.a.moodlets.find()[0]
		check(f.a.moodlets.is_active(entry.id, 635) and f.a.moodlets.is_active(entry.id, 639), "Active saved moodlet: " + lifetime)
		var expiry: int = 755 if lifetime == "duration" else 640
		check(f.a.moodlets.is_active(entry.id, expiry) == (lifetime == "indefinite"), "Exact expiry without behavior modifiers: " + lifetime)
		cleanup(f)
	var traces: Array = []
	for repeat in 2:
		var f := fixture(); f.service.executor.rng = RandomNumberGenerator.new(); f.service.executor.rng.seed = 42
		for step in 10: f.a.add_skill_xp(Skill.Type.GATHERING, 10)
		traces.append([f.a.memories.find(), f.a.moodlets.find(), f.service.executor.rng.state])
		cleanup(f)
	check(traces[0] == traces[1], "Same effect seed and actual XP transitions reproduce records and RNG state")

func canonical_effects() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world); world.game_time.set_process(false); world.game_logger.console_enabled = false
	var rng := SequenceRng.new(); world.game_events.executor.rng = rng
	var resident: RefCounted = world.residents[0]
	resident.add_skill_xp(Skill.Type.CONSTRUCTION, 10)
	check(resident.diary_entries.size() == 1 and resident.memories.size() == 1 and resident.moodlets.size() == 1 and rng.draws == 2, "Canonical actual skill.raised path commits Diary + Memory + Moodlet without waiting for manual play")
	check(resident.memories.find()[0].topic == "construction" and resident.moodlets.find()[0].expires_at_minute == world.game_time.total_minutes + 120, "Real skill payload and game clock reach stored states")
	world.free(); await process_frame
