extends RefCounted
## Shared state for unordered pairs. Directed opinions belong to ResidentData.
const TRANSITION_COOLDOWN_MINUTES := 10080
const LEVEL_NAMES := ["Заклятые враги", "Враги", "Неприязнь", "Знакомые / нет выраженной связи", "Приятели", "Друзья", "Близкие друзья"]

var _residents: Dictionary = {}
var _pairs: Dictionary = {}
var _neighbors: Dictionary = {}
var _sequence := 0

static func valid_level(level: Variant) -> bool:
	return level is int and level >= -3 and level <= 3

static func level_name(level: int) -> String:
	return LEVEL_NAMES[level + 3] if valid_level(level) else ""

func knows_id(id: String) -> bool:
	return _residents.has(id)

func resident_for(id: String) -> RefCounted:
	return _residents[id].reference.get_ref() if knows_id(id) else null

func known_residents() -> Array:
	var residents: Array = []
	for id in _residents:
		var resident := resident_for(id)
		if resident != null: residents.append(resident)
	return residents

func register_resident(resident: RefCounted) -> bool:
	if resident == null or resident.id.strip_edges().is_empty(): return false
	if knows_id(resident.id): return resident_for(resident.id) == resident
	_sequence += 1
	_residents[resident.id] = {"reference": weakref(resident), "generation": _sequence}
	resident.bind_social_links(self)
	return true

func forget_resident(id: String) -> void:
	for other in _neighbors.get(id, {}):
		_pairs.erase(_pair_key(id, other))
		_neighbors[other].erase(id)
		if _neighbors[other].is_empty(): _neighbors.erase(other)
	_neighbors.erase(id)
	_residents.erase(id)

static func _pair_key(first: String, second: String) -> String:
	return JSON.stringify([first, second] if first < second else [second, first])

func _valid_pair(first: RefCounted, second: RefCounted) -> bool:
	return first != null and second != null and first.id != second.id and resident_for(first.id) == first and resident_for(second.id) == second

func get_link(first: RefCounted, second: RefCounted) -> Dictionary:
	if not _valid_pair(first, second): return {}
	return _pairs.get(_pair_key(first.id, second.id), {"link_level": 0, "normal_transition_available_at": null, "revision": 0}).duplicate()

func get_level(first: RefCounted, second: RefCounted) -> int:
	if not _valid_pair(first, second): return 0
	return _pairs.get(_pair_key(first.id, second.id), {}).get("link_level", 0)

func normal_transition_ready(first: RefCounted, second: RefCounted, minute: int) -> bool:
	var link := get_link(first, second)
	return minute >= 0 and not link.is_empty() and (link.normal_transition_available_at == null or minute >= link.normal_transition_available_at)

func prepare_transition(first: RefCounted, second: RefCounted, level: Variant, minute: int, special: bool = false) -> Dictionary:
	var link := get_link(first, second)
	if not _can_transition(link, level, minute, special): return {}
	return {
		"store_id": get_instance_id(),
		"first": first.id, "second": second.id,
		"first_generation": _residents[first.id].generation,
		"second_generation": _residents[second.id].generation,
		"revision": link.revision, "level": level, "special": special,
	}

func commit_transition(prepared: Dictionary, minute: int) -> bool:
	if prepared.get("store_id") != get_instance_id(): return false
	var first_id: Variant = prepared.get("first")
	var second_id: Variant = prepared.get("second")
	if not first_id is String or not second_id is String: return false
	var first := resident_for(first_id)
	var second := resident_for(second_id)
	if not _valid_pair(first, second): return false
	if _residents[first_id].generation != prepared.get("first_generation"): return false
	if _residents[second_id].generation != prepared.get("second_generation"): return false
	var link := get_link(first, second)
	var level: Variant = prepared.get("level")
	var special: Variant = prepared.get("special")
	if not special is bool or link.revision != prepared.get("revision"): return false
	if not _can_transition(link, level, minute, special): return false
	_sequence += 1
	_pairs[_pair_key(first_id, second_id)] = {
		"link_level": level, "normal_transition_available_at": minute + TRANSITION_COOLDOWN_MINUTES,
		"revision": _sequence,
	}
	if not _neighbors.has(first_id): _neighbors[first_id] = {}
	if not _neighbors.has(second_id): _neighbors[second_id] = {}
	_neighbors[first_id][second_id] = true
	_neighbors[second_id][first_id] = true
	return true

static func _can_transition(link: Dictionary, level: Variant, minute: int, special: bool) -> bool:
	if link.is_empty() or not valid_level(level) or minute < 0 or minute > 9223372036854775807 - TRANSITION_COOLDOWN_MINUTES or level == link.link_level: return false
	if special: return true
	return absi(level - link.link_level) == 1 and (link.normal_transition_available_at == null or minute >= link.normal_transition_available_at)

func counts_for(resident: RefCounted) -> Dictionary:
	if resident == null or resident_for(resident.id) != resident: return {}
	var counts := {"positive_1": 0, "positive_2": 0, "positive_3": 0, "negative_1": 0, "negative_2": 0, "negative_3": 0}
	for other in _neighbors.get(resident.id, {}):
		_accumulate(counts, get_level(resident, resident_for(other)), 1)
	return counts

func counts_after_transition(resident: RefCounted, other: RefCounted, level: Variant) -> Dictionary:
	if not _valid_pair(resident, other) or not valid_level(level): return {}
	var counts := counts_for(resident)
	_accumulate(counts, get_level(resident, other), -1)
	_accumulate(counts, level, 1)
	return counts

static func _accumulate(counts: Dictionary, level: int, amount: int) -> void:
	var prefix := "positive_" if level > 0 else "negative_"
	for threshold in range(1, absi(level) + 1):
		counts[prefix + str(threshold)] += amount
