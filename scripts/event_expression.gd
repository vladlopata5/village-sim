extends RefCounted
## A finite expression vocabulary. Unknown is an envelope, never a JSON null.
const Facts = preload("res://scripts/event_facts.gd")
const MAX_NODES := 512
const MAX_DEPTH := 24
const MAX_STEPS := 32768
const REF_OPS := ["role", "binding", "param", "catalog", "local", "ctx"]
const BINARY_OPS := ["eq", "ne", "lt", "lte", "gt", "gte", "add", "sub", "has_tag", "field"]
const OPERATORS := REF_OPS + BINARY_OPS + ["fact", "all", "any", "not", "list", "exists", "if"]
var visits := 0
var budget_exceeded := false

func validate(expression: Variant, names: Dictionary, facts: RefCounted, errors: Array, path: String = "when", depth: int = 0) -> String:
	visits += 1
	if depth > MAX_DEPTH or visits > MAX_NODES:
		errors.append(path + ": expression complexity exceeded")
		return "invalid"
	if not expression is Dictionary:
		var type := Facts.value_type(expression)
		if type in ["array", "invalid"]: errors.append(path + ": use list for expression arrays; objects forbidden")
		return type
	if expression.size() != 1:
		errors.append(path + ": expected one expression operator")
		return "invalid"
	var op: String = expression.keys()[0]
	var value: Variant = expression[op]
	if op in REF_OPS:
		if not value is String or value.is_empty():
			errors.append(path + ": invalid " + op + " reference")
			return "invalid"
		if op == "ctx": return "any"
		if not names.get(op, {}).has(value):
			errors.append(path + ": unknown " + op + " " + value)
			return "invalid"
		return names[op][value]
	if op == "if":
		if not value is Array or value.size() != 3:
			errors.append(path + ": if requires condition/then/else")
			return "invalid"
		var condition := validate(value[0], names, facts, errors, path + "/if/0", depth + 1)
		if condition not in ["bool", "any", "invalid"]: errors.append(path + ": if condition must be bool")
		var yes := validate(value[1], names, facts, errors, path + "/if/1", depth + 1)
		var no := validate(value[2], names, facts, errors, path + "/if/2", depth + 1)
		return yes if yes == no else "any"
	if op in ["all", "any", "list"]:
		if not value is Array or value.size() > Facts.MAX_COLLECTION:
			errors.append(path + ": invalid bounded array")
			return "invalid"
		for item in value:
			var type := validate(item, names, facts, errors, path + "/" + op, depth + 1)
			if op != "list" and type not in ["bool", "any", "invalid"]: errors.append(path + ": logical operand must be bool")
		return "array" if op == "list" else "bool"
	if op == "not":
		var type := validate(value, names, facts, errors, path + "/not", depth + 1)
		if type not in ["bool", "any", "invalid"]: errors.append(path + ": NOT requires bool")
		return "bool"
	if op == "exists":
		_validate_query(value, names, facts, errors, path, depth)
		return "bool"
	if op == "fact":
		if not value is Array or value.size() not in [2, 3]:
			errors.append(path + ": fact expects entity/key[/argument]")
			return "invalid"
		var owner_type := validate(value[0], names, facts, errors, path + "/entity", depth + 1)
		if owner_type not in ["entity", "any", "invalid"]: errors.append(path + ": fact owner must be entity")
		var key_type := validate(value[1], names, facts, errors, path + "/key", depth + 1)
		if key_type not in ["string", "any", "invalid"]: errors.append(path + ": fact key must be string")
		var arg_type := "none"
		if value.size() == 3: arg_type = validate(value[2], names, facts, errors, path + "/arg", depth + 1)
		if value[1] is String:
			var rule: Dictionary = facts.schema(value[1])
			if rule.is_empty(): errors.append(path + ": unregistered fact " + value[1])
			else:
				if arg_type != "any" and arg_type != rule.argument_type: errors.append(path + ": incompatible fact argument")
				return rule.type
		return "any" # Dynamic keys still go through the same registered, typed reader.
	if op in BINARY_OPS:
		if not value is Array or value.size() != 2:
			errors.append(path + ": binary operator requires two operands")
			return "invalid"
		var left := validate(value[0], names, facts, errors, path + "/0", depth + 1)
		var right := validate(value[1], names, facts, errors, path + "/1", depth + 1)
		if op == "field":
			if left not in ["record", "entity", "any", "invalid"] or right not in ["string", "any", "invalid"]: errors.append(path + ": field requires record/string")
			return "any"
		if op == "has_tag":
			if left not in ["record", "entity", "any", "invalid"] or right not in ["string", "any", "invalid"]: errors.append(path + ": has_tag requires record/string")
			return "bool"
		if op in ["add", "sub", "lt", "lte", "gt", "gte"]:
			if left not in ["number", "any", "invalid"] or right not in ["number", "any", "invalid"]: errors.append(path + ": numeric operands required")
		elif left != right and "any" not in [left, right] and "null" not in [left, right]:
			errors.append(path + ": incompatible equality operands")
		return "number" if op in ["add", "sub"] else "bool"
	errors.append(path + ": unknown operation " + op)
	return "invalid"

