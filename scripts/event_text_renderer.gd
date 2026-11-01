extends RefCounted
## One presentation path for diaries and speech. No writes or gameplay callbacks.
const Facts = preload("res://scripts/event_facts.gd")
const Grammar = preload("res://scripts/event_russian_grammar.gd")
static var _pattern: RegEx
static var _path_pattern: RegEx

static func _tokens() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile("\\{([^{}]*)\\}")
	return _pattern

static func _token_parts(token: String) -> Dictionary:
	var parts := token.split(":", true, 1)
	if _path_pattern == null:
		_path_pattern = RegEx.new()
		_path_pattern.compile("^[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)*$")
	if _path_pattern.search(parts[0]) == null: return _failure("invalid text reference: " + token)
	var field: String = parts[0].get_slice(".", parts[0].get_slice_count(".") - 1)
	var argument: String = parts[1] if parts.size() == 2 else ""
	if parts.size() == 2:
		if field in ["name", "pronoun"]:
			if argument not in Grammar.CASES: return _failure("unknown grammatical case: " + token)
		elif field == "gender":
			if argument.split("|", true).size() != 2: return _failure("gender requires masculine|feminine: " + token)
		else: return _failure("unsupported text modifier: " + token)
	if field in ["pronoun", "with", "about"] or parts.size() == 2:
		if not "." in parts[0]: return _failure("grammar requires participant field: " + token)
	return {"ok": true, "path": parts[0], "field": field, "argument": argument, "modified": parts.size() == 2}

static func validate(template: String, roots: Array = []) -> Dictionary:
	var cursor := 0
	for token in _tokens().search_all(template):
		var literal := template.substr(cursor, token.get_start() - cursor)
		if "{" in literal or "}" in literal: return _failure("unmatched template brace")
		var parts := _token_parts(token.get_string(1))
		if not parts.ok: return parts
		var root: String = parts.path.get_slice(".", 0)
		if not roots.is_empty() and root not in roots: return _failure("unknown text reference: " + root)
		cursor = token.get_end()
	var remaining := template.substr(cursor)
	if "{" in remaining or "}" in remaining: return _failure("unmatched template brace")
	return {"ok": true, "errors": []}

static func alternatives(value: Variant) -> Dictionary:
	if value is String: return {"ok": true, "items": [{"text": value, "weight": 1.0}], "errors": []}
	if not value is Array or value.is_empty() or value.size() > Facts.MAX_COLLECTION: return _failure("text requires a string or nonempty bounded alternatives array")
	var items: Array = []
	var positive := false
	for item in value:
		var text: Variant = item if item is String else item.get("text") if item is Dictionary else null
		var weight: Variant = item.get("weight", 1.0) if item is Dictionary else 1.0
		if item is Dictionary:
			for key in item:
				if key not in ["text", "weight"]: return _failure("unknown text alternative field")
		if not text is String or text.strip_edges().is_empty(): return _failure("alternative must contain nonempty text")
		if Facts.value_type(weight) != "number" or not is_finite(float(weight)) or weight < 0: return _failure("invalid text alternative weight")
		positive = positive or weight > 0
		items.append({"text": text, "weight": weight})
	if not positive: return _failure("text alternatives require a positive weight")
	return {"ok": true, "items": items, "errors": []}

static func validate_choice(value: Variant, roots: Array = []) -> Dictionary:
	var choices := alternatives(value)
	if not choices.ok: return choices
	for item in choices.items:
		var result := validate(item.text, roots)
		if not result.ok: return result
	return {"ok": true, "errors": []}

static func render(template: String, values: Dictionary) -> Dictionary:
	if not Facts.plain(values): return _failure("text values must be bounded JSON data")
	var valid := validate(template)
	if not valid.ok: return valid
	var output := ""
	var cursor := 0
	# Only the original template is scanned; substituted names are literal text.
	for token in _tokens().search_all(template):
		var parts := _token_parts(token.get_string(1))
		var resolved := _grammar(values, parts) if parts.modified or parts.field in ["pronoun", "with", "about"] else _read(values, parts.path)
		if not resolved.ok: return resolved
		output += template.substr(cursor, token.get_start() - cursor) + resolved.text
		cursor = token.get_end()
	output += template.substr(cursor)
	return {"ok": true, "text": output, "errors": []}

static func render_choice(value: Variant, values: Dictionary, rng: RefCounted = null) -> Dictionary:
	var choices := alternatives(value)
	if not choices.ok: return choices
	var rendered: Array = []
	var maximum := 0.0
	# Validate/render every variant, even zero-weight ones, before any text draw.
	for item in choices.items:
		var result := render(item.text, values)
		if not result.ok: return result
		rendered.append(result.text)
		maximum = maxf(maximum, item.weight)
	if choices.items.size() == 1: return {"ok": true, "text": rendered[0], "errors": []}
	if rng == null: return _failure("alternatives require an explicit deterministic RNG")
	var total := 0.0
	for item in choices.items: total += item.weight / maximum
	var roll: float = rng.randf()
	if not is_finite(roll) or roll < 0 or roll > 1: return _failure("invalid text RNG draw")
	var remainder := roll * total
	var last := -1
	for index in choices.items.size():
		if choices.items[index].weight == 0: continue
		last = index
		remainder -= choices.items[index].weight / maximum
		if remainder < 0: return {"ok": true, "text": rendered[index], "errors": []}
	return {"ok": true, "text": rendered[last], "errors": []}

