extends Node
## FREE mining participates in ordinary WORK; no hauling or building policy here.
const Profession = preload("res://scripts/resident_profession.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var runtime: Node
var clock: Node
var world: Node
var rocks: Array
var locations: RefCounted
var complete_cycle: Callable
var rock: RefCounted
var target: Vector2
var mining := false
var _intent: RefCounted
var _last_minute := 0
var _mutating := false
var _interrupt_pending := false
var _cleaning := false
var _available: Dictionary = {}
var _cache_identity: Array = []
func setup(owner_runtime: Node, game_clock: Node, sources: Array, resolver: RefCounted, completion: Callable) -> void:
	runtime = owner_runtime
	clock = game_clock
	rocks = sources
	locations = resolver
	complete_cycle = completion
	runtime.intents.intent_arrived.connect(_arrived)
	runtime.intents.intent_changed.connect(_changed)
	runtime.intents.forced_interrupt.connect(_forced)
	clock.minute_changed.connect(_minute)
	clock.phase_changed.connect(_phase)
func _area() -> RefCounted:
	if world == null or runtime.data.profession != Profession.Type.MINER or not runtime.data.work_location_id.is_empty(): return null
	return world.work_areas.get_area(runtime.data.work_area_id)
func _identity(area: RefCounted) -> Array:
	return [area.id,area.revision,area.center,area.radius,Engine.get_process_frames(),clock.total_minutes,locations.navigation.revision,runtime.view.get_sim_position()]
func _eligible(source: RefCounted, area: RefCounted) -> bool:
	return source in rocks and source.position.is_finite() and source.stock > 0 and source.reservation_owner_id.is_empty() and area.contains(source.position)
func best_target() -> Dictionary:
	var area = _area()
	if area == null: return {}
	var eligible: Array = rocks.filter(func(source): return _eligible(source,area))
	eligible.sort_custom(func(a,b):
		var first: float = area.center.distance_squared_to(a.position)
		var second: float = area.center.distance_squared_to(b.position)
		return String(a.id)<String(b.id) if first==second else first<second)
	for source in eligible:
		var point: Variant = locations.resolve(source,runtime.view.get_sim_position())
		if point is Vector2: return {"rock":source,"point":point}
	return {}
func has_work() -> bool:
	_available = {}
	var area = _area()
	if clock.get_phase() != "День" or area == null or runtime.data.inventory.amount != 0: return false
	_available = best_target()
	_cache_identity = _identity(area)
	return not _available.is_empty()
func request_work() -> bool:
	if clock.get_phase() != "День" or runtime.intents.has_current_action() or runtime.data.inventory.amount != 0: return false
	var area = _area()
	if area == null: return false
	var candidate := _available
	_available = {}
	if candidate.is_empty() or _cache_identity != _identity(area) or not _eligible(candidate.rock,area) or not locations.is_available(candidate.point): candidate = best_target()
	if candidate.is_empty(): return false
	rock = candidate.rock
	target = candidate.point
	_mutating = true
	var claimed: bool = rock.claim(StringName(runtime.data.id))
	_mutating = false
	if not claimed or _interrupt_pending:
		abort(false)
		return false
	_intent = Intent.new(Intent.Type.MOVE_TO,&"mine_rock",target,Balance.WORK_PRIORITY,false)
	if not runtime.intents.submit(_intent):
		abort(false)
		return false
	if runtime.logger != null: runtime.logger.info(EventLog.AI,"%s: выбрал добычу камня — %s" % [runtime.data.resident_name,rock.id])
	return true
func _valid() -> bool:
	return rock != null and rock in rocks and rock.stock > 0 and rock.reservation_owner_id == StringName(runtime.data.id) and locations.is_available(target) and locations.in_range(rock,target)
func _arrived(intent: RefCounted) -> void:
	if intent != _intent: return
	if not _valid() or not locations.in_range(rock,runtime.view.get_sim_position()) or runtime.view.get_sim_position().distance_to(target)>8.0:
		abort()
		return
	mining = true
	_last_minute = clock.total_minutes
	runtime.data.activity = Activity.Type.WORKING
	if runtime.logger != null: runtime.logger.info(EventLog.AI,"%s: начал добычу камня — %s" % [runtime.data.resident_name,rock.id])
func _accrue(now: int) -> bool:
	if not mining or not _valid() or not is_instance_valid(runtime.view) or not locations.in_range(rock,runtime.view.get_sim_position()) or runtime.view.get_sim_position().distance_to(target)>8.0: return false
	var elapsed := maxi(now-_last_minute,0)
	_last_minute = now
	# Hold interrupts until receipt publication and XP; signals may be reentrant.
	_mutating = true
	var source = rock
	var receipt: int = source.add_work(StringName(runtime.data.id),elapsed)
	if receipt > 0:
		mining = false
		complete_cycle.call(source,receipt,runtime.view.get_sim_position())
		runtime.data.add_skill_xp(Skill.Type.GATHERING,1)
	_mutating = false
	return receipt > 0
func _minute(now: int) -> void:
	if _intent == null or _mutating: return
	if not _valid():
		abort()
		return
	if _accrue(now): _finish()
	elif _interrupt_pending: abort(false)
func _cleanup() -> RefCounted:
	_cleaning = true
	_available = {}
	var previous = _intent
	_intent = null
	mining = false
	if rock != null: rock.release(StringName(runtime.data.id))
	rock = null
	_interrupt_pending = false
	_cleaning = false
	return previous
func _finish() -> void:
	var previous = _cleanup()
	if previous != null and runtime.intents.current_intent == previous: runtime.intents.clear_completed(previous)
func abort(reconsider: bool = true) -> void:
	if _mutating:
		_interrupt_pending = true
		return
	if _cleaning or rock == null: return
	# Already elapsed work wins a completion edge; later work is never accrued.
	if _accrue(clock.total_minutes):
		_finish()
		return
	var previous = _cleanup()
	if previous != null and runtime.intents.current_intent == previous: runtime.intents.cancel_current(previous)
	if reconsider: runtime.decision.call_deferred("request_decision","miner_aborted")
func _changed(intent: RefCounted) -> void:
	if _intent != null and intent != _intent: abort(false)
func _forced(_previous: RefCounted) -> void: abort(false)
func _phase(phase: String) -> void:
	if phase != "День": abort()
func _exit_tree() -> void: abort(false)
