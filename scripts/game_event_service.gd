extends Node
## Live trigger adapter. Selection and atomic consequence execution stay separate.
const Facts = preload("res://scripts/event_facts.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const DryRunner = preload("res://scripts/event_dry_run.gd")
const EffectExecutor = preload("res://scripts/event_effect_executor.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
signal event_completed(result: Dictionary)
var enabled := true
var facts := Facts.new()
var catalog := Catalog.new()
var selector := DryRunner.new(catalog, facts)
var executor := EffectExecutor.new()
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

func _init() -> void:
	selector.rng.randomize() # Own stream; never consumes social or resident RNG.
	selector.set_chance("skill.raised", Balance.SKILL_RAISED_EVENT_CHANCE)
	if not catalog.load_file("res://assets/events/skill_progress.json", facts): push_error(str(catalog.errors))

func setup(control: RefCounted, clock: Node, active_guard: Callable) -> void:
	assert(_control == null or _control == control, "Event service belongs to one world")
	_control = control
	_clock = clock
	_active_guard = active_guard
	executor.setup(_control, facts, _active)
	if not _control.residents_changed.is_connected(_sync_residents): _control.residents_changed.connect(_sync_residents)
	_sync_residents()

func _active(data: RefCounted) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _control != null and _control.get_resident(data.id) == data and _active_guard.is_valid() and _active_guard.call(data)

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

func _on_skill_raised(transition_id: int, skill: Skill.Type, previous_level: int, new_level: int, data: RefCounted) -> void:
	if skill not in Skill.Type.values() or transition_id <= 0 or previous_level < 0 or new_level <= previous_level or new_level > Balance.MAX_SKILL_LEVEL: return
	var row: Dictionary = _tracked.get(data.id, {})
	if row.is_empty() or row.data != data: return
	var id := JSON.stringify(["skill.raised", data.id, row.generation, transition_id])
	if _outcomes.has(id) or _pending_ids.has(id): return
	var context := {"occurrence_id": id, "trigger": "skill.raised", "minute": _clock.total_minutes, "actor": {"kind": "resident", "id": data.id}, "payload": {"skill": Skill.Type.keys()[skill].to_lower(), "skill_name": Skill.display_name(skill), "previous_level": previous_level, "new_level": new_level}}
	_last_occurrence = context.duplicate(true)
	_pending_ids[id] = true
	_queue.append({"context": context, "source": data})
	if _draining: return
	_draining = true
	while not _queue.is_empty():
		var item: Dictionary = _queue.pop_front()
		var result := _process_occurrence(item.context, item.source)
		var token: String = item.context.occurrence_id
		_outcomes[token] = result.duplicate(true)
		_pending_ids.erase(token)
		if result.status == "completed":
			executor.publish(token)
			event_completed.emit(result.duplicate(true))
	_draining = false

func _process_occurrence(context: Dictionary, source: RefCounted) -> Dictionary:
	if not enabled: return {"status": "disabled"}
	if not _active(source): return {"status": "inactive_source"}
	facts.register_entity(context.actor, true)
	var selection: Dictionary = selector.run(context, _history, true)
	if selection.status != "selected": return {"status": selection.status}
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
	for row in _tracked.values():
		if row.data.skill_raised.is_connected(row.callback): row.data.skill_raised.disconnect(row.callback)
	_tracked.clear()
	if is_instance_valid(_control) and _control.residents_changed.is_connected(_sync_residents): _control.residents_changed.disconnect(_sync_residents)
