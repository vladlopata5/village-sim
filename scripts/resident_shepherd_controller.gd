extends Node
## One committed animal job; selection, navigation and resource storage stay shared.
const Animal=preload("res://scripts/animal_data.gd")
const Assignment=preload("res://scripts/resident_assignment.gd")
const Intent=preload("res://scripts/resident_intent.gd")
const Activity=preload("res://scripts/resident_activity.gd").Type
const Profession=preload("res://scripts/resident_profession.gd").Type
const Types=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Purpose=preload("res://scripts/building_slot_purpose.gd").Type
const Balance=preload("res://scripts/balance_config.gd")
enum Phase { NONE, APPROACH, CAPTURING, ESCORT, FINAL_APPROACH, ENTERING, SHEARING }
signal finished(identity: StringName, successful: bool, result: Dictionary)
var phase := Phase.NONE
var runtime: Node
var world: Node
var animal: Node3D
var building: RefCounted
var assignment: RefCounted
var batch: RefCounted
var pair: Node
var identity: StringName
var last_result: Dictionary={}
var _intent: RefCounted
var _serial := 0
var _last_minute := 0
var _progress := 0
var _attempts := 0
var _assignment_revision := 0
var _final_after_frame := -1
var _mutating := false
var _cancel_pending := false
var _ending := false
var _callbacks: Array=[]
func setup(actor: Node, owner_world: Node) -> void:
	runtime=actor;world=owner_world;set_physics_process(false)
	runtime.assignments.capture_error=capture_error
	runtime.assignments.capture_start=start_capture
	runtime.assignments.capture_cancel=cancel_assignment
	runtime.assignments.capture_refused=say
	runtime.intents.forced_interrupt.connect(_forced)
	runtime.intents.intent_changed.connect(_intent_changed)
	runtime.intents.intent_arrived.connect(_arrived)
	# Cleanup precedes an executor's potentially synchronous arrival.
	runtime.intents.intent_changed.disconnect(runtime.view.apply_intent)
	runtime.intents.intent_changed.connect(runtime.view.apply_intent)
	world.game_time.minute_changed.connect(_minute)
	world.player_control.work_assignment_changed.connect(_assignment_changed)
func workplace() -> RefCounted:
	if runtime==null or world==null or runtime.data.profession!=Profession.SHEPHERD: return null
	var place=world.player_control.get_building(runtime.data.work_location_id)
	return place if place!=null and place.type==Types.SHEPHERD_HUT and place.is_built() else null
func capture_error(target: StringName) -> String:
	if runtime.data.profession!=Profession.SHEPHERD: return "Я не пастух"
	var place=workplace()
	if place==null: return "Мне некуда привести овцу"
	var sheep: Node3D=world.get_animal_executor(target) if world.has_method("get_animal_executor") else null
	if sheep==null or sheep.data.status!=Animal.Status.WILD: return "Эту овцу уже забрали"
	if not sheep.data.operation_id.is_empty(): return "Эту овцу уже забрали"
	if place.animal_housing.available()==0: return "В хижине больше нет места"
	return ""
func say(message: String) -> void:
	if world!=null and world.social_feed!=null and not message.is_empty(): world.social_feed.add_message("%s: «%s»." % [runtime.data.resident_name,message])
func _connect(source: Signal, callback: Callable) -> void:
	source.connect(callback);_callbacks.append([source,callback])
func _begin(sheep: Node3D, place: RefCounted, task: RefCounted) -> bool:
	if phase!=Phase.NONE or runtime.intents.has_current_action() or runtime.data.inventory.amount>0 or runtime.intents.player_controlled: return false
	_serial+=1;identity=StringName("%s:animal_job:%d" % [runtime.data.id,_serial])
	animal=sheep;building=place;assignment=task;_progress=0;_attempts=0;_cancel_pending=false
	_assignment_revision=runtime.data.work_assignment_revision;last_result={};phase=Phase.APPROACH
	_connect(animal.tree_exiting,cancel.bind("Животное исчезло"))
	_connect(building.construction_changed,_building_changed)
	if not animal.data.claim_operation(identity):
		cancel("Эту овцу уже забрали");return false
	if phase==Phase.NONE: return false
	return true
func start_capture(task: RefCounted) -> bool:
	var error:=capture_error(task.target)
	if not error.is_empty():say(error);return false
	if not _begin(world.get_animal_executor(task.target),workplace(),task): return false
	_mutating=true
	var reserved: bool=building.animal_housing.reserve(identity,animal.data.id)
	_mutating=false
	if not reserved or _cancel_pending:cancel("В хижине больше нет места");return false
	return _approach()
func _candidate() -> Node3D:
	var place=workplace()
	if place==null or phase!=Phase.NONE or place.resources.get_available_free_capacity(R.WOOL)<1: return null
	if not world.has_method("get_animal_executor"): return null
	for data in place.animal_housing.animals():
		if data.wool_growth!=15 or not data.operation_id.is_empty(): continue
		var body: Node3D=world.get_animal_executor(data.id)
		if body==null or body.home==null or body.home.is_inside() or body.movement_owner!=null: continue
		if runtime.view.navigation.can_reach_point(runtime.view.global_position,body.global_position):return body
	return null
