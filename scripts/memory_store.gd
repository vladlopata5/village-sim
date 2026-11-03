extends RefCounted
## Resident-owned structured experiences. No clock subscription or opinion/mood effects.
const Data = preload("res://scripts/event_store_data.gd")
const Facts = preload("res://scripts/event_facts.gd")
signal changed(entry_id: String)
var _owner_id: String
var _entries: Dictionary = {}
static var _version_sequence := 0
var _clock: WeakRef
var _last_night := -60

func bind_clock(clock: Node) -> void:
	if _clock != null and _clock.get_ref() == clock: return
	_clock = weakref(clock)
	_last_night = _night_at(clock.total_minutes)

static func _night_at(minute: int) -> int:
	@warning_ignore("integer_division")
	return ((minute + 60) / 1440) * 1440 - 60

func advance(minute: int) -> void: advance_all([self], minute)

static func advance_all(stores: Array, minute: int) -> void:
	# Prepare all participants, then mutate all, then publish. Pair snapshots never
	# observe one journal before midnight maintenance and the other afterwards.
	var packets: Array = []
	var seen: Array = []
	for store in stores:
		if store in seen: continue
		seen.append(store)
		packets.append({"store":store,"state":store._prepare_advance(minute)})
	for packet in packets: packet.store._apply_advance(packet.state)
	for packet in packets:
		for entry_id in packet.state.changed: packet.store.changed.emit(entry_id)

func _prepare_advance(minute: int) -> Dictionary:
	if minute < _last_night + 1440: return {"entries":_entries,"night":_last_night,"changed":[]}
	var entries := _entries.duplicate(true)
	var night := _last_night + 1440
	while night <= minute:
		var groups: Dictionary = {}
		for entry: Dictionary in entries.values():
			var key := _meaning(entry)
			if not groups.has(key): groups[key] = []
			groups[key].append(entry)
		for group: Array in groups.values():
			if group.size() < 2: continue
			group.sort_custom(func(a,b): return a.created_minute > b.created_minute if a.created_minute != b.created_minute else a.id > b.id)
			var survivor: Dictionary = group[0]
			var strongest := 0.0
			for entry: Dictionary in group: strongest = maxf(strongest,entry.strength)
			survivor.strength = minf(100,strongest + 10 * (group.size()-1))
			survivor.last_changed_minute = night
			for index in range(1,group.size()): entries.erase(group[index].id)
		for entry_id in entries.keys():
			var entry: Dictionary = entries[entry_id]
			if entry.permanent: continue
			entry.strength = maxf(0,entry.strength-5)
			entry.last_changed_minute = night
			if entry.strength == 0: entries.erase(entry_id)
		@warning_ignore("integer_division")
		var limit := mini(10 + night / 1440 + 1, 50)
		var ordinary: Array = entries.values().filter(func(entry): return not entry.permanent)
		ordinary.sort_custom(func(a,b):
			if a.strength != b.strength: return a.strength < b.strength
			return a.created_minute < b.created_minute if a.created_minute != b.created_minute else a.id < b.id)
		for entry in ordinary:
			if entries.size() <= limit: break
			entries.erase(entry.id)
		night += 1440
	var changed_ids: Array = []
	for entry_id in _entries:
		if not entries.has(entry_id) or entries[entry_id] != _entries[entry_id]: changed_ids.append(entry_id)
	return {"entries":entries,"night":maxi(_last_night,night-1440),"changed":changed_ids}

func _apply_advance(state: Dictionary) -> void:
	for entry_id in state.changed:
		if state.entries.has(entry_id):
			_version_sequence += 1
			state.entries[entry_id]["_version"] = _version_sequence
	_entries = state.entries
	_last_night = state.night

