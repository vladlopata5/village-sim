extends RefCounted
## Resident-owned structured experiences. No clock subscription or opinion/mood effects.
const Data = preload("res://scripts/event_store_data.gd")
signal changed(entry_id: String)
var _owner_id: String
var _entries: Dictionary = {}

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
	entry.last_reinforced_minute = entry.created_minute
	entry.last_changed_minute = entry.created_minute
	entry.last_source_occurrence_id = entry.source_occurrence_id
	return entry

func _apply_event_add(prepared: Dictionary) -> void:
	# Internal commit primitive: only after the whole event has been validated.
	# No validation, signals, callbacks or fallible gameplay operations here.
	_entries[prepared.id] = prepared.duplicate(true)

func reinforce(entry_id: String, amount: float, minute: int, source_occurrence_id: String) -> bool:
	if not _entries.has(entry_id) or not Data.number(amount) or amount <= 0 or not Data.text(source_occurrence_id): return false
	var entry: Dictionary = _entries[entry_id]
	if minute < entry.last_changed_minute: return false
	entry.strength = minf(100.0, entry.strength + amount)
	entry.last_reinforced_minute = minute
	entry.last_changed_minute = minute
	entry.last_source_occurrence_id = source_occurrence_id
	changed.emit(entry_id)
	return true

func weaken(entry_id: String, amount: float, minute: int, removal_threshold: float) -> bool:
	if not _entries.has(entry_id) or not Data.number(amount) or amount <= 0: return false
	if not Data.number(removal_threshold) or removal_threshold < 0 or removal_threshold > 100: return false
	var entry: Dictionary = _entries[entry_id]
	if minute < entry.last_changed_minute: return false
	entry.strength = maxf(0.0, entry.strength - amount)
	entry.last_changed_minute = minute
	if not entry.permanent and entry.strength <= removal_threshold: _entries.erase(entry_id)
	changed.emit(entry_id)
	return true

func remove(entry_id: String) -> bool:
	if not _entries.erase(entry_id): return false
	changed.emit(entry_id)
	return true

func _valid(record: Dictionary) -> bool:
	if not Data.text(_owner_id) or not Data.json_value(record): return false
	if not Data.only_keys(record, ["id", "type", "topic", "owner", "target", "tags", "context", "strength", "permanent", "created_minute", "source_occurrence_id", "provenance"]): return false
	for key in ["id", "type", "topic", "source_occurrence_id"]:
		if not Data.text(record.get(key)): return false
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
