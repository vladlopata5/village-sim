extends Node
## Field operations own cells/seed; hauling and threshing use existing executors.
const Area=preload("res://scripts/building_work_area.gd")
const Field=preload("res://scripts/farm_fields.gd")
const Season=preload("res://scripts/season.gd")
const R=preload("res://scripts/resource_type.gd").Type
const Types=preload("res://scripts/building_type.gd").Type
const Profession=preload("res://scripts/resident_profession.gd").Type
const Intent=preload("res://scripts/resident_intent.gd")
const Purpose=preload("res://scripts/building_slot_purpose.gd").Type
const Activity=preload("res://scripts/resident_activity.gd").Type
const Balance=preload("res://scripts/balance_config.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const TargetScore=preload("res://scripts/work_target_score.gd")
enum Phase { NONE, TO_BUILDING, TO_FIELD, WORKING }
signal completed(kind: StringName, cell: Vector2i, result: int)
var runtime: Node
var world: Node
var phase:=Phase.NONE
var _mutating:=false
var _cancel_pending:=false
var _ending:=false
var _serial:=0
var _alive:=true
var _owner: StringName
var _kind: StringName
var _building: RefCounted
var _context: Array=[]
var _cells: Array=[]
var _target:=Vector2i.ZERO
var _intent: RefCounted
var _seed_reserved:=false
var _paid:=false
var _progress:=0
var _last_minute:=0
var _offer: Dictionary={}
var _stamp: Array=[]
func setup(actor: Node, owner_world: Node) -> void:
	runtime=actor;world=owner_world
	if not world.has_method("_farm_cell_allowed"):return
	world.game_time.minute_changed.connect(_minute)
	world.game_time.season_changed.connect(_season)
	runtime.intents.intent_changed.connect(_changed)
	runtime.intents.forced_interrupt.connect(cancel)
	runtime.intents.intent_arrived.connect(_arrived)
	runtime.view.tree_exiting.connect(cancel)
	world.player_control.work_assignment_changed.connect(_assignment)
	world.player_control.resident_unregistered.connect(_removed)
	world.player_control.building_work_area_changed.connect(_area_changed)
	world.work_areas.changed.connect(_check)
	world.farm_fields.operation_invalidated.connect(_invalidated)
	runtime.intents.intent_changed.disconnect(runtime.view.apply_intent)
	runtime.intents.intent_changed.connect(runtime.view.apply_intent)
func workplace() -> RefCounted:
	if not _alive or world==null or not world.has_method("_farm_cell_allowed") or runtime.data.profession!=Profession.FARMER:return null
	var place: RefCounted=world.player_control.get_building(runtime.data.work_location_id)
	return place if place!=null and place.type==Types.FARM and place.is_built() and runtime.data.work_area_id.is_empty() else null
func _identity(place: RefCounted) -> Array:
	var area: RefCounted=Area.resolve(place,world.work_areas)
	return [place.get_instance_id(),runtime.data.work_assignment_revision,area.id,area.revision,area.center,area.radius]
func _point(cell: Vector2i) -> Vector2:return C.to_sim(world.build_grid.cell_to_world(cell))
func _origin() -> Vector2:return world._food_position_2d(runtime.data.id)
func _reachable(cell: Vector2i) -> bool:return world.logistics.sources.reachable(_origin(),_point(cell))
func _in_area(cell: Vector2i, place: RefCounted) -> bool:return Area.resolve(place,world.work_areas).contains(_point(cell))
func _eligible() -> bool:return not _ending and workplace()!=null and phase==Phase.NONE and runtime.data.inventory.amount==0 and world.logistics.get_job(runtime.data.id)==null and not runtime.intents.player_controlled and runtime.intents.forced_priority==0 and not runtime.intents.has_current_action() and world.game_time.get_phase()=="День"
func _rank(cells: Array, mature: bool=false) -> void:
	var priority: Callable=func(cell):return -world.farm_fields.maturity(cell) if mature else 0
	cells.assign(TargetScore.ordered(cells,_origin(),workplace().position,_point,func(cell):return cell,priority))
func _plow_candidates(place: RefCounted) -> Array:
	var area: RefCounted=Area.resolve(place,world.work_areas)
	var center: Vector3=C.to_world(area.center);var radius: float=C.length_to_world(area.radius)
	var start: Vector2i=world.build_grid.world_to_cell(center-Vector3(radius,0,radius))
	var end: Vector2i=world.build_grid.world_to_cell(center+Vector3(radius,0,radius))
	var size: Vector2i=world.build_grid.grid_size();var result: Array=[]
	for y in range(maxi(0,start.y),mini(size.y,end.y+1)):
		for x in range(maxi(0,start.x),mini(size.x,end.x+1)):
			var cell:=Vector2i(x,y)
			if world.farm_fields.available(cell,Field.State.BARE) and area.contains(_point(cell)):result.append(cell)
	_rank(result);return result
func _first_plow(place: RefCounted) -> Variant:
	for cell in _plow_candidates(place):
		if world._farm_cell_allowed(cell) and _reachable(cell):return cell
	return null
func _collect(place: RefCounted) -> Dictionary:
	if place.resources.get_available_free_capacity(R.SHEAF)<1:return {}
	var drops: Array=world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.SHEAF and drop.available_amount()>0 and Area.resolve(place,world.work_areas).contains(drop.world_position))
	var origin:=_origin()
	drops.sort_custom(func(a,b):return origin.distance_squared_to(a.world_position)<origin.distance_squared_to(b.world_position) or (origin.distance_squared_to(a.world_position)==origin.distance_squared_to(b.world_position) and String(a.id)<String(b.id)))
	for drop in drops:
		if world.logistics.sources.reachable(origin,drop.world_position) and world.logistics.sources.reachable(drop.world_position,world.world_locations.get_position(place.id)):return {"kind":&"COLLECT","source":Source.new(Source.Kind.GROUND,drop.id),"resource":R.SHEAF}
	return {}