func has_work() -> bool: return _candidate()!=null
func request_work() -> bool:
	if world.game_time.get_phase()!="День":return false
	var sheep:=_candidate()
	if sheep==null or not _begin(sheep,workplace(),null):return false
	batch=preload("res://scripts/shearing_batch.gd").new(identity,building.resources)
	_connect(building.resources.reservations_changed,_reservation_changed)
	_connect(world.building_uses.slots_changed,_slots_changed)
	_mutating=true
	var reserved: bool=batch.prepare(runtime.data.id)
	_mutating=false
	if not reserved or _cancel_pending:cancel("Нет места для шерсти");return false
	return _approach()
func _valid() -> bool:
	if batch!=null and not batch.reserves_valid(): return false
	if phase==Phase.SHEARING and (not is_instance_valid(animal) or animal.home==null or not animal.home.owns_service(identity) or not world.building_uses.occupied_by(building.id,runtime.data.id,Purpose.WORKER)): return false
	return phase!=Phase.NONE and is_instance_valid(animal) and workplace()==building and runtime.data.work_assignment_revision==_assignment_revision and animal.data.operation_id==identity and (assignment!=null or (animal.home!=null and animal.home.building==building))
func keeps_shift_action() -> bool:
	return runtime!=null and _intent!=null and runtime.intents.current_intent==_intent and _valid()
func _stage(next: RefCounted) -> bool:
	var old:=_intent
	_intent=next # Publish before intent callbacks/executor arrival.
	var accepted: bool=runtime.intents.submit(next) if old==null else runtime.intents.continue_intent(old,next)
	if not accepted or phase==Phase.NONE:
		cancel("Действие прервано");return false
	return true
func _approach() -> bool:
	if not _valid():cancel("Мне некуда привести овцу");return false
	_attempts+=1
	if _attempts>8:cancel("Не могу догнать овцу");return false
	phase=Phase.APPROACH
	return _stage(Intent.new(Intent.Type.MOVE_TO,&"shepherd_approach",C.to_sim(animal.global_position),Balance.WORK_PRIORITY,false))
func _arrived(arrived: RefCounted) -> void:
	if arrived!=_intent or phase==Phase.NONE or _ending:return
	if not _valid():cancel("Работа стала недоступна");return
	if phase==Phase.APPROACH:
		if runtime.view.global_position.distance_to(animal.global_position)>1.2:
			_approach();return
		if not animal.claim_movement(self):cancel("Эту овцу уже забрали");return
		if assignment!=null:
			phase=Phase.CAPTURING;_last_minute=world.game_time.total_minutes
			if _stage(Intent.new(Intent.Type.NONE,&"shepherd_capture",Vector2.ZERO,Balance.WORK_PRIORITY,false)):runtime.data.activity=Activity.WORKING
		else:_escort()
	elif phase==Phase.ENTERING:
		if not animal.home.enter_service(identity):cancel("Место обслуживания недоступно");return
		_mutating=true
		var accepted: bool=batch.begin_shearing(runtime.data.id,runtime.decision.rng)
		_mutating=false
		if not accepted or _cancel_pending:cancel("Стрижка прервана");return
		phase=Phase.SHEARING;_last_minute=world.game_time.total_minutes
		runtime.data.activity=Activity.WORKING
func _escort() -> void:
	if not _valid():cancel("Работа стала недоступна");return
	var entrance: Variant=world.building_uses.entrance(building.id)
	if not entrance is Vector3:cancel("Мне некуда привести овцу");return
	# Handoff without resuming the autonomous behavior between movement owners.
	animal.release_movement(self,false)
	phase=Phase.ESCORT
	if not _stage(Intent.new(Intent.Type.MOVE_TO,&"shepherd_escort",C.to_sim(entrance),Balance.WORK_PRIORITY,false)):return
	pair=preload("res://scripts/world_3d/pair_escort_3d.gd").new();add_child(pair)
	pair.finished.connect(_escorted.bind(identity))
	if not pair.start(runtime.view,animal,world.game_time) and phase!=Phase.NONE:cancel("Не могу добраться до хижины")
func _escorted(_generation: int, outcome: StringName, expected: StringName) -> void:
	if identity!=expected or phase!=Phase.ESCORT or _ending:return
	if outcome!=&"completed" or not _valid():cancel("Сопровождение прервано");return
	if assignment!=null:
		_mutating=true
		var accepted: bool=animal.assign_home(building,world.building_uses,world.work_areas,identity)
		if accepted and _cancel_pending: animal.release_home()
		_mutating=false
		if not accepted or _cancel_pending:cancel("Приёмка овцы отменена");return
		_finish(true)
	else:
		if not animal.claim_movement(self):cancel("Овца недоступна");return
		phase=Phase.FINAL_APPROACH
		_final_after_frame=Engine.get_physics_frames() if Engine.is_in_physics_frame() else -1
		_connect(animal.movement.arrived,_animal_arrived.bind(identity))
		_connect(animal.movement.failed,_animal_failed.bind(identity))
		animal.movement.set_target(world.building_uses.entrance(building.id))
		set_physics_process(true)
