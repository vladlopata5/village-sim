extends RefCounted
## Deliberately disconnected from the game. Never executes effects or writes history.
const Facts = preload("res://scripts/event_facts.gd")
const Evaluator = preload("res://scripts/event_expression.gd")
var catalog: RefCounted
var facts: RefCounted
var rng: RefCounted = RandomNumberGenerator.new()
var _chances: Dictionary = {}
var _seen: Dictionary = {}

func _init(event_catalog: RefCounted, fact_registry: RefCounted) -> void:
	catalog = event_catalog
	facts = fact_registry
	rng.seed = 0

func set_chance(trigger: String, chance: float) -> bool:
	if trigger.is_empty() or not is_finite(chance) or chance < 0.0 or chance > 1.0: return false
	_chances[trigger] = chance
	return true

func clear_session() -> void:
	_seen.clear()

func run(context: Dictionary, history: Dictionary = {}, diagnostic: bool = false) -> Dictionary:
	var result := {"status": "invalid_context", "chance_passed": false, "eligible": [], "selected": {}, "roles": {}, "bindings": {}, "main": null, "rejected": [], "definitions_checked": 0, "duplicate": false}
	if not Facts.plain(context) or not context.get("occurrence_id") is String or context.occurrence_id.is_empty(): return result
	if not context.get("trigger") is String or not _chances.has(context.trigger) or not _minute(context.get("minute")): return result
	var token: String = context.occurrence_id
	if _seen.has(token):
		result = _seen[token].duplicate(true)
		result.duplicate = true
		return result
	# Only valid opportunities consume a draw. Even chance 0/1 uses exactly one.
	var roll: float = rng.randf()
	if not _random_valid(roll):
		result.status = "invalid_rng"
		return _remember(token, result)
	var chance: float = _chances[context.trigger]
	if chance < 1.0 and roll >= chance:
		result.status = "chance_failed"
		return _remember(token, result)
	result.chance_passed = true
	var candidates: Array = []
	var tables: Dictionary = catalog.get_tables()
	for definition in catalog.definitions_for(context.trigger):
		result.definitions_checked += 1
		var match_result := _match(definition, context, tables, history)
		if not match_result.get("ok", false):
			if diagnostic: result.rejected.append({"id": definition.id, "reason": match_result.reason})
			if "budget" in match_result.reason:
				result.status = "evaluation_error"
				return _remember(token, result)
			continue
		result.eligible.append(definition.id)
		if definition.weight > 0: candidates.append({"definition": definition, "match": match_result})
	if candidates.is_empty():
		result.status = "no_match"
		return _remember(token, result)
	# Normalize before adding, so finite very large weights cannot overflow the sum.
	var maximum := 0.0
	for item in candidates: maximum = maxf(maximum, item.definition.weight)
	var total := 0.0
	for item in candidates: total += item.definition.weight / maximum
	roll = rng.randf()
	if not _random_valid(roll):
		result.status = "invalid_rng"
		return _remember(token, result)
	var threshold := roll * total
	var chosen: Dictionary = candidates.back()
	for item in candidates:
		threshold -= item.definition.weight / maximum
		if threshold < 0.0:
			chosen = item
			break
	result.status = "selected"
	result.selected = chosen.definition
	result.roles = chosen.match.env.role
	result.bindings = chosen.match.env.binding
	result.tables = chosen.match.env.catalog # Frozen tables for consequence expressions.
	result.main = chosen.match.main
	result.cooldown_key = chosen.match.cooldown_key
	result.cooldown_keys = chosen.match.cooldown_keys
	return _remember(token, result)

func _remember(token: String, result: Dictionary) -> Dictionary:
	_seen[token] = result.duplicate(true)
	return result.duplicate(true)

func _match(definition: Dictionary, context: Dictionary, tables: Dictionary, history: Dictionary) -> Dictionary:
	if not definition.enabled: return _reject("disabled")
	var evaluator := Evaluator.new()
	var env := {"ctx": context, "role": {}, "binding": {}, "param": definition.get("params", {}), "catalog": tables, "local": {}}
	for name in definition.roles:
		var role: Dictionary = definition.roles[name]
		var resolved: Dictionary = evaluator.evaluate({"ctx": role.from.trim_prefix("ctx.")}, env, facts)
		if not resolved.known or not facts.valid_entity(resolved.value, role.type, role.get("active_required", true)): return _reject("invalid role: " + name)
		env.role[name] = resolved.value
	for name in definition.roles:
		for other in definition.roles[name].get("different_from", []):
			if Facts.ref_key(env.role[name]) == Facts.ref_key(env.role[other]): return _reject("roles must differ: " + name)
	var bindings := evaluator.resolve_bindings(definition.get("bind", []), env, facts)
	if not bindings.known: return _reject(bindings.reason)
	env.binding = bindings.value
	var condition := evaluator.evaluate(definition.get("when", true), env, facts)
	if not condition.known: return _reject(condition.reason)
	if not condition.value is bool: return _reject("when type mismatch")
	if not condition.value: return _reject("condition false")
	var main: Variant = env.role.get(definition.main_role, env.binding.get(definition.main_role))
	if not facts.valid_entity(main): return _reject("invalid main participant")
	var cooldown_key := ""
	var cooldown_keys: Array = []
	if definition.has("cooldown"):
		var scope: Array = []
		for expression in definition.cooldown.get("scope", []):
			var value := evaluator.evaluate(expression, env, facts)
			if not value.known: return _reject(value.reason)
			if Facts.value_type(value.value) not in ["entity", "string", "number", "bool", "null"]: return _reject("invalid cooldown scope type")
			scope.append([value.value.kind, value.value.id] if Facts.is_ref(value.value) else value.value)
		cooldown_key = JSON.stringify([definition.id, scope])
		cooldown_keys.append(cooldown_key)
		if definition.cooldown.get("symmetric", false):
			scope.reverse()
			var reverse_key := JSON.stringify([definition.id, scope])
			if reverse_key not in cooldown_keys: cooldown_keys.append(reverse_key)
		for key in cooldown_keys:
			if history.has(key):
				if not _minute(history[key]): return _reject("invalid cooldown history")
				if context.minute < history[key] + definition.cooldown.minutes: return _reject("cooldown")
	return {"ok": true, "env": env, "main": main, "cooldown_key": cooldown_key, "cooldown_keys": cooldown_keys}

func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _minute(value: Variant) -> bool:
	return Facts.value_type(value) == "number" and is_finite(float(value)) and value >= 0 and floor(float(value)) == float(value)

static func _random_valid(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0
