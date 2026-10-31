extends RefCounted
## Pure presentation. Inputs are explicit JSON projections, never live objects.
## This class neither selects stories nor rolls RNG/emits Feed/writes Diary.
const Facts = preload("res://scripts/event_facts.gd")
static var _pattern: RegEx

static func _tokens() -> RegEx:
	if _pattern == null:
		_pattern = RegEx.new()
		_pattern.compile("\\{([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)*)\\}")
	return _pattern

static func render(template: String, values: Dictionary) -> Dictionary:
	if not Facts.plain(values): return _failure("text values must be bounded JSON data")
	var output := ""
	var cursor := 0
	# Only the original template is scanned: substituted names are literal text.
	for token in _tokens().search_all(template):
		var resolved := _read(values, token.get_string(1))
		if not resolved.ok: return resolved
		output += template.substr(cursor, token.get_start() - cursor) + resolved.text
		cursor = token.get_end()
	output += template.substr(cursor)
	return {"ok": true, "text": output, "errors": []}

static func render_event(selection: Dictionary, context: Dictionary, projections: Dictionary = {}) -> Dictionary:
	if selection.get("status") != "selected": return _event_failure("event has not been selected")
	if not selection.get("roles") is Dictionary or not selection.get("bindings") is Dictionary or not selection.get("selected") is Dictionary: return _event_failure("invalid selected event")
	var templates: Variant = selection.selected.get("text", {})
	if not templates is Dictionary: return _event_failure("text must be an object")
	# Eligibility/diagnostics may contain thousands of records. They are not text
	# inputs; likewise only explicitly referenced projections are read.
	for value in [selection.roles, selection.bindings, templates, context.get("payload", {})]:
		if not Facts.plain(value): return _event_failure("event text requires bounded JSON data")
	var values: Dictionary = selection.roles.duplicate(true)
	for key in selection.bindings:
		if values.has(key): return _event_failure("ambiguous text root: " + key)
		values[key] = selection.bindings[key]
	if values.has("payload"): return _event_failure("ambiguous text root: payload")
	values.payload = context.get("payload", {})
	var expanded := _expand(values, projections)
	if not expanded.known: return _event_failure(expanded.reason)
	var texts: Dictionary = {}
	for key in templates:
		if not templates[key] is String: return _event_failure("template must be a string: " + key)
		var rendered := render(templates[key], expanded.value)
		if not rendered.ok: return {"ok": false, "texts": {}, "errors": rendered.errors}
		texts[key] = rendered.text
	# Keys remain feed/diary_main/diary_secondary (or other declared text channels).
	# Probability, recipients, importance and delivery belong to the caller.
	return {"ok": true, "texts": texts, "errors": []}

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
			if Facts.value_type(fields[key]) not in ["string", "number", "bool", "null"]: return Facts.unknown("entity projection requires scalar fields")
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