static func event_values(selection: Dictionary, context: Dictionary, projections: Dictionary = {}) -> Dictionary:
	if selection.get("status") != "selected": return Facts.unknown("event has not been selected")
	if not selection.get("roles") is Dictionary or not selection.get("bindings") is Dictionary or not selection.get("selected") is Dictionary: return Facts.unknown("invalid selected event")
	for value in [selection.roles, selection.bindings, context.get("payload", {})]:
		if not Facts.plain(value): return Facts.unknown("event text requires bounded JSON data")
	var values: Dictionary = selection.roles.duplicate(true)
	for key in selection.bindings:
		if values.has(key): return Facts.unknown("ambiguous text root: " + key)
		values[key] = selection.bindings[key]
	if values.has("payload"): return Facts.unknown("ambiguous text root: payload")
	values.payload = context.get("payload", {})
	return _expand(values, projections)

static func render_event(selection: Dictionary, context: Dictionary, projections: Dictionary = {}, rng: RefCounted = null) -> Dictionary:
	var expanded := event_values(selection, context, projections)
	if not expanded.known: return _event_failure(expanded.reason)
	var templates: Variant = selection.selected.get("text", {})
	if not templates is Dictionary or not Facts.plain(templates): return _event_failure("text must be a bounded object")
	var texts: Dictionary = {}
	for key in templates:
		var rendered := render_choice(templates[key], expanded.value, rng)
		if not rendered.ok: return {"ok": false, "texts": {}, "errors": rendered.errors}
		texts[key] = rendered.text
	return {"ok": true, "texts": texts, "errors": []}

static func _grammar(values: Dictionary, parts: Dictionary) -> Dictionary:
	var path: String = parts.path
	var parent: Variant = values
	var keys := path.split(".")
	for index in keys.size() - 1:
		if not parent is Dictionary or not parent.has(keys[index]): return _failure("missing grammar participant: " + path)
		parent = parent[keys[index]]
	if not parent is Dictionary: return _failure("grammar requires participant object: " + path)
	var gender: Variant = parent.get("gender")
	if parts.field in ["gender", "pronoun"]:
		if not gender is String or not Grammar.PRONOUNS.has(gender): return _failure("missing/invalid participant gender: " + path)
		if parts.field == "gender": return {"ok": true, "text": parts.argument.split("|", true)[1 if gender == "feminine" else 0], "errors": []}
		return {"ok": true, "text": Grammar.PRONOUNS[gender][Grammar.CASES.find(parts.argument if parts.modified else "nom")], "errors": []}
	if not parent.get("name") is String: return _failure("missing participant name: " + path)
	var forms: Variant = parent.get("name_forms", Grammar.forms(parent.name, str(gender)))
	if not Grammar.valid_forms(forms, parent.name): return _failure("invalid participant name forms: " + path)
	var text: String
	if parts.field == "with": text = Grammar.with_name(forms.ins)
	elif parts.field == "about": text = Grammar.about_name(forms.prep)
	else: text = forms[parts.argument]
	return {"ok": true, "text": text, "errors": []}

static func _read(values: Dictionary, path: String) -> Dictionary:
	var value: Variant = values
	for key in path.split("."):
		if not value is Dictionary or not value.has(key): return _failure("missing text value: " + path)
		value = value[key]
	if Facts.value_type(value) not in ["string", "number", "bool"]: return _failure("text value must be a scalar: " + path)
	return {"ok": true, "text": str(value), "errors": []}

static func _expand(value: Variant, projections: Dictionary) -> Dictionary:
	if Facts.is_ref(value):
		var fields: Variant = projections.get(Facts.ref_key(value), {})
		if not fields is Dictionary or not Facts.plain(fields): return Facts.unknown("entity projection must be a bounded JSON object")
		var result: Dictionary = value.duplicate(true)
		for key in fields:
			if key in ["id", "kind"]: return Facts.unknown("entity projection cannot replace identity")
			if key == "name_forms" and not Grammar.valid_forms(fields[key], fields.get("name", "")): return Facts.unknown("invalid projected name forms")
			if key != "name_forms" and Facts.value_type(fields[key]) not in ["string", "number", "bool", "null"]: return Facts.unknown("entity projection requires scalar fields")
			result[key] = fields[key]
		return Facts.known(result)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			var expanded := _expand(value[key], projections)
			if not expanded.known: return expanded
			result[key] = expanded.value
		return Facts.known(result)
	if value is Array:
		var result: Array = []
		for item in value:
			var expanded := _expand(item, projections)
			if not expanded.known: return expanded
			result.append(expanded.value)
		return Facts.known(result)
	return Facts.known(value)

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "text": "", "errors": [reason]}

static func _event_failure(reason: String) -> Dictionary:
	return {"ok": false, "texts": {}, "errors": [reason]}
