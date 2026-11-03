extends RefCounted
## One synchronous event transaction: choose -> prepare -> validate -> silent writes.
## The coordinator records completed/cooldown before calling publish(). No rollback.
const Facts = preload("res://scripts/event_facts.gd")
const Evaluator = preload("res://scripts/event_expression.gd")
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
const Data = preload("res://scripts/event_store_data.gd")
const Chronicle = preload("res://scripts/settlement_chronicle.gd")
var chronicle: RefCounted = Chronicle.new()
signal resident_message(resident_id: String, resident_name: String, text: String)
var rng: RefCounted = RandomNumberGenerator.new()
var _control: RefCounted
var _facts: RefCounted
var _active_guard: Callable
var _pending: Dictionary = {}
var _outcomes: Dictionary = {}
var _notices: Dictionary = {}

func _init() -> void:
	rng.randomize() # Separate from event selection, social mechanics and AI.

func setup(control: RefCounted, facts: RefCounted, active_guard: Callable) -> void:
	assert(_control == null or _control == control)
	_control = control
	_facts = facts
	_active_guard = active_guard

func execute(selection: Dictionary, context: Dictionary, minute: int, source: RefCounted) -> Dictionary:
	var token: String = context.get("occurrence_id", "")
	if token.is_empty(): return _error("invalid_context", "missing occurrence_id")
	if _outcomes.has(token):
		var previous: Dictionary = _outcomes[token].duplicate(true)
		previous.duplicate = true
		return previous
	if _pending.has(token): return {"status": "pending", "occurrence_id": token}
	_pending[token] = true
	var result := _prepare_commit(selection.duplicate(true), context.duplicate(true), minute, source)
	result.occurrence_id = token
	_outcomes[token] = result.duplicate(true)
	_pending.erase(token)
	return result.duplicate(true)

func publish(occurrence_id: String) -> void:
	var notices: Array = _notices.get(occurrence_id, [])
	_notices.erase(occurrence_id) # Reentrant publish cannot emit twice.
	for write: Dictionary in notices:
		if write.kind == "chronicle": write.store.changed.emit(write.prepared.id)
		elif write.kind != "chat.say": write.store.changed.emit(write.prepared.id)
	# Presentation happens only after the whole transaction and its store notices.
	for write: Dictionary in notices:
		if write.kind == "chat.say": resident_message.emit(write.person.id, write.name, write.text)