## Resolve in order so later declarations can reference earlier bindings.
func resolve_bindings(declarations: Array, env: Dictionary, facts: RefCounted) -> Dictionary:
	var scope := env.duplicate()
	scope.binding = {}
	for binding: Dictionary in declarations:
		var value: Dictionary
		if binding.has("select"):
			value = select_one(binding.select, scope, facts)
			if value.known and value.value == null: return Facts.unknown("empty binding: " + binding.as)
		else:
			value = evaluate(binding.value, scope, facts)
		if not value.known: return value
		if not Facts.plain(value.value): return Facts.unknown("collection requires a query")
		if binding.get("type", "") == "resident_ref" and not facts.valid_entity(value.value, "resident", binding.get("active_required", true)):
			return Facts.unknown("invalid bound resident: " + binding.as)
		scope.binding[binding.as] = value.value
	return Facts.known(scope.binding)

func _validate_query(query: Variant, names: Dictionary, facts: RefCounted, errors: Array, path: String, depth: int) -> void:
	if not query is Dictionary or not query.has("from") or not query.has("where") or query.get("as") != "candidate":
		errors.append(path + ": query requires from/as:candidate/where")
		return
	var type := validate(query.from, names, facts, errors, path + "/from", depth + 1)
	if type not in ["array", "collection", "any", "invalid"]: errors.append(path + ": query source must be array")
	var inner := names.duplicate(true)
	inner.local = {"candidate": "any"}
	type = validate(query.where, inner, facts, errors, path + "/where", depth + 1)
	if type not in ["bool", "any", "invalid"]: errors.append(path + ": query predicate must be bool")

func evaluate(expression: Variant, env: Dictionary, facts: RefCounted) -> Dictionary:
	visits = 0
	budget_exceeded = false
	if not Facts.plain(expression): return Facts.unknown("expression is not bounded JSON data")
	var result := _eval(expression, env, facts)
	return Facts.unknown("expression budget exceeded") if budget_exceeded else result

