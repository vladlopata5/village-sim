extends Node
## Ordinary WORK: stone/clay in a personal area or hut; hut COLLECT -> MINE -> EXPORT.
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
const Context = preload("res://scripts/natural_work_context.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Source = preload("res://scripts/resource_source_ref.gd")
const TargetScore = preload("res://scripts/work_target_score.gd")
var committed_context: RefCounted
func _resource() -> int:
	return Resources.CLAY if runtime.data.profession==Profession.Type.CLAY_DIGGER else Resources.STONE
func _context() -> RefCounted:
	if world==null or runtime.data.profession not in [Profession.Type.MINER,Profession.Type.CLAY_DIGGER]: return null
	if not runtime.data.work_location_id.is_empty():
		var place = world.player_control.get_building(runtime.data.work_location_id)
		if place==null or not place.is_built() or place.type!=(Types.CLAY_HUT if _resource()==Resources.CLAY else Types.QUARRY) or not world.world_locations.get_position(place.id) is Vector2: return null
		return Context.for_building(place,world.work_areas)
	var area = world.work_areas.get_area(runtime.data.work_area_id)
	return Context.new(area) if area!=null else null
func _room(context: RefCounted) -> bool:
	return context.workplace==null or context.workplace.resources.get_available_free_capacity(_resource())>=1
func _transport_eligible(id: StringName, source_ref: RefCounted = null) -> bool:
	var context := _context()
	return context!=null and context.workplace!=null and context.workplace.id==id and clock.get_phase()=="День" and runtime.data.inventory.amount==0 and not runtime.intents.has_current_action() and (source_ref == null or world.logistics.sources.ground_allowed(source_ref,runtime.view.get_sim_position(),context.workplace,context.area))

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
	var context := _context()
	return context.area if context!=null else null
func _identity(area: RefCounted) -> Array:
	var context := _context()
	var room: int = context.workplace.resources.get_available_free_capacity(_resource()) if context.workplace!=null else -1
	return world.logistics.sources.GroundAreas.identity(runtime.view.get_sim_position(),context.workplace,context.area) + [world.logistics.sources.revision,room,runtime.data.work_location_id,runtime.data.work_area_id,area.id,area.revision,area.center,area.radius,Engine.get_process_frames(),clock.total_minutes,locations.navigation.revision,runtime.view.get_sim_position()]
func _eligible(source: RefCounted, area: RefCounted) -> bool:
	return source in rocks and source.resource_type==_resource() and source.position.is_finite() and source.stock > 0 and source.reservation_owner_id.is_empty() and area.contains(source.position)
func best_target() -> Dictionary:
	var context := _context()
	if context==null or not _room(context):return {}
	var area = context.area
	var eligible: Array = rocks.filter(func(source): return _eligible(source,area))
	if context.workplace!=null:
		eligible=TargetScore.ordered(eligible,runtime.view.get_sim_position(),context.workplace.position,func(source):return source.position,func(source):return source.id)
	else:
		eligible.sort_custom(func(a,b):
			var first: float = area.center.distance_squared_to(a.position)
			var second: float = area.center.distance_squared_to(b.position)
			return String(a.id)<String(b.id) if first==second else first<second)
	for source in eligible:
		var point: Variant = locations.resolve(source,runtime.view.get_sim_position())
		if point is Vector2: return {"kind":&"MINE","rock":source,"point":point}
	return {}
func best_task() -> Dictionary:
	var context := _context()
	if context==null: return {}
	if context.workplace==null: return best_target()
	var place = context.workplace
	var origin: Vector2 = runtime.view.get_sim_position()
	var access: Vector2 = world.world_locations.get_position(place.id)
	if _room(context):
		var matches: Array = world.logistics.sources.find_ground_in_area(_resource(),context.area,origin,access,place)
		if not matches.is_empty(): return {"kind":&"COLLECT","source":matches[0],"destination":place}
		var extraction := best_target()
		if not extraction.is_empty(): return extraction
	var source_ref := Source.new(Source.Kind.CONTAINER,place.id)
	if not world.logistics.sources.available(source_ref,_resource()) or not world.logistics.sources.reachable(origin,access): return {}
	var destinations: Array = world.logistics.sources.storage_destinations(source_ref,_resource(),access)
	return {"kind":&"EXPORT","source":source_ref,"destination":destinations[0]} if not destinations.is_empty() else {}
func has_work() -> bool:
	_available = {}
	var area = _area()
	if clock.get_phase() != "День" or area == null or runtime.data.inventory.amount != 0 or world.logistics.get_job(runtime.data.id)!=null: return false
	_available = best_task()
	_cache_identity = _identity(area)
	return not _available.is_empty()
func _candidate_valid(candidate: Dictionary, context: RefCounted) -> bool:
	if candidate.is_empty(): return false
	if candidate.kind==&"MINE": return _room(context) and _eligible(candidate.rock,context.area) and locations.is_available(candidate.point)
	if context.workplace==null: return false
	if not world.logistics.sources.available(candidate.source,_resource()): return false
	if candidate.kind==&"COLLECT": return _room(context) and candidate.destination==context.workplace and world.logistics.sources.ground_allowed(candidate.source,runtime.view.get_sim_position(),context.workplace,context.area)
	return candidate.source.id==context.workplace.id and candidate.destination.is_built() and candidate.destination.resources.get_available_free_capacity(_resource())>=1
func request_work() -> bool:
	if clock.get_phase() != "День" or runtime.intents.has_current_action() or runtime.data.inventory.amount != 0: return false
	var context := _context()
	if context == null: return false
	var area = context.area
	var candidate := _available
	_available = {}
	if _cache_identity != _identity(area) or not _candidate_valid(candidate,context): candidate = best_task()
	if candidate.is_empty(): return false
	if candidate.kind!=&"MINE":
		var job: RefCounted
		if candidate.kind==&"COLLECT": job = world.logistics.claim_internal(runtime.data.id,candidate.source,context.workplace,_resource(),_transport_eligible.bind(context.workplace.id,candidate.source))
		else: job = world.logistics.claim_worker_export(runtime.data.id,context.workplace,candidate.destination,_resource(),_transport_eligible.bind(context.workplace.id,candidate.source))
		if job==null: return false
		if world.logistics.start_claimed_job(job,runtime.data.id): return true
		world.logistics.cancel_job(job)
		return false
	committed_context = context
	rock = candidate.rock
	target = candidate.point
	_mutating = true
	var claimed: bool = rock.claim(StringName(runtime.data.id))
	_mutating = false
	if not claimed or _interrupt_pending:
		abort(false)
		return false
	_intent = Intent.new(Intent.Type.MOVE_TO,&"mine_clay" if rock.resource_type==Resources.CLAY else &"mine_rock",target,Balance.WORK_PRIORITY,false)
	if not runtime.intents.submit(_intent):
		abort(false)
		return false
	if runtime.logger != null: runtime.logger.info(EventLog.AI,"%s: выбрал добычу %s — %s" % [runtime.data.resident_name,"глины" if rock.resource_type==Resources.CLAY else "камня",rock.id])
	return true
func assignment_changed() -> void:
	# CL1 requires incompatible accepted clay work to end on area/assignment edits.
	if rock!=null and rock.resource_type==Resources.CLAY:
		var context := _context()
		if context==null or context.workplace!=committed_context.workplace or not context.area.contains(rock.position): abort(false)
func _valid() -> bool:
	return committed_context!=null and (committed_context.workplace==null or (world.player_control.get_building(committed_context.workplace.id)==committed_context.workplace and committed_context.workplace.is_built())) and rock != null and rock in rocks and rock.stock > 0 and rock.reservation_owner_id == StringName(runtime.data.id) and locations.is_available(target) and locations.in_range(rock,target)
func _arrived(intent: RefCounted) -> void:
	if intent != _intent: return
	if not _valid() or not locations.in_range(rock,runtime.view.get_sim_position()) or runtime.view.get_sim_position().distance_to(target)>8.0:
		abort()
		return
	mining = true
	_last_minute = clock.total_minutes
	runtime.data.activity = Activity.Type.WORKING
	if runtime.logger != null: runtime.logger.info(EventLog.AI,"%s: начал добычу %s — %s" % [runtime.data.resident_name,"глины" if rock.resource_type==Resources.CLAY else "камня",rock.id])
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
	committed_context = null
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