func _prepare_commit(selection: Dictionary, context: Dictionary, minute: int, source: RefCounted) -> Dictionary:
	if selection.get("status") != "selected" or minute < 0: return _error("invalid_selection", "selection/minute")
	if not Facts.plain(context) or not selection.get("selected") is Dictionary or not selection.get("roles") is Dictionary or not selection.get("bindings") is Dictionary: return _error("invalid_selection", "expected resolved JSON selection")
	if not _active(source): return _error("inactive_source", "source no longer active")
	var definition: Dictionary = selection.selected
	# A probability must never conceal an unsupported operation, including an
	# unchosen reserved R2-B1 opinion/XP description.
	for effect in definition.get("effects", []):
		if effect.get("op") not in ["memory.add", "moodlet.add", "chat.say", "memory.reinforce"]: return _error("unsupported_effect", str(effect.get("op")))
	for group in definition.get("exclusive_groups", []):
		for option in group.options:
			if option.get("op") not in ["memory.add", "moodlet.add", "chat.say", "memory.reinforce", "none"]: return _error("unsupported_effect", str(option.get("op")))
	for group in definition.get("effect_groups", []):
		for effect in group.effects:
			if effect.get("op") not in ["memory.add", "moodlet.add", "chat.say", "memory.reinforce"]: return _error("unsupported_effect", str(effect.get("op")))
	var chosen := _choose(definition)
	if not chosen.ok: return _error("invalid_rng", chosen.error)
	var main := _person(selection.get("main"))
	if main == null: return _error("inactive_main", "main must be an active resident")
	var rendered := _render(selection, context)
	if not rendered.ok: return _error("text_failed", str(rendered.errors))
	var writes: Array = []
	var env := {"ctx": context, "role": selection.roles, "binding": selection.bindings, "param": definition.get("params", {}), "catalog": selection.get("tables", {}), "local": {}}
	var applied: Array = []
	for item: Dictionary in chosen.items:
		var prepared := _effect(item, env, definition, context, minute, rendered.values)
		if not prepared.ok: return prepared
		writes.append(prepared.write)
		applied.append({"slot": item.slot, "op": item.description.op, "owner": prepared.write.person.id, "id": prepared.write.get("prepared", {}).get("id", item.slot)})
	# The mandatory world record is prepared after the previous presentation draws.
	# Single chronicle strings consume no RNG and preserve existing event streams.
	var history_text := TextRenderer.render_choice(definition.get("text", {}).get("chronicle"), rendered.values, rng)
	if not history_text.ok: return _error("text_failed", str(history_text.errors))
	var participants: Array = []
	for entity in selection.roles.values() + selection.bindings.values():
		if Facts.is_ref(entity) and entity not in participants: participants.append(entity)
	var raw := {"id": context.occurrence_id, "definition_id": definition.id, "minute": minute, "text": history_text.text, "participants": participants}
	var history_record: Dictionary = chronicle.prepare_add(raw)
	if history_record.is_empty(): return _error("chronicle_failed", "history rejected record")
	writes.append({"kind": "chronicle", "store": chronicle, "raw": raw, "prepared": history_record})
	# Pure validation hooks only. No await, RNG, signals or gameplay calls between
	# this last check and ALL writes. Internal apply primitives cannot reject.
	if not _active(source): return _error("inactive_source", "source changed during preparation")
	var destinations: Dictionary = {}
	for write: Dictionary in writes:
		if write.kind == "chronicle":
			if write.store != chronicle or chronicle.prepare_add(write.raw) != write.prepared: return _error("chronicle_failed", "stale history")
			continue
		if not _active(write.person): return _error("inactive_recipient", write.person.id)
		if write.kind != "chat.say":
			var current_store: RefCounted = write.person.memories if write.kind.begins_with("memory.") else write.person.moodlets
			var destination := "%s:%s" % [write.store.get_instance_id(), write.prepared.id]
			if destinations.has(destination): return _error("prepare_failed", "duplicate store destination")
			destinations[destination] = true
			var prepared: Dictionary
			if write.kind == "memory.reinforce": prepared = write.store.prepare_reinforce(write.raw.entry_id,write.raw.amount,minute,context.occurrence_id,write.raw.expected_version)
			else: prepared = write.store.prepare_add(write.raw)
			if current_store != write.store or prepared != write.prepared: return _error("prepare_failed", "stale store: " + write.person.id)
	var result := {"status": "completed", "event_id": "event:" + context.occurrence_id, "definition_id": definition.id, "main": selection.main, "minute": minute, "effects": applied, "exclusive_groups": chosen.groups}
	for write: Dictionary in writes:
		if write.kind == "memory.reinforce": write.store._apply_event_update(write.prepared)
		elif write.kind != "chat.say": write.store._apply_event_add(write.prepared)
	_notices[context.occurrence_id] = writes
	return result

func _choose(definition: Dictionary) -> Dictionary:
	var items: Array = []
	var groups: Array = []
	for i in definition.get("effects", []).size():
		var effect: Dictionary = definition.effects[i]
		var chance := _chance(effect.get("chance", 1.0))
		if not chance.ok: return chance
		if chance.passed: items.append({"description": effect, "slot": "effect/%d" % i})
	for group in definition.get("exclusive_groups", []):
		var chance := _chance(group.get("chance", 1.0))
		if not chance.ok: return chance
		var index := -1
		if chance.passed:
			var choice := _weighted(group.options)
			if not choice.ok: return choice
			index = choice.index
		groups.append({"id": group.id, "index": index})
		if index < 0: continue
		var option: Dictionary = group.options[index]
		# R2-B1 also allowed chance on an option. Honor it if explicitly present,
		# after its weighted choice; it never falls through to another option.
		if option.has("chance"):
			chance = _chance(option.chance)
			if not chance.ok: return chance
			if not chance.passed: continue
		if option.op != "none": items.append({"description": option, "slot": "group/%s/option/%d" % [group.id, index]})
	for group in definition.get("effect_groups", []):
		var chance := _chance(group.chance)
		if not chance.ok: return chance
		if chance.passed:
			for index in group.effects.size(): items.append({"description": group.effects[index], "slot": "bundle/%s/effect/%d" % [group.id, index]})
	return {"ok": true, "items": items, "groups": groups}

