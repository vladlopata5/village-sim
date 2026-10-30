extends Node
## Narrow registry of ordinary action executors unlocked by active moodlet types.
var runtime: Node
var clock: Node
var _actions: Dictionary = {}
func setup(owner_runtime: Node, game_clock: Node) -> void:
	runtime = owner_runtime
	clock = game_clock
func register_action(id: String, moodlet_type: String, priority: int, executor: Node) -> void:
	assert(not id.is_empty() and not moodlet_type.is_empty() and priority>0 and not _actions.has(id))
	_actions[id] = {"type":moodlet_type, "priority":priority, "executor":executor}
func _unlocked(moodlet_type: String) -> bool:
	return not runtime.data.moodlets.active(clock.total_minutes,{"type":moodlet_type}).is_empty()
func collect_actions() -> Array:
	var actions: Array = []
	if not runtime.intents.is_ordinary_idle() or runtime.data.moodlets.size()==0: return actions
	for id in _actions:
		var row: Dictionary = _actions[id]
		if _unlocked(row.type) and is_instance_valid(row.executor) and row.executor.has_action(): actions.append({"id":id,"priority":row.priority})
	return actions
func start(id: String, priority: int) -> bool:
	if not _actions.has(id) or not runtime.intents.is_ordinary_idle(): return false
	var row: Dictionary = _actions[id]
	return _unlocked(row.type) and is_instance_valid(row.executor) and row.executor.start(priority,_unlocked.bind(row.type),_remove_unlock.bind(row.type))
func _remove_unlock(moodlet_type: String) -> void:
	var store: RefCounted = runtime.data.moodlets
	for entry: Dictionary in store.find({"type":moodlet_type}):
		if store.get_entry(entry.id)==entry: store.remove(entry.id)
