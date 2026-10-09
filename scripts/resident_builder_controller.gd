extends Node
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
var source: Instance
var phase := Phase.NONE
var work_minutes := 0
var _last_work_minute := 0
var _resource: ResourceType.Type = ResourceType.Type.WOOD
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

func setup(data: RefCounted, clock: Node, locations: RefCounted, buildings: Array, intents: Node, decision: Node) -> void:
	_data = data
	_clock = clock
	_locations = locations
	_buildings = buildings
	_intents = intents
	_decision = decision
	intents.forced_interrupt.connect(_on_forced_interrupt)
	intents.intent_changed.connect(_on_intent_changed)
	intents.intent_arrived.connect(_on_arrival)
	clock.minute_changed.connect(_on_minute)
	clock.phase_changed.connect(_on_phase)
	for building in buildings: register_building(building)

func register_building(building: Instance) -> void:
	if not building.construction_changed.is_connected(_on_world_changed): building.construction_changed.connect(_on_world_changed)
	if not building.resources.availability_changed.is_connected(_on_resource_changed): building.resources.availability_changed.connect(_on_resource_changed)
	_on_world_changed()

func unregister_building(building: Instance) -> void:
	# World registry removes the entity before notifying its workers.
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
		if not building.is_built() or building.resources.get_available_amount(resource) < 1: continue
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
		var available_source := nearest_source(resource, current_position)
		if available_source != null: return {"resource": resource, "source": available_source}
	return {}

func _eligible(candidate: Instance) -> bool:
	return not candidate.is_built() and candidate.has_free_builder_slot() and _locations.get_position(candidate.id) is Vector2 and (candidate.are_construction_materials_complete() or not _material_trip(candidate).is_empty())

func best_site() -> Instance:
	var current_position: Variant = _position()
	if not current_position is Vector2: return null
	var best: Instance = null
	var score := -INF
	for candidate in _buildings:
		if not _eligible(candidate): continue
		var value := site_priority(candidate, current_position)
		if best == null or value > score or (value == score and String(candidate.id) < String(best.id)):
			best = candidate
			score = value
	return best

func has_work() -> bool:
	if _data.profession != Profession.Type.BUILDER or phase != Phase.NONE or _data.inventory.amount != 0: return false
	# Missing sources are reconsidered after world events, not idle retry intervals.
	if _availability_dirty:
		_potential_work = best_site() != null
		_availability_dirty = false
	return _potential_work

func request_work() -> bool:
	if _clock.get_phase() != "День" or not has_work() or _intents.has_current_action(): return false
	site = best_site()
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
	source = trip.source
	_resource = trip.resource
	_mutating = true
	_source_reserved = source.resources.reserve_out(_resource, 1)
	_site_reserved = _source_reserved and site.reserve_construction_material(_resource, 1)
	_mutating = false
	if _interrupt_pending:
		_interrupt_pending = false
		abort("прерывание при резервировании", false)
		return false
	if not _site_reserved:
		abort("не удалось зарезервировать материалы")
		return false
	phase = Phase.GOING_TO_SOURCE
	return _move(&"builder_source", _locations.get_position(source.id))

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
	if not current is Vector2 or current.distance_to(point) > 8.0:
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

func _move(reason: StringName, target: Vector2) -> bool:
	return _set_task_intent(Intent.new(Intent.Type.MOVE_TO, reason, target, Balance.WORK_PRIORITY, false))

func _set_task_intent(next: Intent) -> bool:
	var previous: Intent = _intent
	_intent = next
	var accepted: bool = _intents.submit(_intent) if previous == null else _intents.continue_intent(previous, _intent)
	if not accepted: abort("маршрут не принят")
	return accepted

func _on_arrival(intent: Intent) -> void:
	if intent != _intent: return
	if not _valid_site():
		abort("стройка недоступна при прибытии")
		return
	if phase == Phase.GOING_TO_SOURCE:
		if source not in _buildings or not source.is_built() or not _locations.get_position(source.id) is Vector2:
			abort("источник недоступен")
			return
		_mutating = true
		var taken: bool = source.resources.take_reserved(_resource, 1)
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
		if logger != null: logger.info(EventLog.BUILDING, "%s: забрал 1 %s — %s" % [_data.resident_name, ResourceType.Type.keys()[_resource], source.display_name])
		phase = Phase.CARRYING_TO_SITE
		_move(&"builder_delivery", _locations.get_position(site.id))
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
	if phase != Phase.BUILDING: return
	var point: Variant = _position()
	var action_point: Variant = _locations.get_position(site.id) if site != null else null
	if point is Vector2 and action_point is Vector2 and point.distance_to(action_point) <= 8.0 and _data.activity == Activity.Type.WORKING:
		work_minutes += maxi(now - _last_work_minute, 0)
	_last_work_minute = now

func _on_minute(now: int) -> void:
	if phase == Phase.NONE or _is_waiting(): return
	if not _valid_site():
		abort("стройка удалена или завершена")
		return
	if phase == Phase.GOING_TO_SOURCE and (source not in _buildings or not source.is_built()):
		abort("источник удалён")
		return
	_accrue_work(now)
	if phase == Phase.BUILDING and work_minutes >= Balance.BUILDER_WORK_CYCLE_MINUTES:
		_finish_task("завершил строительный цикл", true)

func _flush_work() -> void:
	_accrue_work(_clock.total_minutes)
	if site != null and work_minutes > 0:
		var contribution := work_minutes
		work_minutes = 0
		site.add_construction_work(contribution)
		if logger != null:
			var message := "завершил строительный цикл" if contribution >= Balance.BUILDER_WORK_CYCLE_MINUTES else "прервал строительный цикл, сохранён вклад"
			logger.info(EventLog.BUILDING, "%s: %s (+%d мин)" % [_data.resident_name, message, contribution])
		if site.can_complete_construction():
			site.complete_construction()
			if logger != null: logger.info(EventLog.BUILDING, "%s: строительство завершено" % site.display_name)

func _cleanup(reason: String) -> Intent:
	_availability_dirty = true
	_exiting = true
	var old: Intent = _intent
	_intent = null
	_flush_work()
	if _source_reserved and source != null: source.resources.release_out(_resource, 1)
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
	if phase_name != "День" and phase in [Phase.BUILDING, Phase.GOING_TO_SITE, Phase.GOING_TO_SOURCE, Phase.GOING_TO_WAIT, Phase.WAITING_FOR_MATERIALS]:
		abort("конец рабочего времени")
	# A carried unit is delivered safely before leaving work.

func _on_resource_changed(resource: ResourceType.Type, _amount: int) -> void:
	if resource == ResourceType.Type.WOOD: _on_world_changed()
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
