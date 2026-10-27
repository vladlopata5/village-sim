extends RefCounted
## Shared data checks only. Stores never retain Nodes, Callables or live Resources.
static func text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func minute(value: Variant) -> bool:
	return value is int and value >= 0

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func entity_ref(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and text(value.get("kind")) and text(value.get("id"))

static func json_value(value: Variant, depth: int = 0) -> bool:
	# A technical nesting bound rejects recursive input, not a gameplay record limit.
	if depth > 24: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not json_value(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not json_value(value[key], depth + 1): return false
			return true
	return false

static func tags(value: Variant) -> bool:
	if not value is Array: return false
	var seen: Dictionary = {}
	for tag in value:
		if not text(tag) or seen.has(tag): return false
		seen[tag] = true
	return true

static func only_keys(value: Dictionary, allowed: Array) -> bool:
	for key in value:
		if not allowed.has(key): return false
	return true

static func matches(record: Dictionary, query: Dictionary) -> bool:
	# Exact top-level values; an empty query returns all records. No live fact reads.
	for key in query:
		if not record.has(key) or record[key] != query[key]: return false
	return true