static func _semantic(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys(); keys.sort()
		for key in keys:
			if key.begins_with("diagnostic_") or key.begins_with("debug_"): continue
			if key in ["_event","_version","occurrence_id","source_occurrence_id","revision","created_minute","last_changed_minute","last_reinforced_minute","last_source_occurrence_id","timestamp","timestamps","diagnostics","debug","pride_moodlet_id"]: continue
			result[key] = _semantic(value[key])
		return result
	if value is Array: return value.map(_semantic)
	return value

static func _meaning(entry: Dictionary) -> String:
	var tags: Array = entry.tags.duplicate(); tags.sort()
	var participants: Array = []
	for entity in entry.get("participants",[]):
		var normalized: Variant = _semantic(entity)
		if normalized not in participants: participants.append(normalized)
	participants.sort_custom(func(a,b): return JSON.stringify(a) < JSON.stringify(b))
	return JSON.stringify(_semantic({"type":entry.type,"topic":entry.topic,"tags":tags,"target":entry.target,"participants":participants,"permanent":entry.permanent,"provenance":entry.provenance,"context":entry.context}))

func chronological() -> Array:
	var records := find()
	records.sort_custom(func(a,b): return a.created_minute > b.created_minute if a.created_minute != b.created_minute else a.id > b.id)
	return records

func _init(owner_id: String) -> void:
	_owner_id = owner_id

func owner() -> Dictionary:
	return {"kind": "resident", "id": _owner_id}

func size() -> int:
	return _entries.size()

func get_entry(entry_id: String) -> Dictionary:
	return _entries.get(entry_id, {}).duplicate(true)

func find(query: Dictionary = {}) -> Array:
	var result: Array = []
	if not Data.json_value(query): return result
	for record: Dictionary in _entries.values():
		if Data.matches(record, query): result.append(record.duplicate(true))
	return result

func find_similar(type: String, topic: String, target: Variant, provenance: Dictionary) -> Array:
	# Occurrence ID is deliberately not the aggregation key. The caller decides
	# whether another experience reinforces one result or becomes a distinct record.
	return find({"type": type, "topic": topic, "target": target, "provenance": provenance})

func add(record: Dictionary) -> bool:
	var entry := prepare_add(record)
	if entry.is_empty(): return false
	_apply_event_add(entry)
	changed.emit(entry.id)
	return true

func prepare_add(record: Dictionary) -> Dictionary:
	if not _valid(record) or _entries.has(record.id): return {}
	var entry := record.duplicate(true)
	entry.owner = owner()
	entry.target = entry.get("target")
	entry.tags = entry.get("tags", [])
	entry.context = entry.get("context", {})
	entry.permanent = entry.get("permanent", false)
	entry["participants"] = entry.get("participants", [])
	entry.last_reinforced_minute = entry.created_minute
	entry.last_changed_minute = entry.created_minute
	entry.last_source_occurrence_id = entry.source_occurrence_id
	return entry

func _apply_event_add(prepared: Dictionary) -> void:
	# Internal commit primitive: only after the whole event has been validated.
	# No validation, signals, callbacks or fallible gameplay operations here.
	_version_sequence += 1
	var entry := prepared.duplicate(true)
	entry["_version"] = _version_sequence
	_entries[entry.id] = entry

func prepare_reinforce(entry_id: String, amount: float, minute: int, source: String, expected_version: int) -> Dictionary:
	if not _entries.has(entry_id) or not Data.number(amount) or amount <= 0 or not Data.text(source): return {}
	var entry: Dictionary = _entries[entry_id]
	if entry._version != expected_version or minute < entry.last_changed_minute: return {}
	var updated := entry.duplicate(true)
	updated.strength = minf(100, entry.strength + amount)
	updated.last_reinforced_minute = minute
	updated.last_changed_minute = minute
	updated.last_source_occurrence_id = source
	return {"id":entry_id,"expected_version":expected_version,"record":updated}

func _apply_event_update(prepared: Dictionary) -> void:
	_apply_event_add(prepared.record)

func reinforce(entry_id: String, amount: float, minute: int, source_occurrence_id: String) -> bool:
	var prepared := prepare_reinforce(entry_id,amount,minute,source_occurrence_id,int(_entries.get(entry_id,{}).get("_version",-1)))
	if prepared.is_empty(): return false
	_apply_event_update(prepared)
	changed.emit(entry_id)
	return true

func weaken(entry_id: String, amount: float, minute: int, removal_threshold: float) -> bool:
	if not _entries.has(entry_id) or not Data.number(amount) or amount <= 0: return false
	if not Data.number(removal_threshold) or removal_threshold < 0 or removal_threshold > 100: return false
	var entry: Dictionary = _entries[entry_id].duplicate(true)
	if minute < entry.last_changed_minute: return false
	entry.strength = maxf(0.0, entry.strength - amount)
	entry.last_changed_minute = minute
	if not entry.permanent and entry.strength <= removal_threshold: _entries.erase(entry_id)
	else: _apply_event_add(entry)
	changed.emit(entry_id)
	return true

func remove(entry_id: String) -> bool:
	if not _entries.erase(entry_id): return false
	changed.emit(entry_id)
	return true

func _valid(record: Dictionary) -> bool:
	if not Data.text(_owner_id) or not Data.json_value(record) or not Facts.plain(record): return false
	if not Data.only_keys(record, ["id", "type", "topic", "owner", "target", "tags", "context", "strength", "permanent", "created_minute", "source_occurrence_id", "provenance", "text", "participants"]): return false
	for key in ["id", "type", "topic", "source_occurrence_id"]:
		if not Data.text(record.get(key)): return false
	if not Data.text(record.get("text")): return false
	if not record.get("participants",[]) is Array: return false
	for participant in record.get("participants",[]):
		if not Data.entity_ref(participant): return false
	if record.has("owner") and record.owner != owner(): return false
	if record.get("target") != null and not Data.entity_ref(record.target): return false
	if not Data.tags(record.get("tags", [])) or not record.get("context", {}) is Dictionary: return false
	if not Data.minute(record.get("created_minute")) or not record.get("permanent", false) is bool: return false
	var strength: Variant = record.get("strength")
	if not Data.number(strength) or strength < 0 or strength > 100: return false
	var provenance: Variant = record.get("provenance")
	if not provenance is Dictionary or provenance.get("kind") not in ["experienced", "hearsay"]: return false
	if provenance.kind == "hearsay":
		if not Data.entity_ref(provenance.get("reported_by")) or provenance.reported_by.kind != "resident": return false
	elif provenance.has("reported_by"): return false
	return true