func task() -> Dictionary:
	var place:=workplace()
	if place==null or phase!=Phase.NONE or runtime.data.inventory.amount>0 or world.logistics.get_job(runtime.data.id)!=null:return {}
	var stamp: Array=_identity(place)+[place.position,Engine.get_process_frames(),world.farm_fields.revision,world.logistics.availability_revision(),world.logistics.sources.revision,world.navigation.revision,_origin(),world.game_time.get_season()]
	if stamp==_stamp and not _offer.is_empty():return _offer.duplicate()
	_offer={};_stamp=stamp
	var collect:=_collect(place)
	if not collect.is_empty():_offer=collect;return _offer.duplicate()
	var fields=world.farm_fields;var season: int=world.game_time.get_season()
	var field_season: bool=season in [Season.Type.SPRING,Season.Type.SUMMER]
	var plow: Variant=null
	var plow_checked:=false
	if field_season:
		var plowed: Array=fields.plot_cells().filter(func(cell):return fields.available(cell,Field.State.PLOWED) and _in_area(cell,place) and world._farm_cell_allowed(cell))
		_rank(plowed)
		# Count the reachable prepared patch even when no seed is available yet.
		var sow: Array=[]
		for cell in plowed:
			if _reachable(cell):sow.append(cell)
			if sow.size()==Balance.FARM_SOW_CELLS:break
		if sow.size()<Balance.FARM_SOW_CELLS:
			plow=_first_plow(place);plow_checked=true
		if place.resources.get_available_amount(R.WHEAT)>0 and not sow.is_empty() and (sow.size()==Balance.FARM_SOW_CELLS or plow==null):_offer={"kind":&"SOW","cells":sow}
		elif sow.size()<Balance.FARM_SOW_CELLS and plow!=null:_offer={"kind":&"PLOW","cells":[plow]}
		if not _offer.is_empty():return _offer.duplicate()
	var supply: Dictionary=runtime.self_logistics.stock_task(place)
	if not supply.is_empty():_offer=supply;return _offer.duplicate()
	# Same plow action as above; only its priority changes after a prepared patch.
	if field_season:
		if not plow_checked:plow=_first_plow(place)
		if plow!=null:_offer={"kind":&"PLOW","cells":[plow]}
	elif season==Season.Type.AUTUMN:
		var mature: Array=fields.plot_cells().filter(func(cell):return fields.available(cell,Field.State.SOWN) and fields.maturity(cell)>=4 and _in_area(cell,place) and world._farm_cell_allowed(cell))
		_rank(mature,true)
		for cell in mature:
			if _reachable(cell):_offer={"kind":&"MOW","cells":[cell]};break
	if not _offer.is_empty():return _offer.duplicate()
	var full: Array=[]
	for resource in [R.WHEAT,R.STRAW]:
		if place.resources.get_amount(resource)>=place.resources.get_capacity(resource):full.append(resource)
	var export: Dictionary=runtime.self_logistics._export(place,full)
	if not export.is_empty():_offer=export;return _offer.duplicate()
	if runtime.recipe_work.has_work():_offer={"kind":&"THRESH"}
	return _offer.duplicate()
