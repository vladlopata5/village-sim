extends RefCounted
## Temporary state; numeric formulas remain in ResidentModifiers.
const Data = preload("res://scripts/event_store_data.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const EVENT_REFRESH_TYPES = {
	"angry": preload("res://scripts/balance_config.gd").ANGRY_MOODLET_MINUTES,
	"well_fed": preload("res://scripts/balance_config.gd").GLUTTON_WELL_FED_MINUTES,
}
signal changed(entry_id: String)
var _owner_id: String
var _entries: Dictionary = {}
var _next_expiry_minute := -1 # No timed records. Derived deadline, never a second effect store.
var _growth_dirty := true
var _growth_factors: Dictionary = {}
var _growth_minute := -1
var _next_growth_change := -1

func _init(owner_id: String) -> void:
	_owner_id = owner_id

func owner() -> Dictionary:
	return {"kind": "resident", "id": _owner_id}

func size() -> int:
	return _entries.size()

func next_expiry_minute() -> int:
	return _next_expiry_minute

func need_growth_factors(minute: int) -> Dictionary:
	if minute<0: return {}
	if _growth_dirty or minute<_growth_minute or (_next_growth_change>=0 and minute>=_next_growth_change):
		_rebuild_growth_cache(minute)
	return _growth_factors.duplicate() # Minute-local consumer snapshot; callers cannot mutate the cache.

func _rebuild_growth_cache(minute: int) -> void:
	var state := Modifiers.moodlet_need_growth_state(_entries.values(),minute)
	_growth_factors=state.factors
	_next_growth_change=state.next_change
	_growth_minute=minute
	_growth_dirty=false

func _update_next_expiry() -> void:
	_next_expiry_minute = -1
	for entry: Dictionary in _entries.values():
		if entry.expires_at_minute != null and (_next_expiry_minute < 0 or entry.expires_at_minute < _next_expiry_minute):
			_next_expiry_minute = entry.expires_at_minute

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
	return _prepare_record(record)

func add_or_refresh(record: Dictionary) -> bool:
	# Explicit singleton API; event-specific policies are prepared separately below.
	var prepared := _prepare_refresh(record)
	if prepared.is_empty(): return false
	_apply_event_add(prepared)
	changed.emit(prepared.id)
	return true

func prepare_event_add(record: Dictionary) -> Dictionary:
	# Explicit per-type event policy. Other definitions keep independent occurrence IDs.
	if not EVENT_REFRESH_TYPES.has(record.get("type")): return prepare_add(record)
	if not _valid(record): return {}
	var duration: int = EVENT_REFRESH_TYPES[record.type]
	if record.created_minute > 9223372036854775807-duration or record.get("expires_at_minute") != record.created_minute+duration: return {}
	var singleton := record.duplicate(true)
	singleton.id = record.type
	return _prepare_refresh(singleton)

func _prepare_refresh(record: Dictionary) -> Dictionary:
	if not _valid(record): return {}
	var previous: Dictionary = _entries.get(record.id, {})
	if not previous.is_empty():
		if previous.type != record.type or previous.source_occurrence_id == record.source_occurrence_id: return {}
		if record.created_minute < previous.created_minute: return {}
	return _prepare_record(record)

func _prepare_record(record: Dictionary) -> Dictionary:
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
	_growth_dirty=true
	_update_next_expiry()

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
	if minute < 0 or _next_expiry_minute < 0 or minute < _next_expiry_minute: return 0
	var expired: Array = []
	for entry: Dictionary in _entries.values():
		if entry.expires_at_minute != null and entry.expires_at_minute <= minute: expired.append(entry.id)
	# Complete this local operation before notifying. A callback may add another ID;
	# it must not be silently erased by the rest of this expiration pass.
	for entry_id: String in expired: _entries.erase(entry_id)
	_growth_dirty=true
	_update_next_expiry() # Before callbacks: their changes must retain their own next deadline.
	for entry_id: String in expired: changed.emit(entry_id)
	return expired.size()

func remove(entry_id: String) -> bool:
	if not _entries.erase(entry_id): return false
	_growth_dirty=true
	_update_next_expiry()
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
		if not modifier is Dictionary or not Modifiers.valid_moodlet_modifier(modifier): return false
	return true
