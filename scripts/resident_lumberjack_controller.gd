extends Node
## Ordinary workplace WORK: collect, chop, plant, then shared container haul export.
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
const Source = preload("res://scripts/resource_source_ref.gd")
var source_ref: Source
var drop: RefCounted
var target: Vector2
var chopping := false
var kind := &""
var work_minutes := 0
var _intent: RefCounted
var _last_minute := 0
var _cleaning := false
var _ground_reserved := false
var _incoming := false
var _mutating := false
var _interrupt_pending := false
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
	return not locations.navigation.find_path(Coordinates.to_world(from_position),Coordinates.to_world(to_position)).is_empty()
func best_target() -> Dictionary:
	var workplace = _current_hut()
	if workplace == null: return {}
	var best: Dictionary = {}
	var distance := INF
	var origin: Vector2 = runtime.view.get_sim_position()
	for candidate in trees:
		if candidate.state != TreeData.State.STANDING or not candidate.reservation_owner_id.is_empty() or not world.forestry_area.inside(workplace,candidate.position): continue
		if workplace.resources.get_available_free_capacity(Resources.Type.LOG) < candidate.yield_amount: continue
		var point: Variant = locations.resolve(candidate,origin)
		if not point is Vector2: continue
		var value := origin.distance_squared_to(candidate.position)
		if best.is_empty() or value < distance or (value == distance and String(candidate.id) < String(best.tree.id)):
			best = {"kind":&"CHOP","tree":candidate,"point":point}
			distance = value
	return best
func best_task() -> Dictionary:
	var workplace = _current_hut()
	if workplace == null or not is_instance_valid(runtime.view): return {}
	var origin: Vector2 = runtime.view.get_sim_position()
	var home: Vector2 = world.world_locations.get_position(workplace.id)
	var best: Dictionary = {}
	var distance := INF
	if workplace.resources.get_available_free_capacity(Resources.Type.LOG) >= 1:
		for reference in world.logistics.sources.find(Resources.Type.LOG,origin,home,workplace.id):
			if reference.kind!=Source.Kind.GROUND: continue
			var candidate = world.logistics.sources.resolve(reference)
			if not world.forestry_area.inside(workplace,candidate.world_position): continue
			best = {"kind":&"COLLECT","drop":candidate,"reference":reference,"point":candidate.world_position}
			break
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
func has_work() -> bool:
	return clock.get_phase()=="День" and not best_task().is_empty()
func request_work() -> bool:
	if clock.get_phase() != "День" or runtime.intents.has_current_action() or runtime.data.inventory.amount != 0: return false
	var candidate := best_task()
	if candidate.is_empty(): return false
	if candidate.kind == &"EXPORT":
		var job = world.logistics.claim_own_export(runtime.data.id,candidate.destination)
		if job == null: return false
		if world.logistics.start_claimed_job(job,runtime.data.id): return true
		world.logistics.cancel_job(job)
		return false
	hut = _current_hut()
	kind = candidate.kind
	target = candidate.point
	_mutating = true
	var claimed := false
	if kind==&"CHOP":
		tree = candidate.tree
		claimed = tree.claim(StringName(runtime.data.id))
	elif kind==&"COLLECT":
		drop = candidate.drop
		source_ref = candidate.reference
		_ground_reserved = world.logistics.sources.reserve(source_ref,Resources.Type.LOG,StringName(runtime.data.id))
		_incoming = _ground_reserved and hut.resources.reserve_in(Resources.Type.LOG,1)
		claimed = _incoming
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
	return &"chop_tree" if kind==&"CHOP" else (&"collect_log" if kind==&"COLLECT" else &"plant_tree")
func _hut_valid() -> bool:
	return hut != null and hut in world.buildings and hut.is_built() and world.world_locations.get_position(hut.id) is Vector2
func _arrived(intent: RefCounted) -> void:
	if intent != _intent: return
	if not _hut_valid() or runtime.view.get_sim_position().distance_to(target)>8.0:
		abort()
		return
	if kind == &"COLLECT":
		_mutating = true
		var taken: bool = world.logistics.sources.pickup(source_ref,Resources.Type.LOG,StringName(runtime.data.id))
		if taken:
			_ground_reserved = false
			runtime.data.inventory.put(Resources.Type.LOG,1)
		_mutating = false
		if not taken or _interrupt_pending:
			abort(false)
			return
		if logger != null: logger.info(EventLog.LOGISTICS,"%s: подобрал 1 LOG" % runtime.data.resident_name)
		kind = &"CARRYING"
		target = world.world_locations.get_position(hut.id)
		_intent = Intent.new(Intent.Type.MOVE_TO,&"lumberjack_delivery",target,Balance.WORK_PRIORITY,false)
		if not runtime.intents.continue_intent(intent,_intent): abort()
	elif kind==&"CARRYING":
		_mutating = true
		runtime.data.inventory.clear()
		var delivered: bool = hut.resources.add_reserved(Resources.Type.LOG,1)
		if delivered: _incoming = false
		else: runtime.data.inventory.put(Resources.Type.LOG,1)
		_mutating = false
		if delivered:
			if logger != null: logger.info(EventLog.LOGISTICS,"%s: доставил 1 LOG — %s" % [runtime.data.resident_name,hut.display_name])
			_finish()
		else: abort()
	else:
		if kind==&"CHOP" and not _valid():
			abort()
			return
		chopping = kind==&"CHOP"
		work_minutes = 0
		_last_minute = clock.total_minutes
		runtime.data.activity = Activity.Type.WORKING
		if logger != null: logger.info(EventLog.AI,"%s: начал %s" % [runtime.data.resident_name,"рубку" if chopping else "посадку"])
func _valid() -> bool:
	return tree != null and tree in trees and tree.state==TreeData.State.STANDING and tree.reservation_owner_id==StringName(runtime.data.id) and locations.is_available(target)
func _accrue(now: int) -> void:
	if runtime.data.activity != Activity.Type.WORKING or not is_instance_valid(runtime.view) or runtime.view.get_sim_position().distance_to(target)>8: return
	var elapsed := maxi(now-_last_minute,0)
	_last_minute = now
	if chopping and tree != null: tree.add_work(StringName(runtime.data.id),elapsed)
	elif kind==&"PLANT": work_minutes += elapsed
func _minute(now: int) -> void:
	if kind.is_empty(): return
	if not _hut_valid() or (kind==&"CHOP" and not _valid()) or (kind==&"COLLECT" and drop not in world.ground_resources.drops):
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
	_cleaning = true
	var old = _intent
	_intent = null
	if tree != null: tree.release(StringName(runtime.data.id))
	if _ground_reserved: world.logistics.sources.release(source_ref,Resources.Type.LOG,StringName(runtime.data.id))
	if _incoming and hut != null: hut.resources.release_in(Resources.Type.LOG,1)
	if world != null: world.forestry_area.release(runtime.data.id)
	if runtime.data.inventory.amount>0:
		var resource: Resources.Type = runtime.data.inventory.resource_type
		var amount: int = runtime.data.inventory.amount
		runtime.data.inventory.clear()
		world.ground_resources.create_drop(resource,amount,runtime.view.get_sim_position())
	tree = null
	hut = null
	drop = null
	source_ref = null
	kind = &""
	chopping = false
	work_minutes = 0
	_ground_reserved = false
	_incoming = false
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
	if phase != "День": abort()
func _exit_tree() -> void: abort(false)