func _chance(probability: Variant) -> Dictionary:
	if not Data.number(probability) or probability < 0 or probability > 1: return {"ok": false, "error": "invalid probability"}
	var roll: float = rng.randf()
	if not is_finite(roll) or roll < 0 or roll > 1: return {"ok": false, "error": "invalid consequence RNG draw"}
	return {"ok": true, "passed": probability >= 1 or roll < probability}

func _weighted(options: Array) -> Dictionary:
	var maximum := 0.0
	for option in options:
		if not Data.number(option.get("weight")) or option.weight < 0: return {"ok": false, "error": "invalid option weight"}
		maximum = maxf(maximum, option.weight)
	if maximum == 0: return {"ok": true, "index": -1}
	var total := 0.0
	for option in options: total += option.weight / maximum
	var roll: float = rng.randf()
	if not is_finite(roll) or roll < 0 or roll > 1: return {"ok": false, "error": "invalid weighted RNG draw"}
	var remainder := roll * total
	var last := -1
	for i in options.size():
		if options[i].weight == 0: continue
		last = i
		remainder -= options[i].weight / maximum
		if remainder < 0: return {"ok": true, "index": i}
	return {"ok": true, "index": last} # Inclusive upper RNG boundary, positive weights only.

func _effect(item: Dictionary, env: Dictionary, definition: Dictionary, context: Dictionary, minute: int, text_values: Dictionary) -> Dictionary:
	var resolved := _resolve(item.description, env)
	if not resolved.known: return _error("prepare_failed", item.slot + ": " + resolved.reason)
	var effect: Dictionary = resolved.value
	var values := _effect_values(effect, text_values)
	if not values.known: return _error("text_failed", item.slot + ": " + values.reason)
	if effect.op == "memory.reinforce":
		if not Data.only_keys(effect,["op","owner","entry_id","amount","expected_version","chance","weight"]): return _error("prepare_failed",item.slot+": invalid reinforcement arguments")
		var recipient := _person(effect.get("owner"))
		if recipient == null: return _error("inactive_recipient",item.slot)
		if not Data.text(effect.get("entry_id")) or not Data.number(effect.get("amount")) or not _whole(effect.get("expected_version")): return _error("prepare_failed",item.slot+": invalid reinforcement")
		var update: Dictionary = recipient.memories.prepare_reinforce(effect.entry_id,effect.amount,minute,context.occurrence_id,int(effect.expected_version))
		if update.is_empty(): return _error("prepare_failed",item.slot+": stale memory")
		return {"ok":true,"write":{"kind":effect.op,"person":recipient,"store":recipient.memories,"raw":effect,"prepared":update}}
	if effect.op == "chat.say":
		if not Data.only_keys(effect, ["op", "owner", "text", "text_bindings", "chance", "weight"]): return _error("prepare_failed", item.slot + ": unsupported chat arguments")
		var speaker := _person(effect.get("owner"))
		if speaker == null: return _error("inactive_recipient", item.slot + ": speaker")
		var speech := TextRenderer.render_choice(effect.get("text"), values.value, rng)
		if not speech.ok or speech.text.strip_edges().is_empty(): return _error("text_failed", item.slot + ": invalid/empty chat text: " + str(speech.get("errors", [])))
		return {"ok": true, "write": {"kind": effect.op, "person": speaker, "name": speaker.resident_name, "text": speech.text, "prepared": {"id": item.slot}}}
	var allowed := ["op", "owner", "target", "tags", "context", "chance", "weight"]
	allowed.append_array(["kind", "topic", "strength", "permanent", "provenance", "text", "text_bindings"] if effect.op == "memory.add" else ["definition", "duration_minutes", "expires_at_minute", "modifiers"])
	if not Data.only_keys(effect, allowed): return _error("prepare_failed", item.slot + ": unsupported arguments")
	var person := _person(effect.get("owner"))
	if person == null: return _error("inactive_recipient", item.slot + ": owner")
	var details: Variant = effect.get("context", {})
	if not details is Dictionary or details.has("_event"): return _error("prepare_failed", item.slot + ": reserved/invalid context")
	var record := {"id": JSON.stringify([context.occurrence_id, definition.id, definition.revision, item.slot]), "type": effect.get("kind") if effect.op == "memory.add" else effect.get("definition"), "owner": effect.owner, "target": effect.get("target"), "tags": effect.get("tags", []), "context": details.duplicate(true), "source_occurrence_id": context.occurrence_id, "created_minute": minute}
	record.context["_event"] = {"id": "event:" + context.occurrence_id, "definition_id": definition.id, "revision": definition.revision, "slot": item.slot}
	var store: RefCounted
	if effect.op == "memory.add":
		record.merge({"topic": effect.get("topic"), "strength": effect.get("strength"), "permanent": effect.get("permanent", false), "provenance": effect.get("provenance")})
		if effect.has("text"):
			var memory_text := TextRenderer.render_choice(effect.text, values.value, rng)
			if not memory_text.ok or memory_text.text.strip_edges().is_empty(): return _error("text_failed", item.slot + ": invalid memory text")
			record["text"] = memory_text.text
		var participants: Array = []
		for entity in env.role.values() + env.binding.values() + [effect.get("target")]:
			if Facts.is_ref(entity) and entity not in participants: participants.append(entity)
		record["participants"] = participants
		store = person.memories
	else:
		if effect.has("duration_minutes") and effect.has("expires_at_minute"): return _error("prepare_failed", item.slot + ": two deadlines")
		var expiry: Variant = effect.get("expires_at_minute")
		if effect.has("duration_minutes"):
			if not _whole(effect.duration_minutes) or effect.duration_minutes > 9223372036854775807 - minute: return _error("prepare_failed", item.slot + ": invalid duration")
			expiry = minute + int(effect.duration_minutes)
		if expiry != null:
			if not _whole(expiry): return _error("prepare_failed", item.slot + ": invalid expiry")
			expiry = int(expiry)
		record.merge({"expires_at_minute": expiry, "modifiers": effect.get("modifiers", [])})
		store = person.moodlets
	var prepared: Dictionary = store.prepare_add(record)
	if prepared.is_empty(): return _error("prepare_failed", item.slot + ": store rejected record")
	return {"ok": true, "write": {"kind": effect.op, "person": person, "store": store, "raw": record, "prepared": prepared}}

