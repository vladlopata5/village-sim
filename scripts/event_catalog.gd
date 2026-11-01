extends RefCounted
## Atomic JSON catalog loading. Only the requested trigger bucket is read at runtime.
const Facts = preload("res://scripts/event_facts.gd")
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
const Evaluator = preload("res://scripts/event_expression.gd")
const MAX_DEFINITIONS := 10000
const MAX_JSON_CHARACTERS := 16000000
const EFFECT_FIELDS := {
	"opinion.add": ["owner", "target", "amount"],
	"skill.add_xp": ["owner", "skill", "amount"],
	"moodlet.add": ["owner", "definition"],
	"memory.add": ["owner", "kind"],
	"chat.say": ["owner", "text"],
	"none": []
}
var errors: Array = []
var _by_trigger: Dictionary = {}
var _catalogs: Dictionary = {}
var definition_count := 0

func load_file(path: String, facts: RefCounted) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors = ["cannot read catalog: " + path]
		return false
	return load_json(file.get_as_text(), facts)

func load_json(text: String, facts: RefCounted) -> bool:
	if text.length() > MAX_JSON_CHARACTERS:
		errors = ["catalog JSON size budget exceeded"]
		return false
	var parser := JSON.new()
	if parser.parse(text) != OK:
		errors = ["JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()]]
		return false
	return load_data(parser.data, facts)

func load_data(data: Variant, facts: RefCounted) -> bool:
	errors = []
	if not data is Dictionary or not data.get("definitions") is Array:
		errors.append("root requires definitions array")
		return false
	if data.definitions.size() > MAX_DEFINITIONS:
		errors.append("catalog definition budget exceeded")
		return false
	if data.get("schema_version", 1) != 1:
		errors.append("unsupported root schema_version")
		return false
	if not data.get("catalogs", {}) is Dictionary:
		errors.append("catalogs must be an object")
		return false
	var tables: Dictionary = data.get("catalogs", {}).duplicate(true)
	# R2-B0 examples used named tables directly on the root.
	if not data.has("catalogs"):
		for key in data:
			if key not in ["definitions", "coverage", "status", "schema_version"]: tables[key] = data[key]
	if not Facts.plain(tables):
		errors.append("catalog tables require bounded JSON-only data")
		return false
	var names := {"role": {}, "binding": {}, "param": {}, "local": {}, "catalog": {}}
	for key in tables: names.catalog[key] = Facts.value_type(tables[key])
	var index: Dictionary = {}
	var ids: Dictionary = {}
	for raw in data.definitions:
		if not raw is Dictionary or not Facts.plain(raw):
			errors.append("definition must be bounded JSON object")
			continue
		var start := errors.size()
		_validate_definition(raw, names, facts)
		var id: String = raw.get("id", "") if raw.get("id") is String else ""
		if ids.has(id): errors.append(id + ": duplicate definition id")
		ids[id] = true
		if errors.size() == start:
			if not index.has(raw.trigger): index[raw.trigger] = []
			index[raw.trigger].append(raw.duplicate(true))
	if not errors.is_empty(): return false
	for bucket in index.values(): bucket.sort_custom(func(a, b): return a.id < b.id)
	_by_trigger = index
	_catalogs = tables.duplicate(true)
	definition_count = data.definitions.size()
	return true

func definitions_for(trigger: String) -> Array:
	return _by_trigger.get(trigger, []).duplicate(true)

func get_tables() -> Dictionary:
	return _catalogs.duplicate(true)

func _validate_definition(raw: Dictionary, base_names: Dictionary, facts: RefCounted) -> void:
	var label: String = str(raw.get("id", "<missing id>"))
	for key in ["id", "trigger"]:
		if not raw.get(key) is String or raw[key].strip_edges().is_empty(): errors.append(label + ": invalid " + key)
	for key in ["schema_version", "revision"]:
		if not _integer(raw.get(key), 1): errors.append(label + ": invalid " + key)
	if raw.get("schema_version") != 1: errors.append(label + ": unsupported schema_version")
	if not raw.get("enabled") is bool: errors.append(label + ": enabled must be bool")
	if not _nonnegative(raw.get("weight")): errors.append(label + ": weight must be finite nonnegative number")
	if raw.get("priority", 0) != 0: errors.append(label + ": priority tiers are not supported in R2-B1")
	if raw.has("limits"): errors.append(label + ": use optional cooldown; R2-B0 event count limits are not supported")
	if not raw.get("roles") is Dictionary or raw.roles.size() > 8:
		errors.append(label + ": roles must be bounded object")
		return
	if not raw.get("params", {}) is Dictionary or not raw.get("bind", []) is Array:
		errors.append(label + ": params/bind type mismatch")
		return
	var names := base_names.duplicate(true)
	for key in raw.roles:
		var role: Variant = raw.roles[key]
		if not key.is_valid_identifier() or not role is Dictionary:
			errors.append(label + ": invalid role declaration")
			continue
		if not role.get("type") is String or role.type.is_empty() or not role.get("from") is String or not role.from.begins_with("ctx."):
			errors.append(label + ": role requires entity type and ctx path")
		for flag in ["active_required", "participant"]:
			if role.has(flag) and not role[flag] is bool: errors.append(label + ": role flag must be bool")
		names.role[key] = "entity"
	for key in raw.roles:
		if not raw.roles[key] is Dictionary: continue
		var distinct: Variant = raw.roles[key].get("different_from", [])
		if not distinct is Array:
			errors.append(label + ": different_from must be array")
			continue
		for other in distinct:
			if not other is String or not names.role.has(other) or other == key: errors.append(label + ": invalid distinct role")
	for key in raw.get("params", {}): names.param[key] = Facts.value_type(raw.params[key])
	if raw.get("bind", []).size() > 8: errors.append(label + ": binding budget exceeded")
	for binding in raw.get("bind", []):
		if not binding is Dictionary or not binding.get("as") is String:
			errors.append(label + ": invalid binding")
			continue
		var key: String = binding.as
		if not key.is_valid_identifier() or names.binding.has(key) or names.role.has(key): errors.append(label + ": duplicate/invalid binding name")
		var type := "any"
		var binding_evaluator := Evaluator.new()
		if binding.has("select") and not binding.has("value"):
			binding_evaluator._validate_query(binding.select, names, facts, errors, label + "/bind/" + key, 0)
			if binding.select is Dictionary:
				if binding.select.get("take") != 1 or binding.select.get("order_by") not in ["id", "value"]: errors.append(label + ": select requires take:1 and order_by:id/value")
		elif binding.has("value") and not binding.has("select"):
			type = binding_evaluator.validate(binding.value, names, facts, errors, label + "/bind/" + key)
		else: errors.append(label + ": binding requires exactly one select/value")
		if binding.has("type"):
			if binding.type != "resident_ref": errors.append(label + ": unsupported binding reference type")
			type = "entity"
		for flag in ["active_required", "participant"]:
			if binding.has(flag) and not binding[flag] is bool: errors.append(label + ": binding flag must be bool")
		names.binding[key] = type
	var evaluator := Evaluator.new()
	var condition_type := evaluator.validate(raw.get("when", true), names, facts, errors, label + "/when")
	if condition_type not in ["bool", "any", "invalid"]: errors.append(label + ": when must be boolean")
	var main: Variant = raw.get("main_role")
	if raw.has("diary_importance") and (not _integer(raw.diary_importance, 1) or raw.diary_importance > 2): errors.append(label + ": diary_importance must be TEMPORARY:1 or KEY:2")
	if not main is String or (not names.role.has(main) and not names.binding.has(main)):
		errors.append(label + ": main_role requires a declared role/binding")
	elif names.binding.has(main) or (raw.roles[main] is Dictionary and raw.roles[main].get("type") == "resident"):
		var text: Variant = raw.get("text", {})
		if not text is Dictionary or not _required_text(text.get("diary_main")): errors.append(label + ": resident main role requires a future diary_main template")
	if raw.has("cooldown"):
		var cooldown: Variant = raw.cooldown
		if not cooldown is Dictionary or not _integer(cooldown.get("minutes"), 0) or not cooldown.get("scope", []) is Array:
			errors.append(label + ": cooldown requires integer minutes and scope array")
		else:
			for scope in cooldown.get("scope", []):
				var scope_evaluator := Evaluator.new()
				scope_evaluator.validate(scope, names, facts, errors, label + "/cooldown")
	_validate_descriptions(raw.get("effects", []), names, facts, label)
	var groups: Variant = raw.get("exclusive_groups", [])
	if not groups is Array:
		errors.append(label + ": exclusive_groups must be array")
	else:
		var group_ids: Dictionary = {}
		for group in groups:
			if not group is Dictionary or not group.get("id") is String or group.id.is_empty() or not group.get("options") is Array:
				errors.append(label + ": invalid exclusive group")
				continue
			if group_ids.has(group.id): errors.append(label + ": duplicate exclusive group")
			group_ids[group.id] = true
			if not _probability(group.get("chance", 1.0)): errors.append(label + ": invalid exclusive group chance")
			_validate_descriptions(group.options, names, facts, label + "/" + group.id, true)
			for option in group.options:
				if option is Dictionary and not _nonnegative(option.get("weight")): errors.append(label + ": exclusive option requires nonnegative weight")
	if raw.has("secondary_diary"):
		var diary: Variant = raw.secondary_diary
		if not diary is Dictionary or not diary.get("role") is String or not (names.role.has(diary.role) or names.binding.has(diary.role)) or not _probability(diary.get("chance")):
			errors.append(label + ": invalid secondary diary policy")
		elif not raw.get("text", {}) is Dictionary or not _required_text(raw.text.get("diary_secondary")): errors.append(label + ": missing secondary diary template")
	_validate_text(raw.get("text", {}), names, label)

func _validate_descriptions(effects: Variant, names: Dictionary, facts: RefCounted, label: String, allow_none: bool = false) -> void:
	if not effects is Array:
		errors.append(label + ": effects must be array")
		return
	for effect in effects:
		if not effect is Dictionary or not EFFECT_FIELDS.has(effect.get("op", "")):
			errors.append(label + ": unsupported effect description")
			continue
		if effect.op == "none" and not allow_none: errors.append(label + ": none is an exclusive option only")
		if effect.op == "none":
			for key in effect:
				if key not in ["op", "chance", "weight"]: errors.append(label + ": none option cannot contain effect arguments")
		for key in EFFECT_FIELDS[effect.op]:
			if not effect.has(key): errors.append(label + ": missing effect field " + key)
		for key in ["owner", "target", "amount", "duration_minutes", "expires_at_minute", "salience", "strength", "skill", "kind", "topic", "definition", "permanent", "text"]:
			if not effect.has(key): continue
			if key == "text" and (effect[key] is String or effect[key] is Array):
				_validate_template(effect[key], names, label + "/effects/text")
				continue
			var evaluator := Evaluator.new()
			var type := evaluator.validate(effect[key], names, facts, errors, label + "/effects/" + key)
			var expected := "entity" if key in ["owner", "target"] else "string" if key in ["skill", "kind", "topic", "definition", "text"] else "bool" if key == "permanent" else "number"
			if type not in [expected, "any", "invalid"] and not (key in ["target", "expires_at_minute"] and type == "null"): errors.append(label + ": incompatible effect field " + key)
		if not _probability(effect.get("chance", 1.0)): errors.append(label + ": invalid effect chance")
		_validate_payload(effect, names, facts, label + "/effects")

func _validate_payload(value: Variant, names: Dictionary, facts: RefCounted, path: String) -> void:
	if value is Array:
		for item in value: _validate_payload(item, names, facts, path)
	elif value is Dictionary:
		if value.size() == 1 and value.keys()[0] in Evaluator.REF_OPS + Evaluator.BINARY_OPS + ["fact", "all", "any", "not", "list", "exists"]:
			var evaluator := Evaluator.new()
			evaluator.validate(value, names, facts, errors, path)
		else:
			for item in value.values(): _validate_payload(item, names, facts, path)

func _validate_text(text: Variant, names: Dictionary, label: String) -> void:
	if not text is Dictionary:
		errors.append(label + ": text must be object")
		return
	for template in text.values(): _validate_template(template, names, label)

func _validate_template(value: Variant, names: Dictionary, label: String) -> void:
	var roots: Array = names.role.keys() + names.binding.keys() + ["payload"]
	var result := TextRenderer.validate_choice(value, roots)
	if not result.ok:
		for error in result.errors: errors.append(label + ": " + str(error))

static func _required_text(value: Variant) -> bool:
	if value is String: return not value.strip_edges().is_empty()
	return TextRenderer.alternatives(value).ok

static func _integer(value: Variant, minimum: int) -> bool:
	return _nonnegative(value) and float(value) >= minimum and floor(float(value)) == float(value)

static func _nonnegative(value: Variant) -> bool:
	return Facts.value_type(value) == "number" and is_finite(float(value)) and float(value) >= 0.0

static func _probability(value: Variant) -> bool:
	return _nonnegative(value) and float(value) <= 1.0
