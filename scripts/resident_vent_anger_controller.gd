extends Node
## Non-destructive tree interaction. Owns only its intent, never forestry claims/progress.
const Intent = preload("res://scripts/resident_intent.gd")
const TreeData = preload("res://scripts/tree_data.gd")
const Balance = preload("res://scripts/balance_config.gd")
var runtime: Node
var clock: Node
var trees: Array
var locations: RefCounted
var _active: RefCounted
var _tree: RefCounted
var _target: Vector2
var _ends_at := -1
var _on_success: Callable
func setup(owner_runtime: Node, game_clock: Node, world_trees: Array, resolver: RefCounted) -> void:
	runtime=owner_runtime;clock=game_clock;trees=world_trees;locations=resolver
	clock.minute_changed.connect(_on_minute)
	runtime.intents.intent_arrived.connect(_on_arrival)
	runtime.intents.intent_changed.connect(_on_intent_changed)
func has_action() -> bool:
	return not _find_target().is_empty()
func _find_target() -> Dictionary:
	var origin: Vector2=runtime.view.get_sim_position()
	var candidates: Array=trees.filter(func(tree):return tree.state==TreeData.State.STANDING and tree.reservation_owner_id.is_empty())
	candidates.sort_custom(func(a,b):
		var first: float=a.position.distance_squared_to(origin);var second: float=b.position.distance_squared_to(origin)
		return first<second if first!=second else String(a.id)<String(b.id))
	for tree in candidates:
		var point: Variant=locations.resolve(tree,origin)
		if point is Vector2 and locations.is_available(point):
			return {"tree":tree,"point":point}
	return {}
func start(priority: int, admitted: Callable, on_success: Callable) -> bool:
	if _active!=null or not runtime.intents.is_ordinary_idle(): return false
	var target := _find_target() # Revalidate live geometry/availability at commit, without retaining probes.
	if target.is_empty() or not admitted.call(): return false
	var candidate: RefCounted=target.tree
	if candidate not in trees or candidate.state!=TreeData.State.STANDING or not candidate.reservation_owner_id.is_empty(): return false
	_tree=candidate;_target=target.point;_on_success=on_success;_ends_at=-1
	_tree.changed.connect(_on_tree_changed)
	_active=Intent.new(Intent.Type.MOVE_TO,&"vent_anger",_target,priority,true)
	if not runtime.intents.submit(_active): _reset();return false
	return _active!=null and runtime.intents.current_intent==_active
func _valid_target() -> bool:
	return _tree!=null and _tree in trees and _tree.state==TreeData.State.STANDING and locations.is_available(_target)
func _on_arrival(intent: RefCounted) -> void:
	if intent!=_active: return
	if not _valid_target() or not locations.in_range(_tree,runtime.view.get_sim_position()): _abort();return
	var previous: RefCounted=_active
	_active=Intent.new(Intent.Type.NONE,&"vent_anger",Vector2.ZERO,previous.priority,true)
	_ends_at=clock.total_minutes+Balance.VENT_ANGER_MINUTES
	if not runtime.intents.continue_intent(previous,_active): _reset()
	# Existing stationary idle pose is the animation placeholder, as for a WANDER stay.
	# Owned intent prevents this from counting as ordinary idle/RESTLESS boredom.
func _on_minute(minute: int) -> void:
	if _active==null: return
	if not _valid_target() or (_ends_at>=0 and not locations.in_range(_tree,runtime.view.get_sim_position())): _abort();return
	if _ends_at<0 or minute<_ends_at: return
	var completed: RefCounted=_active;var callback: Callable=_on_success
	_reset() # Before store callbacks: nested cancellation/completion cannot apply twice.
	if callback.is_valid(): callback.call()
	runtime.intents.clear_completed(completed)
func _on_tree_changed() -> void:
	if _active!=null and not _valid_target(): _abort()
func _on_intent_changed(intent: RefCounted) -> void:
	if _active!=null and intent!=_active: _reset()
func _abort() -> void:
	var previous: RefCounted=_active
	_reset()
	if previous!=null and runtime.intents.abort_current(previous): runtime.decision.request_decision("moodlet_action_unavailable")
func _reset() -> void:
	if _tree!=null and _tree.changed.is_connected(_on_tree_changed): _tree.changed.disconnect(_on_tree_changed)
	_active=null;_tree=null;_ends_at=-1;_on_success=Callable()
func _exit_tree() -> void: _reset()
