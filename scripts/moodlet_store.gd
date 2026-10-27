extends RefCounted
## Inert temporary state. Future consumers use ResidentModifiers, not formulas here.
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
	entry.expires_at_minute = entry.get("expires_at_minute")
	entry.modifiers = entry.get("modifiers", [])
	return entry

func _apply_event_add(prepared: Dictionary) -> void:
	# Internal commit primitive; publish only after all event writes + metadata.
	_entries[prepared.id] = prepared.duplicate(true)

func is_active(entry_id: String, minute: int) -> bool:
	if minute < 0 or not _entries.has(entry_id): return false
	var entry: Dictionary = _entries[entry_id]
	return minute >= entry.created_minute and (entry.expires_at_minute == null or minute < entry.expires_at_minute)

func active(minute: int, query: Dictionary = {}) -> Array:
	var result: Array = []
	for entry: Dictionary in find(query):
		if is_active(entry.id, minute): result.append(entry)
	return result

func expire(minute: int) -> int:
	if minute < 0: return 0
	var expired: Array = []
	for entry: Dictionary in _entries.values():
		if entry.expires_at_minute != null and entry.expires_at_minute <= minute: expired.append(entry.id)
	# Complete this local operation before notifying. A callback may add another ID;
	# it must not be silently erased by the rest of this expiration pass.
	for entry_id: String in expired: _entries.erase(entry_id)
	for entry_id: String in expired: changed.emit(entry_id)
	return expired.size()

func remove(entry_id: String) -> bool:
	if not _entries.erase(entry_id): return false
	changed.emit(entry_id)
	return true

func _valid(record: Dictionary) -> bool:
	if not Data.text(_owner_id) or not Data.json_value(record): return false
	if not Data.only_keys(record, ["id", "type", "owner", "target", "tags", "context", "created_minute", "expires_at_minute", "source_occurrence_id", "modifiers"]): return false
	for key in ["id", "type", "source_occurrence_id"]:
		if not Data.text(record.get(key)): return false
	if record.has("owner") and record.owner != owner(): return false
	if record.get("target") != null and not Data.entity_ref(record.target): return false
	if not Data.tags(record.get("tags", [])) or not record.get("context", {}) is Dictionary: return false
	if not Data.minute(record.get("created_minute")): return false
	var expiry: Variant = record.get("expires_at_minute")
	if expiry != null and (not Data.minute(expiry) or expiry < record.created_minute): return false
	var modifiers: Variant = record.get("modifiers", [])
	if not modifiers is Array: return false
	for modifier in modifiers:
		if not modifier is Dictionary: return false
	return true