func _eval(expression: Variant, env: Dictionary, facts: RefCounted, depth: int = 0) -> Dictionary:
	visits += 1
	if visits > MAX_STEPS or depth > MAX_DEPTH: return _budget()
	if not expression is Dictionary: return Facts.known(expression)
	if expression.size() != 1: return Facts.unknown("invalid expression shape")
	var op: String = expression.keys()[0]
	var arg: Variant = expression[op]
	if op in REF_OPS:
		if op == "ctx": return _path(env.ctx, arg)
		return Facts.known(env[op][arg]) if env.get(op, {}).has(arg) else Facts.unknown("missing " + op + ": " + arg)
	if op == "if":
		if not arg is Array or arg.size() != 3: return Facts.unknown("invalid if operands")
		var condition := _eval(arg[0], env, facts, depth + 1)
		if not condition.known: return condition
		if not condition.value is bool: return Facts.unknown("if condition must be bool")
		return _eval(arg[1] if condition.value else arg[2], env, facts, depth + 1)
	if op in ["all", "any"]:
		var uncertain := false
		for item in arg:
			var result := _eval(item, env, facts, depth + 1)
			if not result.known:
				uncertain = true
			elif not result.value is bool: return Facts.unknown("logical type mismatch")
			elif (op == "all" and not result.value) or (op == "any" and result.value): return result
		if uncertain: return Facts.unknown("logical operand unknown")
		return Facts.known(op == "all")
	if op == "not":
		var result := _eval(arg, env, facts, depth + 1)
		if not result.known: return result
		return Facts.known(not result.value) if result.value is bool else Facts.unknown("NOT type mismatch")
	if op == "list":
		var items: Array = []
		for item in arg:
			var result := _eval(item, env, facts, depth + 1)
			if not result.known: return result
			items.append(result.value)
		return Facts.known(items)
	if op == "exists":
		return _exists(arg, env, facts, depth + 1)
	if op not in BINARY_OPS and op != "fact": return Facts.unknown("unsupported operation: " + op)
	if not arg is Array or (arg.size() != 2 and not (op == "fact" and arg.size() == 3)): return Facts.unknown("invalid operands")
	var operands: Array = []
	for item in arg:
		var result := _eval(item, env, facts, depth + 1)
		if not result.known: return result
		operands.append(result.value)
	if op == "fact": return facts.read(operands[0], operands[1], operands[2] if operands.size() == 3 else null)
	var left: Variant = operands[0]
	var right: Variant = operands[1]
	if op == "field": return _path(left, right) if right is String else Facts.unknown("field type mismatch")
	if op == "has_tag":
		if not right is String: return Facts.unknown("tag type mismatch")
		var tags: Dictionary = facts.read(left, "tags") if Facts.is_ref(left) else _path(left, "tags")
		if not tags.known: return tags
		return Facts.known(right in tags.value) if tags.value is Array else Facts.unknown("tags must be array")
	if op in ["eq", "ne"]:
		var a := Facts.value_type(left)
		var b := Facts.value_type(right)
		if a != b and "null" not in [a, b]: return Facts.unknown("equality type mismatch")
		var equal: bool = Facts.ref_key(left) == Facts.ref_key(right) if a == "entity" and b == "entity" else left == right
		return Facts.known(equal if op == "eq" else not equal)
	if Facts.value_type(left) != "number" or Facts.value_type(right) != "number": return Facts.unknown("numeric type mismatch")
	match op:
		"lt": return Facts.known(left < right)
		"lte": return Facts.known(left <= right)
		"gt": return Facts.known(left > right)
		"gte": return Facts.known(left >= right)
		"add", "sub":
			var value: float = float(left) + float(right) if op == "add" else float(left) - float(right)
			return Facts.known(value) if is_finite(value) else Facts.unknown("non-finite arithmetic")
	return Facts.unknown("unsupported operation")

func select_values(query: Dictionary, env: Dictionary, facts: RefCounted, depth: int = 0) -> Dictionary:
	if depth == 0:
		visits = 0
		budget_exceeded = false
	var source := _eval(query.from, env, facts, depth + 1)
	if not source.known: return source
	if not source.value is Array: return Facts.unknown("query source type mismatch")
	if source.value.size() > Facts.MAX_COLLECTION: return _budget()
	var matches: Array = []
	var uncertain := false
	for candidate in source.value:
		var inner := env.duplicate()
		inner.local = {"candidate": candidate}
		var result := _eval(query.where, inner, facts, depth + 1)
		if not result.known: uncertain = true
		elif not result.value is bool: return Facts.unknown("query predicate type mismatch")
		elif result.value: matches.append(candidate)
	# Unknown candidates cannot silently alter deterministic binding selection.
	if budget_exceeded: return _budget()
	if uncertain: return Facts.unknown("query candidate unknown")
	return Facts.known(matches)