func _physics_process(delta: float) -> void:
	if _final_after_frame==Engine.get_physics_frames(): return
	_final_after_frame=-1
	if phase==Phase.FINAL_APPROACH and _valid():animal.advance_owned(self,delta,animal.get_base_movement_speed(),INF)
func _animal_failed(expected: StringName) -> void:
	if expected==identity:cancel("Вход недоступен")
func _animal_arrived(expected: StringName) -> void:
	if expected!=identity or phase!=Phase.FINAL_APPROACH:return
	set_physics_process(false)
	phase=Phase.ENTERING
	var next=Intent.new(Intent.Type.MOVE_TO,&"shepherd_shear",C.to_sim(world.building_uses.entrance(building.id)),Balance.WORK_PRIORITY,false)
	next.building_id=building.id;next.slot_purpose=Purpose.WORKER
	_stage(next)
func _accrue() -> void:
	var now: int=world.game_time.total_minutes
	if phase in [Phase.CAPTURING,Phase.SHEARING] and runtime.intents.current_intent==_intent and runtime.data.activity==Activity.WORKING:
		var minutes:=maxi(now-_last_minute,0)
		if phase==Phase.CAPTURING:_progress=mini(_progress+minutes,60)
		elif batch!=null:batch.advance(runtime.data.id,minutes)
	_last_minute=now
func _minute(_now: int) -> void:
	if phase==Phase.NONE or _mutating or _ending:return
	if not _valid():cancel("Работа стала недоступна");return
	_accrue()
	if phase==Phase.CAPTURING and _progress==60:_escort()
	elif phase==Phase.SHEARING and batch.progress==120:_finish(true)
	elif phase==Phase.APPROACH and animal.global_position.distance_to(C.to_world(_intent.target_position))>2.0:_approach()
func _accept_output() -> bool:return building!=null and building.is_built() and not building.production_removed
func _finish(successful: bool, reason: String = "") -> void:
	if _ending or phase==Phase.NONE:return
	if _mutating:_cancel_pending=true;return
	_accrue();_ending=true;_mutating=true
	var old_intent:=_intent;var old_identity:=identity;var old_assignment:=assignment
	var body:=animal;var place:=building;var old_pair:=pair
	last_result={}
	if batch!=null:last_result=batch.settle(runtime.data.id,body.data,_accept_output)
	phase=Phase.NONE;_intent=null;assignment=null;pair=null
	for callback in _callbacks:
		if callback[0].is_connected(callback[1]):callback[0].disconnect(callback[1])
	_callbacks.clear();set_physics_process(false)
	if is_instance_valid(old_pair):old_pair.cancel();old_pair.queue_free()
	if is_instance_valid(body) and body.data.operation_id==old_identity:
		if body.home!=null:body.home.leave_service(old_identity)
		body.release_movement(self,successful)
		body.data.release_operation(old_identity)
		if body.movement_owner==null and (body.home==null or body.home.building.is_built()):body.behavior.resume()
	if place!=null and old_assignment!=null:place.animal_housing.release_reservation(old_identity)
	animal=null;building=null;batch=null
	if old_assignment!=null:runtime.assignments.finish_capture(old_assignment,successful)
	_mutating=false;_ending=false
	if not reason.is_empty():say(reason)
	var result_snapshot:=last_result.duplicate()
	if runtime.intents.current_intent==old_intent:
		if successful:runtime.intents.clear_completed(old_intent)
		else:runtime.intents.cancel_current(old_intent)
	finished.emit(old_identity,successful,result_snapshot)
func cancel(reason: String = "Действие прервано") -> void:_finish(false,reason)
func cancel_assignment(task: RefCounted) -> void:
	if assignment==task:cancel()
func _forced(_old: RefCounted) -> void:cancel()
func _intent_changed(next: RefCounted) -> void:
	if phase!=Phase.NONE and next!=_intent and not _ending:cancel()
func _assignment_changed(id: String) -> void:
	if id==runtime.data.id and phase!=Phase.NONE and not _valid():cancel("Мне некуда привести овцу")
func _building_changed() -> void:
	if phase!=Phase.NONE and not _valid():cancel("Хижина перестала работать")
func _reservation_changed(_resource: int) -> void:
	if phase!=Phase.NONE and batch!=null and not batch.reserves_valid():cancel("Потерян резерв для шерсти")
func _slots_changed(id: StringName, _purpose: int) -> void:
	if phase==Phase.SHEARING and id==building.id and not _valid():cancel("Место обслуживания потеряно")
func _exit_tree() -> void:
	if phase!=Phase.NONE:cancel()
