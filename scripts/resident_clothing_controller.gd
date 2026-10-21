extends Node
## One personal obtain/equip operation using SourceRef ownership, never a HaulJob.
const Source=preload("res://scripts/resource_source_ref.gd")
const Equipment=preload("res://scripts/resident_equipment.gd")
const Catalog=preload("res://scripts/resource_catalog.gd")
const Intent=preload("res://scripts/resident_intent.gd")
const Purpose=preload("res://scripts/building_slot_purpose.gd").Type
const Balance=preload("res://scripts/balance_config.gd")
signal finished(identity: StringName, obtained: bool)
var runtime: Node
var world: Node
var sources: RefCounted
var _intent: RefCounted
var _source: RefCounted
var _entity: RefCounted
var _resource: int=-1
var _identity: StringName
var _serial:=0
var _obtained: StringName
var _alive:=true
var _active:=false
var _mutating:=false
var _cancel_pending:=false
var _committing:=false
var _last_minute:=0
var _offer: Dictionary={}
var _probe_stamp: Array=[]
var _callbacks: Array=[]
func setup(actor: Node, owner_world: Node) -> void:
	runtime=actor;world=owner_world;sources=world.logistics.sources
	_last_minute=world.game_time.total_minutes
	world.game_time.minute_changed.connect(_minute)
	runtime.intents.intent_changed.connect(_intent_changed)
	runtime.intents.forced_interrupt.connect(_forced)
	runtime.intents.intent_arrived.connect(_arrived)
	# The personal owner publishes/cleans up before synchronous executor callbacks.
	runtime.intents.intent_changed.disconnect(runtime.view.apply_intent)
	runtime.intents.intent_changed.connect(runtime.view.apply_intent)
	runtime.view.tree_exiting.connect(cancel)
	world.player_control.resident_unregistered.connect(_resident_removed)
func _origin() -> Vector2:return world._food_position_2d(runtime.data.id)
func _stamp() -> Array:
	var navigation: RefCounted=world.world_locations.get("navigation")
	return [sources.revision,world.logistics.availability_revision(),navigation.revision if navigation!=null else 0,_origin(),runtime.view.get_sim_position()]
func _first(candidates: Array, origin: Vector2) -> Dictionary:
	candidates=candidates.filter(func(row):return sources.available(row.source,row.resource))
	candidates.sort_custom(func(a,b):
		var da: float=origin.distance_squared_to(sources.point(a.source));var db: float=origin.distance_squared_to(sources.point(b.source))
		return a.source.stable_key()<b.source.stable_key() if da==db else da<db)
	for row in candidates:
		if sources.reachable(origin,sources.point(row.source)):return row
	return {}
func offer() -> Dictionary:
	if not _alive or not is_instance_valid(runtime.view) or _active or not runtime.data.equipment.needs_clothing():return {}
	var stamp:=_stamp()
	if stamp==_probe_stamp and (_offer.is_empty() or sources.available(_offer.source,_offer.resource)):return _offer.duplicate()
	var candidates: Array=[]
	for building in sources.buildings.values():
		for resource in Catalog.equipment_types(&"clothing"):
			if Equipment.allowed(resource):candidates.append({"source":Source.new(Source.Kind.CONTAINER,building.id),"resource":resource})
	_offer=_first(candidates,_origin())
	if _offer.is_empty():
		candidates=[]
		for source in sources.ground_candidates(-1,runtime.view.get_sim_position(),null,null,Equipment.allowed):
			candidates.append({"source":source,"resource":sources.resolve(source).resource_type})
		_offer=_first(candidates,_origin())
	_probe_stamp=stamp
	return _offer.duplicate()
func has_action() -> bool:return not offer().is_empty()
func _connect(signal_value: Signal, callback: Callable) -> void:
	signal_value.connect(callback);_callbacks.append([signal_value,callback])
