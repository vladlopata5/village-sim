extends Node
## Live trigger adapter. Selection and atomic consequence execution stay separate.
const Facts = preload("res://scripts/event_facts.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const DryRunner = preload("res://scripts/event_dry_run.gd")
const EffectExecutor = preload("res://scripts/event_effect_executor.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const ResidentFacts = preload("res://scripts/resident_event_facts.gd")
const CandidatePicker = preload("res://scripts/event_candidate_picker.gd")
signal event_completed(result: Dictionary)
signal resident_message(resident_id: String, resident_name: String, text: String)
var enabled := true
var facts := Facts.new()
var catalog := Catalog.new()
var selector := DryRunner.new(catalog, facts)
var executor := EffectExecutor.new()
var chronicle: RefCounted:
	get: return executor.chronicle
var candidate_picker := CandidatePicker.new()
var _control: RefCounted
var _clock: Node
var _active_guard: Callable
var _tracked: Dictionary = {}
var _registration_sequence := 0
var _source_generations: Array = [] # Weak identities; re-registering the same data keeps its token.
var _queue: Array = []
var _pending_ids: Dictionary = {}
var _draining := false
var _outcomes: Dictionary = {}
var _completed: Dictionary = {}
var _history: Dictionary = {}
var _last_occurrence: Dictionary = {}
var _social_source: Node
var _construction_sources: Array = [] # Weak building refs; no worker history.
var _meal_sources: Array = [] # Weak controllers; no separate meal history.

func _init() -> void:
	selector.rng.randomize() # Own stream; never consumes social or resident RNG.
	selector.set_chance("skill.raised", Balance.SKILL_RAISED_EVENT_CHANCE)
	selector.set_chance("construction.completed", Balance.CONSTRUCTION_COMPLETED_EVENT_CHANCE)
	selector.set_chance("social.resolved", Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE)
	selector.set_chance("meal.completed", 1.0)
	executor.resident_message.connect(resident_message.emit)
	# Schemas for validation only. Live values are short-lived pair snapshots.
	var schema := ResidentFacts.snapshot_schema()
	for key in schema: facts.register_fact(key, "resident", schema[key][0], schema[key][1])
	_load_catalogs()

func _load_catalogs() -> void:
	var combined := {"schema_version": 1, "definitions": [], "catalogs": {}}
	for path in ["res://assets/events/skill_progress.json", "res://assets/events/social_success_envy.json", "res://assets/events/catalog_expansion.json", "res://assets/events/construction_completed.json", "res://assets/events/meal_completed.json"]:
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			push_error(path + ": " + parser.get_error_message())
			return
		var root: Variant = parser.data
		if not root is Dictionary or root.get("schema_version", 1) != 1 or not root.get("definitions") is Array or not root.get("catalogs", {}) is Dictionary:
			push_error(path + ": invalid event catalog root")
			return
		combined.definitions.append_array(root.definitions)
		for key in root.get("catalogs", {}):
			if combined.catalogs.has(key):
				push_error(path + ": duplicate catalog table " + str(key))
				return
			combined.catalogs[key] = root.catalogs[key]
	if not catalog.load_data(combined, facts): push_error(str(catalog.errors))

func setup(control: RefCounted, clock: Node, active_guard: Callable) -> void:
	assert(_control == null or _control == control, "Event service belongs to one world")
	_control = control
	_clock = clock
	_active_guard = active_guard
	executor.setup(_control, facts, _active)
	if not _control.residents_changed.is_connected(_sync_residents): _control.residents_changed.connect(_sync_residents)
	_sync_residents()

func _active(data: RefCounted) -> bool:
	return data != null and is_inside_tree() and not is_queued_for_deletion() and _control != null and _control.get_resident(data.id) == data and _active_guard.is_valid() and _active_guard.call(data)

func attach_social(source: Node) -> void:
	assert(_social_source == null or _social_source == source, "One social producer per event-service session")
	_social_source = source
	if not source.interaction_committed.is_connected(_on_social_committed): source.interaction_committed.connect(_on_social_committed)

func _on_social_committed(result: RefCounted) -> void:
	var context: Dictionary = result.confirmed_context()
	if context.is_empty(): return # Presenting a synthetic/legacy result is not a trigger.
	var first: RefCounted = _control.get_resident(context.actor.id)
	var second: RefCounted = _control.get_resident(context.other.id)
	_enqueue(context, first if result.has_participants(first, second) else null, second)

func observe_construction(building: RefCounted) -> void:
	# Starting built entities have no first-build fact to announce retroactively.
	if building.previously_built or building.is_upgrading(): return
	for row in _construction_sources:
		if row.reference.get_ref() == building: return
	_construction_sources = _construction_sources.filter(func(row): return row.reference.get_ref() != null)
	var reference: WeakRef = weakref(building)
	var callback := _on_construction_completed.bind(reference)
	building.construction_completed.connect(callback)
	_construction_sources.append({"reference": reference, "callback": callback})

func observe_meals(controller: Node, data: RefCounted) -> void:
	for row in _meal_sources:
		if row.reference.get_ref() == controller: return
	_meal_sources = _meal_sources.filter(func(row): return row.reference.get_ref() != null)
	var callback := _on_meal_completed.bind(weakref(data))
	controller.meal_completed.connect(callback)
	_meal_sources.append({"reference": weakref(controller), "callback": callback})

func _on_meal_completed(snapshot: Dictionary, resident_ref: WeakRef) -> void:
	var person: RefCounted = resident_ref.get_ref()
	if person == null or snapshot.get("resident_id") != person.id: return
	if not snapshot.get("meal_id") is String or snapshot.meal_id.is_empty(): return
	if not snapshot.get("minute") is int or snapshot.minute < 0 or not snapshot.get("hunger") is int or snapshot.hunger < 0 or snapshot.hunger > 100: return
	var payload := snapshot.duplicate(true)
	payload.erase("minute")
	var id := JSON.stringify(["meal.completed", _source_generation(person), snapshot.meal_id])
	_enqueue({"occurrence_id": id, "trigger": "meal.completed", "minute": snapshot.minute, "actor": {"kind": "resident", "id": person.id}, "payload": payload}, person)

func _on_construction_completed(snapshot: Dictionary, source_ref: WeakRef) -> void:
	var building: RefCounted = source_ref.get_ref()
	if building == null or not snapshot.get("initial_construction", false): return
	var id := JSON.stringify(["construction.completed", String(building.id), _source_generation(building)])
	var minute: int = snapshot.minute if snapshot.minute >= 0 else _clock.total_minutes
	var payload := snapshot.duplicate(true)
	payload.erase("minute")
	payload["timestamp_source"] = "caller" if snapshot.minute >= 0 else "completion_signal"
	var context := {"occurrence_id": id, "trigger": "construction.completed", "minute": minute, "building": {"kind": "building", "id": snapshot.building_id}, "payload": payload}
	var candidates: Array = []
	for resident_id in snapshot.assigned_builder_ids: candidates.append({"kind": "resident", "id": resident_id})
	_enqueue(context, null, null, candidates)

func _sync_residents() -> void:
	for id in _tracked.keys():
		var row: Dictionary = _tracked[id]
		if _control.get_resident(id) == row.data: continue
		if row.data.skill_raised.is_connected(row.callback): row.data.skill_raised.disconnect(row.callback)
		_tracked.erase(id)
		facts.register_entity({"kind": "resident", "id": id}, false)
	for data in _control.get_residents():
		if not _tracked.has(data.id):
			var callback := _on_skill_raised.bind(data)
			_tracked[data.id] = {"data": data, "generation": _source_generation(data), "callback": callback}
			data.skill_raised.connect(callback)
		facts.register_entity({"kind": "resident", "id": data.id}, _active(data))

func _source_generation(data: RefCounted) -> int:
	for row in _source_generations:
		if row.reference.get_ref() == data: return row.generation
	_source_generations = _source_generations.filter(func(row): return row.reference.get_ref() != null)
	_registration_sequence += 1
	_source_generations.append({"reference": weakref(data), "generation": _registration_sequence})
	return _registration_sequence

func _on_skill_raised(transition_id: int, skill: Skill.Type, previous_rank: int, new_rank: int, data: RefCounted) -> void:
	if skill not in Skill.Type.values() or transition_id <= 0 or previous_rank not in Skill.Rank.values() or new_rank not in Skill.Rank.values() or new_rank <= previous_rank: return
	var row: Dictionary = _tracked.get(data.id, {})
	if row.is_empty() or row.data != data: return
	var id := JSON.stringify(["skill.raised", data.id, row.generation, transition_id])
	if _outcomes.has(id) or _pending_ids.has(id): return
	var context := {"occurrence_id": id, "trigger": "skill.raised", "minute": _clock.total_minutes, "actor": {"kind": "resident", "id": data.id}, "payload": {"skill": Skill.Type.keys()[skill].to_lower(), "skill_name": Skill.display_name(skill), "previous_rank": previous_rank, "new_rank": new_rank, "previous_rank_name": Skill.rank_name(previous_rank as Skill.Rank), "new_rank_name": Skill.rank_name(new_rank as Skill.Rank)}}
	_enqueue(context, data)

func _enqueue(context: Dictionary, source: RefCounted, other: RefCounted = null, candidates: Variant = null) -> void:
	var id: String = context.occurrence_id
	if _outcomes.has(id) or _pending_ids.has(id): return
	_last_occurrence = context.duplicate(true)
	_pending_ids[id] = true
	_queue.append({"context": context, "source": source, "other": other, "candidates": candidates})
	if _draining: return
	_draining = true
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var result := _process_occurrence(item.context, item.source, item.other, item.candidates)
		var token: String = item.context.occurrence_id
		_outcomes[token] = result.duplicate(true)
		_pending_ids.erase(token)
		if result.status == "completed":
			executor.publish(token)
			event_completed.emit(result.duplicate(true))
	_draining = false

func _process_occurrence(context: Dictionary, source: RefCounted, expected_other: RefCounted = null, candidates: Variant = null) -> Dictionary:
	if not enabled: return {"status": "disabled"}
	var required_main: Variant = null
	if candidates != null:
		var choice := candidate_picker.choose(candidates, _control, _active)
		if choice.status != "chosen": return {"status": choice.status}
		source = choice.person
		context["actor"] = choice.reference
		context.payload["eligible_candidate_count"] = choice.candidate_count
		required_main = choice.reference
		_last_occurrence = context.duplicate(true)
	if not _active(source): return {"status": "inactive_source"}
	facts.register_entity(context.actor, true)
	var evaluation_facts: RefCounted = facts
	if context.trigger == "social.resolved":
		var second: RefCounted = _control.get_resident(context.other.id)
		if second != expected_other or not _active(second): return {"status": "inactive_social_pair"}
		evaluation_facts = ResidentFacts.snapshot(source, second, _clock.total_minutes)
	elif context.trigger == "meal.completed":
		evaluation_facts = ResidentFacts.snapshot(source, null, _clock.total_minutes)
	selector.facts = evaluation_facts
	executor.setup(_control, evaluation_facts, _active)
	var result := _select_and_commit(context, source, required_main)
	selector.facts = facts
	executor.setup(_control, facts, _active)
	return result

func _select_and_commit(context: Dictionary, source: RefCounted, required_main: Variant = null) -> Dictionary:
	var selection: Dictionary = selector.run(context, _history, true)
	if selection.status != "selected": return {"status": selection.status}
	if required_main != null and selection.main != required_main: return {"status": "invalid_candidate_main"}
	var minute: int = _clock.total_minutes
	var result := executor.execute(selection, context, minute, source)
	if result.status != "completed": return result
	_completed[context.occurrence_id] = result.duplicate(true)
	if not selection.cooldown_key.is_empty(): _history[selection.cooldown_key] = minute
	return result

func replay(occurrence_id: String) -> Dictionary:
	if _outcomes.has(occurrence_id):
		var result: Dictionary = _outcomes[occurrence_id].duplicate(true)
		result.duplicate = true
		return result
	return {"status": "pending" if _pending_ids.has(occurrence_id) else "unknown_occurrence"}

func last_occurrence() -> Dictionary: return _last_occurrence.duplicate(true)
func completed_events() -> Dictionary: return _completed.duplicate(true)
func cooldown_history() -> Dictionary: return _history.duplicate(true)

func _exit_tree() -> void:
	for row in _meal_sources:
		var controller: Node = row.reference.get_ref()
		if controller != null and controller.meal_completed.is_connected(row.callback): controller.meal_completed.disconnect(row.callback)
	_meal_sources.clear()
	for row in _construction_sources:
		var building: RefCounted = row.reference.get_ref()
		if building != null and building.construction_completed.is_connected(row.callback): building.construction_completed.disconnect(row.callback)
	_construction_sources.clear()
	if is_instance_valid(_social_source) and _social_source.interaction_committed.is_connected(_on_social_committed): _social_source.interaction_committed.disconnect(_on_social_committed)
	for row in _tracked.values():
		if row.data.skill_raised.is_connected(row.callback): row.data.skill_raised.disconnect(row.callback)
	_tracked.clear()
	if is_instance_valid(_control) and _control.residents_changed.is_connected(_sync_residents): _control.residents_changed.disconnect(_sync_residents)
