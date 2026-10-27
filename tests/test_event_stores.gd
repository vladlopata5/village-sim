extends SceneTree
const MemoryStore = preload("res://scripts/memory_store.gd")
const MoodletStore = preload("res://scripts/moodlet_store.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Skill = preload("res://scripts/skill_type.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func memory(entry_id: String = "m1") -> Dictionary:
	return {"id": entry_id, "type": "envy", "topic": "clothing", "target": {"kind": "resident", "id": "other"}, "tags": ["negative", "personal"], "strength": 20, "permanent": false, "created_minute": 10, "source_occurrence_id": "event/1", "provenance": {"kind": "experienced"}, "context": {"detail": {"label": "coat"}}}

func moodlet(entry_id: String = "t1") -> Dictionary:
	return {"id": entry_id, "type": "envy", "target": {"kind": "resident", "id": "other"}, "tags": ["negative"], "created_minute": 10, "expires_at_minute": 30, "source_occurrence_id": "event/1", "modifiers": [{"channel": "future_channel", "value": -3}], "context": {"topic": "clothing"}}

func _initialize() -> void:
	memories()
	memory_validation()
	moodlets()
	moodlet_validation()
	references_and_isolation()
	notifications()
	print("Event stores: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func memories() -> void:
	var store := MemoryStore.new("owner")
	var input := memory()
	check(store.add(input) and store.size() == 1, "Create standalone structured memory")
	check(store.get_entry("m1").owner == {"kind": "resident", "id": "owner"}, "Store binds its resident owner")
	check(store.get_entry("missing").is_empty() and store.find({"unknown": "x"}).is_empty(), "Missing memory and unknown query do not invent records")
	input.context.detail.label = "changed"
	input.tags.append("extra")
	var snapshot := store.get_entry("m1")
	check(snapshot.context.detail.label == "coat" and snapshot.tags.size() == 2, "Deep copy on add")
	snapshot.context.detail.label = "changed again"
	snapshot.provenance.kind = "hearsay"
	var results := store.find({"topic": "clothing"})
	results[0].target.id = "someone_else"
	check(store.get_entry("m1").target.id == "other" and store.get_entry("m1").context.detail.label == "coat", "Lookup/query return detached nested snapshots")
	check(not store.add(memory()) and store.size() == 1 and store.get_entry("m1").strength == 20, "Duplicate ID neither replaces nor reinforces")
	var housing := memory("housing"); housing.topic = "housing"
	var target := memory("target"); target.target = {"kind": "building", "id": "house"}
	var rumor := memory("rumor"); rumor.provenance = {"kind": "hearsay", "reported_by": {"kind": "resident", "id": "reporter"}, "incident_id": "incident/1"}
	var other_rumor := rumor.duplicate(true); other_rumor.id = "other_reporter"; other_rumor.provenance.reported_by.id = "reporter2"
	var incident := rumor.duplicate(true); incident.id = "other_incident"; incident.provenance.incident_id = "incident/2"
	for entry in [housing, target, rumor, other_rumor, incident]: check(store.add(entry), "Independent topic, target and source: " + entry.id)
	check(store.find_similar("envy", "clothing", input.target, {"kind": "experienced"}).size() == 1, "Analogous firsthand experience can be found without mixing housing or hearsay")
	check(store.find_similar("envy", "clothing", input.target, rumor.provenance).size() == 1, "Reporter and incident are part of explicit provenance match")
	check(store.reinforce("m1", 65, 20, "event/2"), "Explicit repeat experience strengthens existing memory")
	snapshot = store.get_entry("m1")
	check(snapshot.strength == 85 and not snapshot.permanent and snapshot.created_minute == 10 and snapshot.last_reinforced_minute == 20, "Strength 80 does not imply permanence; creation time stays stable")
	check(snapshot.source_occurrence_id == "event/1" and snapshot.last_source_occurrence_id == "event/2", "Initial and latest event provenance retained without full history")
	check(store.reinforce("m1", 1000, 21, "event/3") and store.get_entry("m1").strength == 100, "Reinforcement saturates at 100")
	check(not store.reinforce("m1", 1, 19, "old") and not store.reinforce("m1", -1, 22, "bad"), "Reject backward time and negative reinforcement")
	check(not store.reinforce("m1", 1, 22, "") and not store.reinforce("missing", 1, 22, "event/4"), "Reinforcement requires existing record and source event")
	check(store.weaken("m1", 80, 30, 10) and store.get_entry("m1").strength == 20, "Explicit weakening without a built-in time formula")
	check(store.get_entry("m1").last_reinforced_minute == 21 and store.get_entry("m1").last_changed_minute == 30, "Weakening does not pretend to be reinforcement")
	check(not store.reinforce("m1", 1, 29, "past") and not store.weaken("m1", 1, 29, 0), "All updates respect last change, including weakening")
	check(store.weaken("m1", 10, 31, 10) and store.get_entry("m1").is_empty(), "Ordinary memory removed exactly at caller-supplied threshold")
	var permanent := memory("permanent"); permanent.permanent = true
	check(store.add(permanent) and store.weaken("permanent", 1000, 50, 0), "Permanent memory can weaken below zero with saturation")
	check(store.get_entry("permanent").strength == 0 and store.get_entry("permanent").permanent, "Permanent record survives weakening at zero")
	check(store.reinforce("permanent", 5, 51, "event/5") and store.get_entry("permanent").strength == 5, "Faded permanent record can be reinforced")
	check(store.remove("permanent") and not store.remove("permanent"), "Explicit deletion can remove permanent record; repeated deletion is harmless")
	var zero := memory("zero"); zero.strength = 0
	var maximum := memory("maximum"); maximum.strength = 100
	check(store.add(zero) and store.add(maximum), "Both strength boundaries accepted on creation")
	check(store.weaken("maximum", 1000, 60, 0) and store.get_entry("maximum").is_empty(), "Ordinary strength never goes negative")
	check(not store.weaken("zero", 1, 60, -1) and not store.weaken("zero", 1, 60, 101), "Removal threshold must be explicit and within 0..100")
	check(not store.reinforce("zero", INF, 60, "e") and not store.weaken("zero", NAN, 60, 0), "Nonfinite deltas rejected")
	check(store.find({"tags": ["negative", "personal"]}).size() == store.size(), "Exact tag query over stored values")
	var other := MemoryStore.new("second")
	check(other.add(memory("same_id")) and store.add(memory("same_id")) and other.size() == 1, "IDs local to owner; separate stores do not share state")

func memory_validation() -> void:
	var store := MemoryStore.new("owner")
	for delta in [{"strength": -1}, {"strength": 101}, {"strength": NAN}, {"strength": INF}, {"strength": true}, {"permanent": 1}, {"created_minute": -1}, {"created_minute": 1.5}, {"id": ""}, {"topic": " "}, {"type": ""}, {"source_occurrence_id": ""}, {"target": {"id": "x"}}, {"target": {"kind": "resident", "id": "x", "extra": 1}}, {"owner": {"kind": "resident", "id": "foreign"}}, {"tags": ["x", "x"]}, {"tags": [1]}, {"context": []}, {"provenance": {}}, {"provenance": {"kind": "hearsay"}}, {"provenance": {"kind": "hearsay", "reported_by": {"kind": "building", "id": "b"}}}, {"provenance": {"kind": "experienced", "reported_by": {"kind": "resident", "id": "r"}}}, {"unexpected": 1}]:
		var entry := memory(); entry.merge(delta, true)
		check(not store.add(entry) and store.size() == 0, "Invalid memory rejected atomically: " + str(delta))
	check(not MemoryStore.new("").add(memory()), "Empty owner is invalid")
	var minimal := memory()
	for field in ["tags", "context", "target", "permanent"]: minimal.erase(field)
	check(store.add(minimal) and store.get_entry("m1").target == null, "Optional target/tags/context/permanence have inert defaults")

func moodlets() -> void:
	var store := MoodletStore.new("owner")
	var input := moodlet()
	check(store.add(input) and store.size() == 1, "Add standalone timed state")
	check(not store.is_active("t1", 9) and store.is_active("t1", 10) and store.is_active("t1", 29) and not store.is_active("t1", 30), "Active on [created, expiry), exact expiry excluded")
	check(store.active(29).size() == 1 and store.active(30).is_empty() and store.size() == 1, "Read-only active query excludes expired entries without deleting them")
	input.modifiers[0].value = 99
	var snapshot := store.get_entry("t1"); snapshot.modifiers[0].value = 100
	var results := store.active(20); results[0].context.topic = "changed"
	check(store.get_entry("t1").modifiers[0].value == -3 and store.get_entry("t1").context.topic == "clothing", "Moodlet input and read views are detached")
	check(not store.add(moodlet()) and store.get_entry("t1").expires_at_minute == 30, "Duplicate ID does not silently refresh, replace or stack")
	var second := moodlet("t2")
	check(store.add(second) and store.active(20, {"type": "envy"}).size() == 2, "Distinct explicit instances may coexist; no formula combines them")
	var indefinite := moodlet("indefinite"); indefinite.erase("expires_at_minute"); indefinite.erase("modifiers")
	check(store.add(indefinite) and store.is_active("indefinite", 10000000) and store.get_entry("indefinite").modifiers.is_empty(), "No deadline is allowed without implied effects")
	check(store.expire(29) == 0 and store.size() == 3, "Expiration before deadline is a no-op")
	check(store.expire(30) == 2 and store.size() == 1 and store.is_active("indefinite", 30), "Explicit expiry removes timed states, preserves indefinite state")
	check(store.expire(30) == 0 and store.expire(-1) == 0 and not store.is_active("indefinite", -1), "Repeated/invalid expiry and activity checks are safe")
	check(store.remove("indefinite") and not store.remove("indefinite") and store.get_entry("indefinite").is_empty(), "Explicit removal is idempotent")
	var instant := moodlet("instant"); instant.expires_at_minute = instant.created_minute
	check(store.add(instant) and not store.is_active("instant", 10) and store.expire(10) == 1, "Zero duration is consistently inactive and removable")

func moodlet_validation() -> void:
	var store := MoodletStore.new("owner")
	for delta in [{"id": ""}, {"type": ""}, {"source_occurrence_id": ""}, {"created_minute": -1}, {"expires_at_minute": 9}, {"expires_at_minute": 30.5}, {"expires_at_minute": true}, {"modifiers": [3]}, {"modifiers": {}}, {"target": "other"}, {"owner": {"kind": "resident", "id": "foreign"}}, {"tags": ["a", "a"]}, {"context": []}, {"unexpected": 1}]:
		var entry := moodlet(); entry.merge(delta, true)
		check(not store.add(entry) and store.size() == 0, "Invalid moodlet rejected atomically: " + str(delta))
	check(not MoodletStore.new("").add(moodlet()), "Moodlet requires resident owner")
	check(not store.is_active("unknown", 20) and store.find({"no_such_field": 1}).is_empty(), "Missing state is not active")

func references_and_isolation() -> void:
	var resident := Resident.new("owner", "Owner", 25)
	var other := Node.new(); other.name = "target"
	var other_data := Resident.new("other", "Other", 30)
	var deleted_resident: WeakRef = weakref(other_data)
	other.set_meta("resident_data", other_data)
	other_data = null
	root.add_child(other)
	var invalid := memory(); invalid.context.node = other
	check(not resident.memories.add(invalid), "Live Node cannot be retained in memory metadata")
	var invalid_moodlet := moodlet(); invalid_moodlet.modifiers[0].node = other
	check(not resident.moodlets.add(invalid_moodlet), "Live Node cannot be hidden in modifier payload")
	invalid.context.node = func(): return 1
	check(not resident.memories.add(invalid), "Callable cannot be retained")
	invalid.context.node = Resident.new("hidden", "Hidden", 20)
	check(not resident.memories.add(invalid), "RefCounted resident cannot be retained as metadata")
	var recursive: Array = []; recursive.append(recursive)
	invalid.context = {"cycle": recursive}
	check(not resident.memories.add(invalid), "Cyclic data rejected by finite validation depth")
	recursive.clear()
	var original := [resident.mood, resident.get_opinion(&"other"), resident.get_skill_xp(Skill.Type.GATHERING), resident.diary_entries.duplicate(), Modifiers.movement_speed(resident, 10.0)]
	check(resident.memories.add(memory()) and resident.moodlets.add(moodlet()), "Resident owns independent empty stores, populated only by explicit API")
	other.free()
	check(deleted_resident.get_ref() == null, "Historical target ref does not retain removed resident data")
	check(resident.memories.get_entry("m1").target == {"kind": "resident", "id": "other"} and resident.moodlets.is_active("t1", 20), "Deleted target Node is irrelevant to stable archived ref and lifetime")
	check(resident.memories.reinforce("m1", 3, 20, "event/2") and resident.memories.weaken("m1", 1, 21, 0) and resident.moodlets.expire(30) == 1, "Explicit mutations work with deleted target")
	var after := [resident.mood, resident.get_opinion(&"other"), resident.get_skill_xp(Skill.Type.GATHERING), resident.diary_entries.duplicate(), Modifiers.movement_speed(resident, 10.0)]
	check(original == after, "Stores do not change mood, relationships, skills, diary or ResidentModifiers")
	check(resident.relationships.is_empty(), "Memory does not create relationship records")
	var wire: Variant = JSON.parse_string(JSON.stringify(resident.memories.find()))
	check(wire is Array and wire[0].target.id == "other" and wire[0].strength == 22, "Snapshots use JSON-compatible values; no save/load introduced")
	var fresh := Resident.new("fresh", "Fresh", 30)
	check(fresh.memories.size() == 0 and fresh.moodlets.size() == 0, "No store data shared between residents")

func notifications() -> void:
	var store := MemoryStore.new("owner")
	var observed: Array = []
	var callback := func(entry_id: String): observed.append(store.get_entry(entry_id))
	store.changed.connect(callback)
	check(store.add(memory()) and observed.size() == 1 and observed[0].strength == 20, "Add notification observes fully stored memory")
	check(store.reinforce("m1", 5, 20, "event/2") and observed.size() == 2 and observed[1].last_source_occurrence_id == "event/2", "Reinforcement notification observes committed strength/source")
	check(not store.add(memory()) and observed.size() == 2, "Rejected mutation does not notify")
	check(store.weaken("m1", 100, 30, 0) and observed.size() == 3 and observed[2].is_empty(), "Removal notification observes absence")
	store.changed.disconnect(callback)
	var timed := MoodletStore.new("owner")
	timed.add(moodlet("a")); timed.add(moodlet("b"))
	var seen: Array = []
	var expiry_callback := func(entry_id: String):
		seen.append([entry_id, timed.size()])
		if entry_id == "a":
			var replacement := moodlet("b"); replacement.expires_at_minute = 50
			timed.add(replacement)
	timed.changed.connect(expiry_callback)
	check(timed.expire(30) == 2 and timed.size() == 1 and timed.is_active("b", 40), "Expiry commits removals before callbacks; reentrant replacement survives")
	check(seen[0] == ["a", 0], "Expiry observer sees completed local removal pass")
	timed.changed.disconnect(expiry_callback)