func select_one(query: Dictionary, env: Dictionary, facts: RefCounted) -> Dictionary:
	visits = 0; budget_exceeded = false
	var source := _eval(query.from,env,facts)
	if not source.known: return source
	if not source.value is Facts.Collection:
		var matches := select_values(query,env,facts)
		if not matches.known: return matches
		return _first_match(matches.value,query.order_by)
	var best: Variant = null
	var best_key: Variant = null
	var uncertain := false
	var base_visits := visits
	# A finite immutable snapshot is streamed completely. Existing AST/depth/step
	# limits apply to each predicate, not to an arbitrary prefix of the journal.
	for page_index in source.value.page_count():
		for candidate in source.value.page(page_index):
			visits = base_visits
			var inner := env.duplicate(); inner.local = {"candidate":candidate}
			var result := _eval(query.where,inner,facts)
			if budget_exceeded: return _budget()
			if not result.known: uncertain = true; continue
			if not result.value is bool: return Facts.unknown("query predicate type mismatch")
			if not result.value: continue
			var key: Variant = candidate.get("id") if query.order_by == "id" else candidate
			if Facts.value_type(key) not in ["number","string"] or (best != null and Facts.value_type(key) != Facts.value_type(best_key)): return Facts.unknown("invalid binding sort key")
			if best == null or key < best_key: best = candidate; best_key = key
	if uncertain: return Facts.unknown("query candidate unknown")
	return Facts.known(best)

func _first_match(matches: Array, order: String) -> Dictionary:
	var best: Variant = null; var best_key: Variant = null
	for candidate in matches:
		var key: Variant = candidate.get("id") if order == "id" and candidate is Dictionary else candidate if order == "value" else null
		if Facts.value_type(key) not in ["number","string"] or (best != null and Facts.value_type(key) != Facts.value_type(best_key)): return Facts.unknown("invalid binding sort key")
		if best == null or key < best_key: best = candidate; best_key = key
	return Facts.known(best)

func _exists(query: Dictionary, env: Dictionary, facts: RefCounted, depth: int) -> Dictionary:
	var source := _eval(query.from, env, facts, depth + 1)
	if not source.known: return source
	if source.value is Facts.Collection:
		var uncertain_collection := false
		var base_visits := visits
		for page_index in source.value.page_count():
			for candidate in source.value.page(page_index):
				visits = base_visits
				var inner := env.duplicate(); inner.local = {"candidate":candidate}
				var result := _eval(query.where,inner,facts,depth+1)
				if budget_exceeded: return _budget()
				if not result.known: uncertain_collection = true
				elif not result.value is bool: return Facts.unknown("query predicate type mismatch")
				elif result.value: return Facts.known(true)
		return Facts.unknown("query candidate unknown") if uncertain_collection else Facts.known(false)
	if not source.value is Array: return Facts.unknown("query source type mismatch")
	if source.value.size() > Facts.MAX_COLLECTION: return _budget()
	var uncertain := false
	for candidate in source.value:
		var inner := env.duplicate()
		inner.local = {"candidate": candidate}
		var result := _eval(query.where, inner, facts, depth + 1)
		if not result.known: uncertain = true
		elif not result.value is bool: return Facts.unknown("query predicate type mismatch")
		elif result.value: return Facts.known(true)
	return Facts.unknown("query candidate unknown") if uncertain else Facts.known(false)

func _budget() -> Dictionary:
	budget_exceeded = true
	return Facts.unknown("expression/collection budget exceeded")

func _path(record: Variant, path: String) -> Dictionary:
	var cursor: Variant = record
	for key in path.split("."):
		if not cursor is Dictionary or not cursor.has(key): return Facts.unknown("missing field: " + path)
		cursor = cursor[key]
	return Facts.known(cursor)
