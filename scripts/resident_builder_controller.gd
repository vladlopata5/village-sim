extends Node
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
## Resident-owned construction workflow. Site score selects a task only after WORK wins.
const Instance = preload("res://scripts/building_instance.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Skill = preload("res://scripts/skill_type.gd")
const EventLog = preload("res://scripts/game_logger.gd")
enum Phase { NONE, GOING_TO_SOURCE, CARRYING_TO_SITE, GOING_TO_SITE, BUILDING, GOING_TO_WAIT, WAITING_FOR_MATERIALS }
signal work_cycle_started(building_id: StringName)
signal cargo_dropped(resource: ResourceType.Type, amount: int)
var logger: EventLog
var position_provider: Callable
var site: Instance
const Source = preload("res://scripts/resource_source_ref.gd")
var sources = preload("res://scripts/resource_sources.gd").new()
var _owns_sources := true
var source_ref: Source
var source: Instance
var phase := Phase.NONE
var work_minutes := 0
var _last_work_minute := 0
var _resource: ResourceType.Type
var _source_reserved := false
var _site_reserved := false
var _intent: Intent
var _data: RefCounted
var _clock: Node
var _locations: RefCounted
var _buildings: Array
var _intents: Node
var _decision: Node
var _exiting := false
var _mutating := false
var _interrupt_pending := false
var _had_work := false
var _availability_dirty := true
var _potential_work := false
var _waiting_resume_queued := false
var source_search_count := 0
# Optional navigation query providers; isolated domain fixtures use generic source queries.
var material_planner: Callable
var material_lower_bound: Callable
var material_path_current: Callable
var _work_offer: Instance
var _work_origin: Variant = null
var _search_identity: Array = []
var _trip_offer: Dictionary = {}
var _offer_site: Instance
var _offer_source: RefCounted
var _delivery_path: Dictionary = {}
var handling = preload("res://scripts/resource_handling.gd").new()

func setup(data: RefCounted, clock: Node, locations: RefCounted, buildings: Array, intents: Node, decision: Node) -> void:
	_data = data
	_clock = clock
	_locations = locations
	_buildings = buildings
	sources.locations = locations
	_intents = intents
	_decision = decision
	intents.forced_interrupt.connect(_on_forced_interrupt)
	intents.intent_changed.connect(_on_intent_changed)
	intents.intent_arrived.connect(_on_arrival)
	clock.minute_changed.connect(_on_minute)
	clock.phase_changed.connect(_on_phase)
	for building in buildings: register_building(building)

func bind_sources(provider: RefCounted) -> void:
	_owns_sources = false
	sources = provider
	if not sources.changed.is_connected(_on_sources_changed): sources.changed.connect(_on_sources_changed)
	_on_world_changed()
func _on_sources_changed() -> void:
	if phase==Phase.GOING_TO_SOURCE and not _mutating and not sources.reserved(source_ref,_resource,_source_owner()): abort("источник недоступен")
	_on_world_changed()
func _source_owner() -> StringName: return StringName("builder:"+_data.id)
func register_building(building: Instance) -> void:
	if _owns_sources: sources.buildings[building.id] = building
	if not building.construction_changed.is_connected(_on_world_changed): building.construction_changed.connect(_on_world_changed)
	if not building.resources.availability_changed.is_connected(_on_resource_changed): building.resources.availability_changed.connect(_on_resource_changed)
	_on_world_changed()

func unregister_building(building: Instance) -> void:
	# World registry removes the entity before notifying its workers.
	if building not in _buildings: sources.buildings.erase(building.id)
	if site == building: abort("стройка отменена")
	if building.construction_changed.is_connected(_on_world_changed): building.construction_changed.disconnect(_on_world_changed)
	if building.resources.availability_changed.is_connected(_on_resource_changed): building.resources.availability_changed.disconnect(_on_resource_changed)
	_on_world_changed()

func site_priority(candidate: Instance, from_position: Vector2) -> float:
	var distance := from_position.distance_to(candidate.position) / Balance.BUILDER_DISTANCE_SCALE
	return candidate.get_construction_material_ratio() * Balance.BUILDER_MATERIAL_PROGRESS_MAX + candidate.get_construction_progress_ratio() * Balance.BUILDER_CONSTRUCTION_PROGRESS_MAX + candidate.active_builder_ids.size() * Balance.BUILDER_ACTIVE_WORKER_BONUS - distance * distance * Balance.BUILDER_DISTANCE_WEIGHT

func _position() -> Variant:
	return position_provider.call(_data.id) if position_provider.is_valid() else null

func nearest_source(resource: ResourceType.Type, from_position: Vector2) -> Instance:
	source_search_count += 1
	var best: Instance = null
	var best_distance := INF
	for building in _buildings:
		if not building.is_built() or not building.definition.allows_external_export(resource) or building.resources.get_available_amount(resource) < 1: continue
		var point: Variant = _locations.get_position(building.id)
		if not point is Vector2: continue
		var distance: float = from_position.distance_squared_to(point)
		if best == null or distance < best_distance or (distance == best_distance and String(building.id) < String(best.id)):
			best = building
			best_distance = distance
	return best

func _material_trip(candidate: Instance) -> Dictionary:
	var current_position: Variant = _position()
	if not current_position is Vector2: return {}
	for resource in candidate.definition.construction_requirements:
		if candidate.get_uncovered_construction_amount(resource) <= 0: continue
		var end: Variant = _locations.get_position(candidate.id)
		if not end is Vector2: continue
		if material_planner.is_valid():
			if _trip_offer_valid(candidate,resource,current_position,end): return _trip_offer
			source_search_count += 1
			var trip: Dictionary = sources.find_construction_trip(resource,current_position,end,candidate.id,material_planner,material_lower_bound,sources.CONSTRUCTION_SEARCH_SLACK,candidate)
			if not trip.is_empty():
				trip["resource"] = resource
				trip["search_identity"] = sources.GroundAreas.identity(current_position,candidate)
				_trip_offer = trip
				_offer_site = candidate
				_offer_source = sources.resolve(trip.reference)
				return trip
			continue
		source_search_count += 1
		var matches: Array = sources.find(resource,current_position,end,candidate.id,candidate)
		if not matches.is_empty(): return {"resource":resource,"reference":matches[0]}
	return {}

func _trip_offer_valid(candidate: Instance, resource: int, origin: Vector2, destination: Vector2) -> bool:
	if _trip_offer.is_empty() or _offer_site != candidate or candidate not in _buildings or candidate.is_built(): return false
	if _trip_offer.resource != resource or candidate.get_uncovered_construction_amount(resource) <= 0: return false
	if _trip_offer.get("search_identity",[]) != sources.GroundAreas.identity(origin,candidate): return false
	var reference: Source = _trip_offer.reference
	if sources.resolve(reference) != _offer_source or not sources.available(reference,resource) or not sources.ground_allowed(reference,origin,candidate): return false
	if _trip_offer.origin != origin or _trip_offer.destination != destination or _trip_offer.access != sources.point(reference): return false
	return material_path_current.call(_trip_offer.source_path) and material_path_current.call(_trip_offer.delivery_path)
func on_navigation_changed(_revision: int) -> void:
	_on_world_changed() # Also invalidates negative availability after a blocker changes.

func _eligible(candidate: Instance) -> bool:
	return not candidate.is_built() and candidate.has_free_builder_slot() and _locations.get_position(candidate.id) is Vector2 and (candidate.are_construction_materials_complete() or not _material_trip(candidate).is_empty())

func best_site() -> Instance:
	var current_position: Variant = _position()
	_work_offer = null
	_work_origin = current_position
	if not current_position is Vector2: return null
	var ranked: Array[Dictionary] = []
	for candidate in _buildings:
		if candidate.is_built() or not candidate.has_free_builder_slot(): continue
		ranked.append({"site":candidate,"score":site_priority(candidate,current_position)})
	ranked.sort_custom(func(a,b): return a.score > b.score or (a.score == b.score and String(a.site.id) < String(b.site.id)))
	for candidate in ranked:
		if _eligible(candidate.site):
			_work_offer = candidate.site
			return _work_offer
	return null

func has_work() -> bool:
	if _data.profession != Profession.Type.BUILDER or phase != Phase.NONE or _data.inventory.amount != 0: return false
	# Cheap context at existing decision probes, never a resource scan on movement ticks.
	var current_position: Variant = _position()
	var current_identity: Array = [current_position,sources.revision]
	for candidate in _buildings:
		if not candidate.is_built(): current_identity.append(sources.GroundAreas.identity(current_position,candidate))
	if current_identity != _search_identity:
		_search_identity = current_identity
		_availability_dirty = true
	# Missing sources are reconsidered after world events, not idle retry intervals.
	if _availability_dirty:
		_potential_work = best_site() != null
		_availability_dirty = false
	return _potential_work

func request_work() -> bool:
	if _clock.get_phase() != "День" or not has_work() or _intents.has_current_action(): return false
	# Fresh resource/identity checks even if availability and execution share geometry.
	site = _work_offer if material_planner.is_valid() and _work_offer != null and _work_offer in _buildings and _work_offer.has_free_builder_slot() and _work_origin == _position() and _eligible(_work_offer) else best_site()
	if site == null: return false
	_mutating = true
	var claimed: bool = site.claim_builder_slot(_data.id)
	_mutating = false
	if _interrupt_pending:
		_interrupt_pending = false
		abort("прерывание при занятии слота", false)
		return false
	if not claimed:
		site = null
		return false
	if logger != null:
		logger.info(EventLog.AI, "%s: выбрал стройку — %s" % [_data.resident_name, site.display_name])
		logger.info(EventLog.BUILDING, "%s: занял место строителя — %s" % [_data.resident_name, site.id])
	return _continue_task()

func _valid_site() -> bool:
	return site != null and site in _buildings and not site.is_built() and _data.id in site.active_builder_ids and _locations.get_position(site.id) is Vector2

func _continue_task() -> bool:
	if not _valid_site():
		abort("стройка недоступна")
		return false
	if _data.profession != Profession.Type.BUILDER or _clock.get_phase() != "День":
		_finish_task("смена профессии или завершение рабочего времени")
		return false
	if site.are_construction_materials_complete():
		phase = Phase.GOING_TO_SITE
		return _move(&"builder_site", _locations.get_position(site.id))
	if _materials_incoming(): return _wait_for_materials()
	var trip := _material_trip(site)
	if trip.is_empty():
		# An uncovered deficit without a source cannot keep a task waiting.
		_finish_task("нет доступных материалов")
		return false
	source_ref = trip.reference
	source = sources.resolve(source_ref) if source_ref.kind==Source.Kind.CONTAINER else null
	_resource = trip.resource
	_mutating = true
	_source_reserved = sources.reserve(source_ref,_resource,_source_owner())
	_site_reserved = _source_reserved and site.reserve_construction_material(_resource, 1)
	_mutating = false
	if _interrupt_pending:
		_interrupt_pending = false
		abort("прерывание при резервировании", false)
		return false
	# Reentrant reserve callbacks may change an UNACCEPTED proposal's search context.
	if not _site_reserved or not sources.reserved(source_ref,_resource,_source_owner()) or not _valid_site() or not sources.ground_allowed(source_ref,_position(),site):
		abort("не удалось зарезервировать материалы")
		return false
	phase = Phase.GOING_TO_SOURCE
	_delivery_path = trip.get("delivery_path",{})
	_trip_offer = {}
	_offer_site = null
	_offer_source = null
	return _move(&"builder_source", sources.point(source_ref),trip.get("source_path",{}))

func _materials_incoming() -> bool:
	for resource in site.definition.construction_requirements:
		if site.get_uncovered_construction_amount(resource) > 0: return false
	return true

func _is_waiting() -> bool:
	return phase in [Phase.GOING_TO_WAIT, Phase.WAITING_FOR_MATERIALS]

func _wait_for_materials() -> bool:
	var was_waiting := _is_waiting()
	if not was_waiting and logger != null:
		var counts: Array[String] = []
		for resource in site.definition.construction_requirements:
			counts.append("%s %d/%d, в пути %d" % [ResourceType.Type.keys()[resource], site.get_delivered_amount(resource), site.get_required_amount(resource), site.get_construction_reserved_in(resource)])
		logger.info(EventLog.BUILDING, "%s: ждёт материалы — %s (%s)" % [_data.resident_name, site.id, "; ".join(counts)])
	var point: Vector2 = _locations.get_position(site.id)
	var current: Variant = _position()
	if not current is Vector2 or not (_locations.at_action(_data.id,site.id,Purpose.CONSTRUCTION,current,8.0) if _locations.has_method("at_action") else current.distance_to(point)<=8.0):
		if phase == Phase.GOING_TO_WAIT: return true
		phase = Phase.GOING_TO_WAIT
		return _move(&"builder_wait_arrival", point)
	if phase == Phase.WAITING_FOR_MATERIALS: return true
	phase = Phase.WAITING_FOR_MATERIALS
	# A stationary, interruptible action retains assignment without an AI retry loop.
	return _set_task_intent(Intent.new(Intent.Type.NONE, &"builder_wait_materials", point, Balance.WORK_PRIORITY, true))

func _resume_waiting() -> void:
	_waiting_resume_queued = false
	if not _is_waiting() or not _valid_site(): return
	if site.are_construction_materials_complete():
		if logger != null: logger.info(EventLog.BUILDING, "%s: материалы доставлены — продолжает строительство %s" % [_data.resident_name, site.id])
	elif _materials_incoming():
		return # Still covered: no new reservation or source search.
	elif logger != null:
		logger.info(EventLog.BUILDING, "%s: ожидаемая поставка отменена — пересматривает работу %s" % [_data.resident_name, site.id])
	_continue_task()

func _move(reason: StringName, target: Vector2, prepared: Dictionary = {}) -> bool:
	var next := Intent.new(Intent.Type.MOVE_TO,reason,target,Balance.WORK_PRIORITY,false)
	next.prepared_path = prepared
	return _set_task_intent(next)

func _set_task_intent(next: Intent) -> bool:
	var previous: Intent = _intent
	_intent = next
	if _locations.has_method("configure_intent"):
		if phase==Phase.GOING_TO_SOURCE:
			if source_ref!=null and source_ref.kind==Source.Kind.CONTAINER: _locations.configure_intent(_intent,source_ref.id,Purpose.COURIER,_data.id)
		elif site!=null: _locations.configure_intent(_intent,site.id,Purpose.COURIER if phase==Phase.CARRYING_TO_SITE else Purpose.CONSTRUCTION,_data.id)
	var accepted: bool = _intents.submit(_intent) if previous == null else _intents.continue_intent(previous, _intent)
	if not accepted: abort("маршрут не принят")
	return accepted

func _on_arrival(intent: Intent) -> void:
	if intent != _intent or handling.is_active(): return
	if phase in [Phase.GOING_TO_SOURCE,Phase.CARRYING_TO_SITE]:
		if not _valid_site():
			abort("стройка недоступна")
			return
		intent.resource_handling = &"loading" if phase==Phase.GOING_TO_SOURCE else &"unloading"
		handling.start(intent.resource_handling,_clock.total_minutes,Balance.RESOURCE_LOADING_MINUTES if phase==Phase.GOING_TO_SOURCE else Balance.RESOURCE_UNLOADING_MINUTES)
		_data.activity = Activity.Type.HAULING
		if logger != null: logger.info(EventLog.LOGISTICS, "%s: %s (%d игровых минут)" % [_data.resident_name,"погрузка" if intent.resource_handling==&"loading" else "разгрузка",Balance.RESOURCE_LOADING_MINUTES if phase==Phase.GOING_TO_SOURCE else Balance.RESOURCE_UNLOADING_MINUTES])
		return
	_complete_arrival(intent)

func _complete_arrival(intent: Intent) -> void:
	if intent != _intent: return
	if not _valid_site():
		abort("стройка недоступна при прибытии")
		return
	if phase == Phase.GOING_TO_SOURCE:
		if not sources.reserved(source_ref,_resource,_source_owner()) or not sources.point(source_ref) is Vector2:
			abort("источник недоступен")
			return
		_mutating = true
		var taken: bool = sources.pickup(source_ref,_resource,_source_owner())
		if taken:
			_source_reserved = false
			_data.inventory.put(_resource, 1)
		_mutating = false
		if _interrupt_pending:
			_interrupt_pending = false
			abort("прерывание при подборе", false)
			return
		if not taken:
			abort("не удалось получить материал")
			return
		if logger != null: logger.info(EventLog.BUILDING, "%s: забрал 1 %s — %s" % [_data.resident_name, ResourceType.Type.keys()[_resource], sources.label(source_ref)])
		phase = Phase.CARRYING_TO_SITE
		var prepared := _delivery_path
		_delivery_path = {}
		_move(&"builder_delivery", _locations.get_position(site.id),prepared)
	elif phase == Phase.CARRYING_TO_SITE:
		_mutating = true
		_data.inventory.clear()
		var delivered: bool = site.deliver_reserved_construction_material(_resource, 1)
		if delivered: _site_reserved = false
		else: _data.inventory.put(_resource, 1)
		_mutating = false
		if _interrupt_pending:
			_interrupt_pending = false
			abort("прерывание при доставке", false)
			return
		if not delivered:
			abort("доставка невозможна")
			return
		if logger != null: logger.info(EventLog.BUILDING, "%s: доставил 1 %s — %s" % [_data.resident_name, ResourceType.Type.keys()[_resource], site.display_name])
		source = null
		_continue_task()
	elif phase == Phase.GOING_TO_WAIT:
		_continue_task()
	elif phase == Phase.GOING_TO_SITE:
		if not site.are_construction_materials_complete():
			_continue_task()
			return
		phase = Phase.BUILDING
		work_minutes = 0
		_last_work_minute = _clock.total_minutes
		_data.activity = Activity.Type.WORKING
		work_cycle_started.emit(site.id)
		if logger != null: logger.info(EventLog.BUILDING, "%s: начал строительный цикл (%d мин)" % [_data.resident_name, Balance.BUILDER_WORK_CYCLE_MINUTES])

func _accrue_work(now: int) -> void:
	if phase != Phase.BUILDING or not _valid_site(): return
	var previous := _last_work_minute
	_last_work_minute = now # Advance before synchronous construction callbacks.
	var point: Variant = _position()
	var action_point: Variant = _locations.get_position(site.id)
	if not point is Vector2 or not action_point is Vector2 or not (_locations.at_action(_data.id,site.id,Purpose.CONSTRUCTION,point,8.0) if _locations.has_method("at_action") else point.distance_to(action_point)<=8.0) or _data.activity!=Activity.Type.WORKING or _intents.current_intent!=_intent or not site.are_construction_materials_complete(): return
	# The interval ending at 17:00 still contains the final working minute.
	var minute_of_day := posmod(previous,1440)
	if minute_of_day<420 or minute_of_day>=1020: return
	var elapsed := mini(maxi(now-previous,0),1020-minute_of_day)
	elapsed = mini(elapsed,Balance.BUILDER_WORK_CYCLE_MINUTES-work_minutes)
	elapsed = mini(elapsed,site.definition.construction_work_required-site.construction_progress)
	if elapsed<=0: return
	var worked_site := site
	work_minutes += elapsed # Action timing only; already applied work is never buffered.
	_mutating = true
	worked_site.add_construction_work(elapsed)
	var completed := worked_site.can_complete_construction() and worked_site.complete_construction()
	_mutating = false
	if completed:
		if logger!=null: logger.info(EventLog.BUILDING,"%s: строительство завершено" % worked_site.display_name)
		_interrupt_pending = false
		_finish_task("строительство завершено",work_minutes>=Balance.BUILDER_WORK_CYCLE_MINUTES)
	elif _interrupt_pending:
		_interrupt_pending = false
		abort("прерывание во время work update",false)
	elif work_minutes>=Balance.BUILDER_WORK_CYCLE_MINUTES:
		_finish_task("завершил строительный цикл",true)

func _on_minute(now: int) -> void:
	if phase == Phase.NONE or _is_waiting(): return
	if not _valid_site():
		abort("стройка удалена или завершена")
		return
	if phase in [Phase.GOING_TO_SOURCE,Phase.CARRYING_TO_SITE] and (not _site_reserved or site.get_construction_reserved_in(_resource)<1):
		abort("бронь материалов недоступна")
		return
	if phase == Phase.GOING_TO_SOURCE and not sources.reserved(source_ref,_resource,_source_owner()):
		abort("источник удалён")
		return
	if handling.is_active() and handling.advance(now):
		var arrived := _intent
		_complete_arrival(arrived)
		arrived.resource_handling = &""
	_accrue_work(now)

func _flush_work() -> void:
	# All contribution is already in BuildingInstance. Cleanup cannot apply it twice.
	if work_minutes>0 and logger!=null:
		var message := "завершил строительный цикл" if work_minutes>=Balance.BUILDER_WORK_CYCLE_MINUTES else "прервал строительный цикл, сохранён вклад"
		logger.info(EventLog.BUILDING,"%s: %s (%d мин уже начислено)" % [_data.resident_name,message,work_minutes])

func _cleanup(reason: String) -> Intent:
	_trip_offer = {}
	_work_offer = null
	_offer_site = null
	_offer_source = null
	_delivery_path = {}
	_availability_dirty = true
	_exiting = true
	var old: Intent = _intent
	handling.cancel()
	if old!=null: old.resource_handling=&""
	_intent = null
	_flush_work()
	if _source_reserved: sources.release(source_ref,_resource,_source_owner())
	if _site_reserved and site != null: site.release_construction_material(_resource, 1)
	_source_reserved = false
	_site_reserved = false
	if _data.inventory.amount > 0:
		var amount: int = _data.inventory.amount
		var resource: ResourceType.Type = _data.inventory.resource_type
		_data.inventory.clear()
		cargo_dropped.emit(resource, amount)
	if site != null: site.release_builder_slot(_data.id)
	site = null
	source = null
	source_ref = null
	phase = Phase.NONE
	work_minutes = 0
	_exiting = false
	if logger != null: logger.debug(EventLog.BUILDING, "%s: строительство cleanup — %s" % [_data.resident_name, reason])
	return old

func _finish_task(reason: String, completed_work_cycle: bool = false) -> void:
	var old := _cleanup(reason)
	if completed_work_cycle: _data.add_skill_xp(Skill.Type.CONSTRUCTION, 1)
	if old != null and _intents.current_intent == old: _intents.clear_completed(old)

func abort(reason: String, request_decision: bool = true) -> void:
	if phase == Phase.NONE and site == null: return
	var old := _cleanup(reason)
	if old != null and _intents.current_intent == old: _intents.cancel_current(old)
	if request_decision: _decision.call_deferred("request_decision", "builder_aborted")

func _on_forced_interrupt(_previous: Intent) -> void:
	if _mutating:
		_interrupt_pending = true
		return
	abort("forced / PlayerCommand", false)

func _on_intent_changed(intent: Intent) -> void:
	if _exiting or _intent == null or intent == _intent: return
	if _mutating: _interrupt_pending = true
	else: abort("смена намерения", false)

func on_profession_changed(resident_id: String) -> void:
	# Waiting carries no cargo/work cycle to finish; it is already a safe boundary.
	if resident_id == _data.id and _is_waiting() and _data.profession != Profession.Type.BUILDER:
		_finish_task("смена профессии во время ожидания")

func _on_phase(phase_name: String) -> void:
	if phase_name != "День" and phase in [Phase.BUILDING, Phase.GOING_TO_SITE, Phase.GOING_TO_WAIT, Phase.WAITING_FOR_MATERIALS]:
		abort("конец рабочего времени")
	# A carried unit is delivered safely before leaving work.

func _on_resource_changed(resource: ResourceType.Type, _amount: int) -> void:
	for candidate in _buildings:
		if not candidate.is_built() and candidate.definition.construction_requirements.has(resource):
			_on_world_changed()
			return
func _on_world_changed() -> void:
	_availability_dirty = true
	if _exiting or _mutating: return
	if site != null and phase != Phase.NONE and not _valid_site():
		abort("изменение доступности стройки")
	if _is_waiting() and not _waiting_resume_queued:
		# Coalesce synchronous reservation/delivery signals; never run inside a carrier mutation.
		_waiting_resume_queued = true
		call_deferred("_resume_waiting")
	var available := has_work()
	if available and not _had_work and _data.activity == Activity.Type.IDLE and not _intents.has_current_action():
		_decision.call_deferred("request_decision", "construction_available")
	_had_work = available

func _exit_tree() -> void:
	if site != null: _cleanup("удаление исполнителя")