func has_work() -> bool:return not task().is_empty()
func _haul_valid(place: RefCounted, context: Array, source: RefCounted) -> bool:
	return workplace()==place and _identity(place)==context and (source.kind!=Source.Kind.GROUND or world.logistics.sources.point(source)==null or Area.resolve(place,world.work_areas).contains(world.logistics.sources.point(source)))
func request_work() -> bool:
	if not _eligible():return false
	var candidate:=task();_stamp=[]
	if candidate.is_empty():return false
	var place:=workplace()
	if candidate.kind==&"IMPORT":return runtime.self_logistics.request_stock_supply(place,candidate)
	if candidate.kind==&"THRESH":return runtime.recipe_work.request_work()
	if candidate.kind==&"EXPORT":return runtime.self_logistics._start_export(place,candidate)
	if candidate.kind==&"COLLECT":
		var context:=_identity(place);var valid:=_haul_valid.bind(place,context,candidate.source)
		var eligible: Callable=func():return _eligible() and valid.call()
		var job=world.logistics.claim_transport(runtime.data.id,candidate.source,place,R.SHEAF,eligible,true,valid,false,0.0,place)
		if job==null:return false
		if world.logistics.start_claimed_job(job,runtime.data.id):return true
		world.logistics.cancel_transport(job,"сбор снопа не начался");return false
	_serial+=1;_owner=StringName("%s:farming:%d"%[runtime.data.id,_serial])
	_kind=candidate.kind;_building=place;_context=_identity(place);_cells=candidate.cells.duplicate();_paid=false;_seed_reserved=false;_cancel_pending=false
	phase=Phase.TO_FIELD
	_building.construction_changed.connect(_check)
	var expected: int=Field.State.BARE if _kind==&"PLOW" else (Field.State.PLOWED if _kind==&"SOW" else Field.State.SOWN)
	_mutating=true
	var claimed: bool=world.farm_fields.reserve(_cells,_owner,expected,world._farm_cell_allowed)
	if claimed and _kind==&"SOW":
		_seed_reserved=true
		if not place.resources.reserve_out(R.WHEAT,1):_seed_reserved=false;claimed=false
	_mutating=false
	if not claimed or _cancel_pending or not _valid():cancel();return false
	if _kind==&"SOW":return _move(true)
	return _next_cell()
func _valid() -> bool:
	if phase==Phase.NONE or workplace()!=_building or _identity(_building)!=_context:return false
	var season: int=world.game_time.get_season()
	if (_kind==&"MOW" and season!=Season.Type.AUTUMN) or (_kind!=&"MOW" and season not in [Season.Type.SPRING,Season.Type.SUMMER]):return false
	if _seed_reserved and _building.resources.get_reserved_out(R.WHEAT)<1:return false
	for cell in _cells:
		if not world.farm_fields.owned(cell,_owner) or not _in_area(cell,_building) or not world._farm_cell_allowed(cell):return false
	return true
