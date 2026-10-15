extends Node
## Ordinary WORK: building collect/chop/plant/export, or independent-area chop.
const Profession = preload("res://scripts/resident_profession.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const TreeData = preload("res://scripts/tree_data.gd")
const Resources = preload("res://scripts/resource_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var runtime: Node
var clock: Node
var trees: Array
var locations: RefCounted
var complete_tree: Callable
var logger: RefCounted
var world: Node
var tree: RefCounted
var hut: RefCounted
const Context = preload("res://scripts/forestry_work_context.gd")
var committed_context: RefCounted
var target: Vector2
var chopping := false
var kind := &""
var work_minutes := 0
var _intent: RefCounted
var _last_minute := 0
var _cleaning := false
var _mutating := false
var _interrupt_pending := false
func _context() -> RefCounted:
	if world == null or runtime.data.profession != Profession.Type.LUMBERJACK: return null
	if not runtime.data.work_location_id.is_empty():
		var building = _current_hut()
		return Context.for_building(building) if building != null else null
	var area = world.work_areas.get_area(runtime.data.work_area_id)
	return Context.new(area) if area != null else null
func _context_valid() -> bool:
	return committed_context != null and (committed_context.mode == Context.Mode.FREE or _hut_valid())
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
func _current_hut() -> RefCounted:
	if world == null or runtime.data.profession != Profession.Type.LUMBERJACK: return null
	var building = world.player_control.get_building(runtime.data.work_location_id)
	return building if building != null and building.is_built() and building.type == BuildingType.Type.LUMBERJACK_HUT and world.world_locations.get_position(building.id) is Vector2 else null
func _path(from_position: Vector2, to_position: Vector2) -> bool:
	return locations.navigation.has_walkable_path(Coordinates.to_world(from_position),Coordinates.to_world(to_position))
func _eligible_tree(candidate: RefCounted, context: RefCounted) -> bool:
	return candidate in trees and candidate.position.is_finite() and candidate.state==TreeData.State.STANDING and candidate.reservation_owner_id.is_empty() and context.area.contains(candidate.position) and (context.mode == Context.Mode.FREE or context.hut.resources.get_available_free_capacity(Resources.Type.LOG)>=candidate.yield_amount)
func best_target() -> Dictionary:
	var context = _context()
	if context == null: return {}
	var eligible: Array = trees.filter(func(candidate): return _eligible_tree(candidate,context))
	eligible.sort_custom(func(a,b):
		var first: float = context.area.center.distance_squared_to(a.position)
		var second: float = context.area.center.distance_squared_to(b.position)
		return String(a.id)<String(b.id) if first==second else first<second)
	var origin: Vector2 = runtime.view.get_sim_position()
	for candidate in eligible:
		var point: Variant = locations.resolve(candidate,origin)
		if point is Vector2: return {"kind":&"CHOP","tree":candidate,"point":point}
	return {}
func best_task() -> Dictionary:
	var context = _context()
	if context == null or not is_instance_valid(runtime.view): return {}
	if context.mode == Context.Mode.FREE: return best_target()
	var workplace = context.hut
	var origin: Vector2 = runtime.view.get_sim_position()
	var home: Vector2 = world.world_locations.get_position(workplace.id)
	var best: Dictionary = {}
	var distance := INF
	if workplace.resources.get_available_free_capacity(Resources.Type.LOG) >= 1:
		var matches: Array = world.logistics.sources.find_ground_in_area(Resources.Type.LOG,context.area,origin,home,workplace)
		if not matches.is_empty(): best = {"kind":&"COLLECT","reference":matches[0]}
	if not best.is_empty(): return best
	best = best_target()
	if not best.is_empty(): return best
	if world.forestry_area.tree_count(workplace) < workplace.definition.target_tree_count:
		best = world.forestry_area.planting_target(workplace,origin)
		if not best.is_empty(): return best
	if workplace.resources.get_available_amount(Resources.Type.LOG) < 1 or not _path(origin,home): return {}
	distance = INF
	for destination in world.logistics.external_destinations(workplace,Resources.Type.LOG):
		var point: Variant = world.world_locations.get_position(destination.id)
		if not point is Vector2 or not _path(home,point): continue
		var value := home.distance_squared_to(point)
		if best.is_empty() or value < distance or (value==distance and String(destination.id)<String(best.destination.id)):
			distance = value
			best = {"kind":&"EXPORT","destination":destination}
	return best
# One-use availability result, only in this frame/minute and unchanged world.
# It is never a claim and is revalidated before reservation.
var _available_task: Dictionary = {}
var _availability_frame := -1
var _availability_minute := -1
var _availability_revision := -1
var _availability_origin := Vector2.ZERO
var _availability_context: Array = []
var _availability_drops := 0
var _availability_sources := -1
var _availability_room := -1
func has_work() -> bool:
	_available_task = {}
	if clock.get_phase()!="День": return false
	var candidate := best_task()
	if candidate.get("kind") in [&"CHOP",&"COLLECT"]:
		_available_task = candidate
		_availability_frame = Engine.get_process_frames()
		_availability_minute = clock.total_minutes
		_availability_revision = locations.navigation.revision
		_availability_origin = runtime.view.get_sim_position()
		_availability_context = _context().identity() + world.logistics.sources.GroundAreas.identity(_availability_origin,_context().hut,_context().area)
		_availability_drops = world.ground_resources.drops.size()
		_availability_sources = world.logistics.sources.revision
		_availability_room = context_room(_context())
	return not candidate.is_empty()
func _take_available_task() -> Dictionary:
	var candidate := _available_task
	_available_task = {}
	var context = _context()
	if candidate.is_empty() or context==null or not is_instance_valid(runtime.view): return {}
	if _availability_frame!=Engine.get_process_frames() or _availability_minute!=clock.total_minutes or _availability_revision!=locations.navigation.revision or _availability_origin!=runtime.view.get_sim_position() or _availability_context!=context.identity()+world.logistics.sources.GroundAreas.identity(runtime.view.get_sim_position(),context.hut,context.area) or _availability_drops!=world.ground_resources.drops.size() or _availability_sources!=world.logistics.sources.revision or _availability_room!=context_room(context): return {}
	if candidate.kind==&"COLLECT":
		if context.mode!=Context.Mode.BUILDING or context_room(context)<1 or not world.logistics.sources.available(candidate.reference,Resources.Type.LOG): return {}
		return candidate if world.logistics.sources.ground_allowed(candidate.reference,runtime.view.get_sim_position(),context.hut,context.area) else {}
	if not _eligible_tree(candidate.tree,context) or not locations.is_available(candidate.point) or not locations.in_range(candidate.tree,candidate.point): return {}
	return candidate
func context_room(context: RefCounted) -> int:
	return context.hut.resources.get_available_free_capacity(Resources.Type.LOG) if context.mode==Context.Mode.BUILDING else -1
func _collect_eligible(workplace_id: StringName, source_ref: RefCounted) -> bool:
	var place := _current_hut()
	var context = _context()
	return place!=null and place.id==workplace_id and clock.get_phase()=="День" and runtime.data.inventory.amount==0 and not runtime.intents.has_current_action() and context != null and world.logistics.sources.ground_allowed(source_ref,runtime.view.get_sim_position(),place,context.area)
func request_work() -> bool:
	if clock.get_phase() != "День" or runtime.intents.has_current_action() or runtime.data.inventory.amount != 0: return false
	var candidate := _take_available_task()
	if candidate.is_empty(): candidate = best_task()
	if candidate.is_empty(): return false
	if candidate.kind == &"COLLECT":
		var place := _current_hut()
		if place==null: return false
		var job = world.logistics.claim_internal(runtime.data.id,candidate.reference,place,Resources.Type.LOG,_collect_eligible.bind(place.id,candidate.reference))
		if job==null: return false
		job.execution_priority = Balance.WORK_PRIORITY # Preserve former committed forestry route priority.
		if world.logistics.start_claimed_job(job,runtime.data.id): return true
		world.logistics.cancel_job(job)
		return false
	if candidate.kind == &"EXPORT":
		var job = world.logistics.claim_own_export(runtime.data.id,candidate.destination)
		if job == null: return false
		if world.logistics.start_claimed_job(job,runtime.data.id): return true
		world.logistics.cancel_job(job)
		return false
	committed_context = _context()
	if committed_context == null: return false
	hut = committed_context.hut
	kind = candidate.kind
	target = candidate.point
	_mutating = true
	var claimed := false
	if kind==&"CHOP":
		tree = candidate.tree
		claimed = tree.claim(StringName(runtime.data.id))
	elif kind==&"PLANT": claimed = world.forestry_area.claim(runtime.data.id,hut,candidate.spot)
	_mutating = false
	if not claimed or _interrupt_pending:
		abort(false)
		return false
	_intent = Intent.new(Intent.Type.MOVE_TO,_reason(),target,Balance.WORK_PRIORITY,false)
	if not runtime.intents.submit(_intent):
		abort(false)
		return false
	if logger != null: logger.info(EventLog.AI,"%s: forestry %s — %s" % [runtime.data.resident_name,kind,tree.id if tree != null else hut.id])
	return true
func _reason() -> StringName:
	return &"chop_tree" if kind==&"CHOP" else &"plant_tree"
func _hut_valid() -> bool:
	return hut != null and hut in world.buildings and hut.is_built() and world.world_locations.get_position(hut.id) is Vector2
func _arrived(intent: RefCounted) -> void:
	if intent != _intent: return
	if not _context_valid() or runtime.view.get_sim_position().distance_to(target)>8.0:
		abort()
		return
	if kind==&"CHOP" and (not _valid() or not locations.in_range(tree,runtime.view.get_sim_position())):
		abort()
		return
	chopping = kind==&"CHOP"
	work_minutes = 0
	_last_minute = clock.total_minutes
	runtime.data.activity = Activity.Type.WORKING
	if logger != null: logger.info(EventLog.AI,"%s: начал %s" % [runtime.data.resident_name,"рубку" if chopping else "посадку"])
func _valid() -> bool:
	return tree != null and tree in trees and tree.state==TreeData.State.STANDING and tree.reservation_owner_id==StringName(runtime.data.id) and locations.is_available(target) and locations.in_range(tree,target)
func _accrue(now: int) -> void:
	if runtime.data.activity != Activity.Type.WORKING or not is_instance_valid(runtime.view) or runtime.view.get_sim_position().distance_to(target)>8: return
	var elapsed := maxi(now-_last_minute,0)
	_last_minute = now
	if chopping and tree != null and locations.in_range(tree,runtime.view.get_sim_position()): tree.add_work(StringName(runtime.data.id),elapsed)
	elif kind==&"PLANT": work_minutes += elapsed
func _minute(now: int) -> void:
	if kind.is_empty(): return
	if not _context_valid() or (kind==&"CHOP" and not _valid()):
		abort()
		return
	_accrue(now)
	if chopping and tree.state==TreeData.State.DEPLETED:
		var completed = tree
		complete_tree.call(completed)
		runtime.data.add_skill_xp(Skill.Type.GATHERING,1)
		_finish()
	elif kind==&"PLANT" and runtime.data.activity==Activity.Type.WORKING and work_minutes>=Balance.TREE_PLANTING_MINUTES:
		world.forestry_area.complete(runtime.data.id,hut)
		_finish()
func _cleanup() -> RefCounted:
	_available_task = {}
	_cleaning = true
	var old = _intent
	_intent = null
	if tree != null: tree.release(StringName(runtime.data.id))
	if world != null: world.forestry_area.release(runtime.data.id)
	tree = null
	hut = null
	committed_context = null
	kind = &""
	chopping = false
	work_minutes = 0
	_interrupt_pending = false
	_cleaning = false
	return old
func _finish() -> void:
	var old = _cleanup()
	if old != null and runtime.intents.current_intent==old: runtime.intents.clear_completed(old)
func abort(reconsider: bool = true) -> void:
	if _mutating:
		_interrupt_pending = true
		return
	if _cleaning or kind.is_empty(): return
	_accrue(clock.total_minutes)
	var old = _cleanup()
	if old != null and runtime.intents.current_intent==old: runtime.intents.cancel_current(old)
	if reconsider: runtime.decision.call_deferred("request_decision","lumberjack_aborted")
func _changed(intent: RefCounted) -> void:
	if _intent != null and intent != _intent: abort(false)
func _forced(_previous: RefCounted) -> void: abort(false)
func _phase(phase: String) -> void:
	if phase != "День": abort() # Only CHOP/PLANT are owned here; hauls finish in HaulExecutor.
func _exit_tree() -> void: abort(false)
