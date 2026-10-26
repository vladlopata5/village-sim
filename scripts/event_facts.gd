extends RefCounted
## Isolated, JSON-only snapshots. No Nodes, property access or executable readers.
## Adapters may populate this registry before a dry-run; evaluation only reads it.
const MAX_COLLECTION := 256
const MAX_DEPTH := 24
var _schemas: Dictionary = {}
var _entities: Dictionary = {}
var _values: Dictionary = {}

static func unknown(reason: String = "unknown") -> Dictionary:
	return {"known": false, "value": null, "reason": reason}

static func known(value: Variant) -> Dictionary:
	return {"known": true, "value": value}

static func value_type(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT, TYPE_FLOAT: return "number"
		TYPE_STRING: return "string"
		TYPE_ARRAY: return "array"
		TYPE_DICTIONARY:
			if is_ref(value): return "entity"
			return "record"
	return "invalid"

static func is_ref(value: Variant) -> bool:
	return value is Dictionary and value.size() == 2 and value.get("kind") is String and not value.kind.is_empty() and value.get("id") is String and not value.id.is_empty()

static func plain(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			if value.size() > MAX_COLLECTION: return false
			for item in value:
				if not plain(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_COLLECTION: return false
			for key in value:
				if not (key is String or key is StringName) or not plain(value[key], depth + 1): return false
			return true
	return false

static func copy_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value

static func ref_key(entity: Dictionary) -> String:
	return JSON.stringify([entity.get("kind"), entity.get("id")])

func register_fact(key: String, kind: String, type: String, argument_type: String = "none", nullable: bool = false) -> bool:
	if key.is_empty() or kind.is_empty() or _schemas.has(key): return false
	if type not in ["bool", "number", "string", "array", "record", "entity"]: return false
	if argument_type not in ["none", "bool", "number", "string", "entity"]: return false
	_schemas[key] = {"kind": kind, "type": type, "argument_type": argument_type, "nullable": nullable}
	return true

func schema(key: String) -> Dictionary:
	return _schemas.get(key, {}).duplicate()

func register_entity(entity: Dictionary, active: bool = true) -> bool:
	if not plain(entity) or not is_ref(entity): return false
	_entities[ref_key(entity)] = active
	return true

func valid_entity(entity: Variant, kind: String = "", active_required: bool = true) -> bool:
	if not is_ref(entity): return false
	if not kind.is_empty() and entity.kind != kind: return false
	var key := ref_key(entity)
	return _entities.has(key) and (not active_required or _entities[key])

func set_value(entity: Dictionary, key: String, value: Variant, argument: Variant = null) -> bool:
	var rule := schema(key)
	if rule.is_empty() or not valid_entity(entity, rule.kind, false): return false
	if not _argument_valid(rule, argument) or not plain(value): return false
	if value == null:
		if not rule.nullable: return false
	elif value_type(value) != rule.type: return false
	_values[_value_key(entity, key, argument)] = copy_value(value)
	return true

func read(entity: Variant, key: Variant, argument: Variant = null) -> Dictionary:
	if not key is String: return unknown("fact key must be string")
	var rule := schema(key)
	if rule.is_empty(): return unknown("unregistered fact: " + key)
	if not valid_entity(entity, rule.kind, false): return unknown("invalid fact entity: " + key)
	if not _argument_valid(rule, argument): return unknown("invalid fact argument: " + key)
	var token := _value_key(entity, key, argument)
	if not _values.has(token): return unknown("missing fact: " + key)
	return known(copy_value(_values[token]))

func _argument_valid(rule: Dictionary, argument: Variant) -> bool:
	return argument == null if rule.argument_type == "none" else value_type(argument) == rule.argument_type and plain(argument)

func _value_key(entity: Dictionary, key: String, argument: Variant) -> String:
	var arg: Variant = [argument.kind, argument.id] if is_ref(argument) else argument
	return JSON.stringify([entity.kind, entity.id, key, arg])
