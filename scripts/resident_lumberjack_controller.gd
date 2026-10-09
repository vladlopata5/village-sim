extends Node
## Resident-owned world work; ordinary WORK selection remains in the existing AI.
const Profession = preload("res://scripts/resident_profession.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const TreeData = preload("res://scripts/tree_data.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var runtime: Node
var clock: Node
var trees: Array
var locations: RefCounted
var complete_tree: Callable
var logger: RefCounted
var tree: RefCounted
var target: Vector2
var chopping := false
var _intent: RefCounted
var _last_minute := 0
var _cleaning := false
func setup(owner_runtime: Node, game_clock: Node, world_trees: Array, resolver: RefCounted, completion: Callable) -> void:
	runtime = owner_runtime
	clock = game_clock
	trees = world_trees
	locations = resolver
	complete_tree = completion
	logger = runtime.logger
	runtime.intents.intent_arrived.connect(_arrived)
	runtime.intents.intent_changed.connect(_changed)
	runtime.intents.forced_interrupt.connect(_forced)
	clock.minute_changed.connect(_minute)
	clock.phase_changed.connect(_phase)
func best_target() -> Dictionary:
	var best: Dictionary = {}
	var distance := INF
	var origin: Vector2 = runtime.view.get_sim_position()
	for candidate in trees:
		if candidate.state != TreeData.State.STANDING or not candidate.reservation_owner_id.is_empty(): continue
		var point: Variant = locations.resolve(candidate,origin)
		if not point is Vector2: continue
		var value := origin.distance_squared_to(candidate.position)
		if best.is_empty() or value < distance or (value == distance and String(candidate.id) < String(best.tree.id)):
			best = {"tree":candidate,"point":point}
			distance = value
	return best
func has_work() -> bool:
	return runtime.data.profession == Profession.Type.LUMBERJACK and clock.get_phase() == "День" and not best_target().is_empty()
func request_work() -> bool:
	if runtime.data.profession != Profession.Type.LUMBERJACK or clock.get_phase() != "День" or runtime.intents.has_current_action(): return false
	var candidate := best_target()
	if candidate.is_empty() or not candidate.tree.claim(StringName(runtime.data.id)): return false
	tree = candidate.tree
	target = candidate.point
	_intent = Intent.new(Intent.Type.MOVE_TO,&"chop_tree",target,Balance.WORK_PRIORITY,false)
	if not runtime.intents.submit(_intent):
		abort(false)
		return false
	if logger != null: logger.info(EventLog.AI,"%s: выбрал дерево — %s" % [runtime.data.resident_name,tree.id])
	return true
func _arrived(intent: RefCounted) -> void:
	if intent != _intent: return
	if not _valid() or runtime.view.get_sim_position().distance_to(target) > 8.0:
		abort()
		return
	chopping = true
	_last_minute = clock.total_minutes
	runtime.data.activity = Activity.Type.WORKING
	if logger != null: logger.info(EventLog.PRODUCTION,"%s: начал рубку — %s" % [runtime.data.resident_name,tree.id])
func _valid() -> bool:
	return tree != null and tree in trees and tree.state == TreeData.State.STANDING and tree.reservation_owner_id == StringName(runtime.data.id) and locations.is_available(target)
func _accrue(now: int) -> void:
	if not chopping or tree == null: return
	var elapsed := maxi(now-_last_minute,0)
	_last_minute = now
	if runtime.data.activity == Activity.Type.WORKING and runtime.view.get_sim_position().distance_to(target) <= 8.0:
		tree.add_work(StringName(runtime.data.id),elapsed)
func _minute(now: int) -> void:
	if tree == null: return
	if not _valid():
		abort()
		return
	_accrue(now)
	if tree.state == TreeData.State.DEPLETED:
		var completed = tree
		var old = _intent
		_cleaning = true
		tree = null
		_intent = null
		chopping = false
		complete_tree.call(completed)
		runtime.data.add_skill_xp(Skill.Type.GATHERING,1)
		_cleaning = false
		if logger != null: logger.info(EventLog.PRODUCTION,"%s: срубил дерево — %s" % [runtime.data.resident_name,completed.id])
		runtime.intents.clear_completed(old)
func abort(reconsider: bool = true) -> void:
	if _cleaning or tree == null: return
	_cleaning = true
	_accrue(clock.total_minutes)
	tree.release(StringName(runtime.data.id))
	var old = _intent
	tree = null
	_intent = null
	chopping = false
	if runtime.intents.current_intent == old: runtime.intents.cancel_current(old)
	_cleaning = false
	if reconsider: runtime.decision.call_deferred("request_decision","lumberjack_aborted")
func _changed(intent: RefCounted) -> void:
	if _intent != null and intent != _intent: abort(false)
func _forced(_previous: RefCounted) -> void: abort(false)
func _phase(phase: String) -> void:
	if phase != "День": abort()
func _exit_tree() -> void: abort(false)