func keeps_shift_action() -> bool:return phase!=Phase.NONE and _valid()
func _move(preparation: bool=false) -> bool:
	var previous:=_intent;_intent=null
	if previous!=null and runtime.intents.current_intent==previous:runtime.intents.clear_completed(previous)
	if runtime.intents.has_current_action():cancel();return false
	phase=Phase.TO_BUILDING if preparation else Phase.TO_FIELD
	_intent=Intent.new(Intent.Type.MOVE_TO,StringName("farm_"+String(_kind).to_lower()),world.world_locations.get_position(_building.id) if preparation else _point(_target),Balance.WORK_PRIORITY,false)
	if preparation:world.world_locations.configure_intent(_intent,_building.id,Purpose.WORKER,runtime.data.id)
	if not runtime.intents.submit(_intent):cancel();return false
	return phase!=Phase.NONE
func _next_cell() -> bool:
	if _cells.is_empty():_finish(true);return true
	_target=_cells[0];_progress=0
	return _move()
func _arrived(intent: RefCounted) -> void:
	if phase not in [Phase.TO_BUILDING,Phase.TO_FIELD] or intent!=_intent or _mutating:return
	if not _valid():cancel();return
	if phase==Phase.TO_BUILDING:
		if not world.world_locations.at_action(runtime.data.id,_building.id,Purpose.WORKER,runtime.view.get_sim_position(),8.0):cancel();return
		_next_cell();return
	if runtime.view.get_sim_position().distance_to(_point(_target))>8.0:cancel();return
	phase=Phase.WORKING;_last_minute=world.game_time.total_minutes;runtime.data.activity=Activity.WORKING
func _pay_seed() -> bool:
	if _paid:return true
	if not _seed_reserved:return false
	_seed_reserved=false;_paid=true
	if _building.resources.take_reserved(R.WHEAT,1):return true
	_seed_reserved=true;_paid=false;return false
func _minute(now: int) -> void:
	if phase==Phase.NONE or _mutating:return
	if not _valid():cancel();return
	if phase!=Phase.WORKING:return
	if runtime.data.activity==Activity.WORKING and runtime.view.get_sim_position().distance_to(_point(_target))<=8.0:_progress+=maxi(0,now-_last_minute)
	_last_minute=now
	if _progress<Balance.FARM_FIELD_WORK_MINUTES:return
	_mutating=true
	var cell:=_target;var result:=0;var done:=false
	match _kind:
		&"PLOW":done=world.farm_fields.plow(cell,_owner)
		&"SOW":done=world.farm_fields.sow(cell,_owner,world.game_time.get_day(),_pay_seed)
		&"MOW":
			result=world.farm_fields.mow(cell,_owner);done=result>=0
			if result>0:world.place_ground_resources(R.SHEAF,result,_point(cell))
	if done:_cells.erase(cell);completed.emit(_kind,cell,result)
	_mutating=false
	if not done or _cancel_pending or not _valid():cancel();return
	_next_cell()
func _finish(success: bool) -> void:
	if phase==Phase.NONE:return
	if _mutating:_cancel_pending=true;return
	_ending=true;phase=Phase.NONE
	var previous:=_intent;_intent=null
	if _building!=null and _building.construction_changed.is_connected(_check):_building.construction_changed.disconnect(_check)
	world.farm_fields.release(_owner)
	if _seed_reserved:
		_seed_reserved=false;_building.resources.release_out(R.WHEAT,1)
	_cells=[];_building=null;_stamp=[];_ending=false
	if previous!=null and runtime.intents.current_intent==previous:
		if success:runtime.intents.clear_completed(previous)
		else:runtime.intents.cancel_current(previous)
func cancel(_previous: Variant=null) -> void:_finish(false)
func _changed(next: RefCounted) -> void:
	if phase!=Phase.NONE and _intent!=null and next!=_intent:cancel()
func _check() -> void:
	if phase!=Phase.NONE and not _mutating and not _valid():cancel()
func _assignment(id: String) -> void:
	if id==runtime.data.id:_check()
func _area_changed(id: StringName) -> void:
	if _building!=null and id==_building.id:_check()
func _invalidated(operation_owner: StringName) -> void:
	if phase!=Phase.NONE and operation_owner==_owner:cancel()
func _season(_previous: int, _current: int) -> void:_check()
func _exit_tree() -> void:cancel()

func _removed(id: String) -> void:
	if id==runtime.data.id:_alive=false;cancel()