func _effect_values(effect: Dictionary, values: Dictionary) -> Dictionary:
	if not effect.has("text_bindings"): return Facts.known(values)
	var aliases: Variant = effect.get("text_bindings", {})
	if not aliases is Dictionary: return Facts.unknown("text_bindings must be an object")
	var labels: Dictionary = {}
	for entity in aliases.values():
		var person := _person(entity)
		if person == null: return Facts.unknown("inactive text participant")
		labels[Facts.ref_key(entity)] = person.event_text_projection()
	return TextRenderer.bind_values(values, aliases, labels)

func _resolve(value: Variant, env: Dictionary) -> Dictionary:
	if value is Dictionary:
		if value.size() == 1 and value.keys()[0] in Evaluator.REF_OPS + Evaluator.BINARY_OPS + ["fact", "all", "any", "not", "list", "exists"]:
			return Evaluator.new().evaluate(value, env, _facts)
		var fields: Dictionary = {}
		for key in value:
			var result := _resolve(value[key], env)
			if not result.known: return result
			fields[key] = result.value
		return Facts.known(fields)
	if value is Array:
		var array: Array = []
		for item in value:
			var result := _resolve(item, env)
			if not result.known: return result
			array.append(result.value)
		return Facts.known(array)
	return Facts.known(value)

func _render(selection: Dictionary, context: Dictionary) -> Dictionary:
	var labels: Dictionary = {}
	for value in selection.roles.values() + selection.bindings.values():
		var person := _person(value)
		if person != null: labels[Facts.ref_key(value)] = person.event_text_projection()
	var values := TextRenderer.event_values(selection,context,labels)
	return {"ok":true,"values":values.value} if values.known else {"ok":false,"errors":[values.reason]}

func _active(person: RefCounted) -> bool:
	return person != null and _control != null and _control.get_resident(person.id) == person and _active_guard.is_valid() and _active_guard.call(person)

func _person(entity: Variant) -> RefCounted:
	if not Facts.is_ref(entity) or entity.kind != "resident": return null
	var person: RefCounted = _control.get_resident(entity.id)
	return person if _active(person) else null

static func _whole(value: Variant) -> bool:
	if value is int: return value >= 0
	return value is float and is_finite(value) and value >= 0 and value < float(9223372036854775807) and floor(value) == value

static func _error(status: String, reason: String) -> Dictionary:
	return {"ok": false, "status": status, "errors": [reason]}