func start(priority: int=Balance.CLOTHING_PRIORITY) -> bool:
	if _active or runtime.intents.has_current_action() or runtime.intents.player_controlled or runtime.intents.forced_priority>0 or runtime.data.inventory.amount>0:return false
	var selected:=offer();_probe_stamp=[]
	if selected.is_empty():return false
	_serial+=1;_identity=StringName("%s:clothing:%d"%[runtime.data.id,_serial])
	_source=selected.source;_resource=selected.resource;_entity=sources.resolve(_source)
	_active=true;_cancel_pending=false
	if _source.kind==Source.Kind.CONTAINER:
		_connect(_entity.construction_changed,_check_source)
		_connect(_entity.resources.reservations_changed,_check_source)
		_connect(world.player_control.building_unregistered,_building_removed)
	else:
		_connect(_entity.availability_changed,_check_source)
		_connect(sources.ground.removed,_ground_removed)
	_mutating=true
	var reserved: bool=sources.reserve(_source,_resource,_identity)
	_mutating=false
	if not reserved or _cancel_pending or not _valid() or runtime.intents.has_current_action() or runtime.intents.player_controlled or runtime.intents.forced_priority>0:
		cancel();return false
	_intent=Intent.new(Intent.Type.MOVE_TO,&"get_clothing",sources.point(_source),priority,false)
	if _source.kind==Source.Kind.CONTAINER:world.world_locations.configure_intent(_intent,_source.id,Purpose.COURIER,runtime.data.id)
	var expected:=_identity
	if not runtime.intents.submit(_intent):cancel();return false
	return (_active and _identity==expected) or _obtained==expected
func _valid() -> bool:
	return _active and sources.resolve(_source)==_entity and sources.reserved(_source,_resource,_identity) and sources.point(_source) is Vector2
func _at_source() -> bool:
	if _source.kind==Source.Kind.CONTAINER:
		return world.world_locations.at_action(runtime.data.id,_source.id,Purpose.COURIER,runtime.view.get_sim_position(),8.0)
	return runtime.view.get_sim_position().distance_to(sources.point(_source))<=8.0
func _arrived(arrived: RefCounted) -> void:
	if not _active or arrived!=_intent or _mutating:return
	if not _valid() or not _at_source():cancel();return
	_mutating=true;_committing=true
	var obtained: bool=runtime.data.equipment.receive(_resource,sources.pickup.bind(_source,_resource,_identity))
	_committing=false;_mutating=false
	_finish(obtained)
func _finish(obtained: bool) -> void:
	if not _active:return
	if _mutating:_cancel_pending=true;return
	_active=false
	var previous:=_intent;var identity:=_identity
	if obtained:_obtained=identity
	_intent=null
	for callback in _callbacks:
		if callback[0].is_connected(callback[1]):callback[0].disconnect(callback[1])
	_callbacks.clear()
	# Detach before source release can invoke cancellation/replanning again.
	var source:=_source;var entity:=_entity;var resource:=_resource
	_source=null;_entity=null;_probe_stamp=[]
	sources.release(source,resource,identity,entity)
	if is_instance_valid(runtime) and runtime.intents.current_intent==previous:
		if obtained:runtime.intents.clear_completed(previous)
		else:runtime.intents.cancel_current(previous)
	finished.emit(identity,obtained)
func cancel() -> void:_finish(false)
func _intent_changed(next: RefCounted) -> void:
	if _active and _intent!=null and next!=_intent:cancel()
func _forced(_previous: RefCounted) -> void:cancel()
func _check_source(_a: Variant=null,_b: Variant=null) -> void:
	if _active and not _committing and not _valid():cancel()
func _building_removed(id: StringName) -> void:
	if _active and _source.kind==Source.Kind.CONTAINER and _source.id==id:cancel()
func _ground_removed(drop: RefCounted) -> void:
	if _active and not _committing and drop==_entity:cancel()
func _resident_removed(id: String) -> void:
	if id==runtime.data.id:
		_alive=false;cancel()
		if world.game_time.minute_changed.is_connected(_minute):world.game_time.minute_changed.disconnect(_minute)
func _minute(now: int) -> void:
	runtime.data.equipment.advance(maxi(now-_last_minute,0));_last_minute=now
	if _active and not _mutating and not _valid():cancel()
func _exit_tree() -> void:cancel()
