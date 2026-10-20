extends Node
## Joint recipe choice; all physical supply/export remains in HaulExecutor.
const Profession = preload("res://scripts/resident_profession.gd")
const Types = preload("res://scripts/building_type.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
var runtime: Node
var world: Node
var _offer: Dictionary={}
var _offer_stamp: Array=[]
func setup(owner_runtime: Node, owner_world: Node) -> void:
	runtime = owner_runtime
	world = owner_world
func _workplace() -> RefCounted:
	var target = world.player_control.get_building(runtime.data.work_location_id)
	if target==null or not target.is_built() or not world.world_locations.get_position(target.id) is Vector2: return null
	if not target.definition.production_recipes.is_empty() and runtime.data.profession==target.definition.worker_profession: return target
	if runtime.data.profession==Profession.Type.SHEPHERD and target.type==Types.Type.SHEPHERD_HUT: return target
	if runtime.data.profession==Profession.Type.GATHERER and target.type==Types.Type.GATHERER_HUT: return target
	return null
func _eligible(workplace_id: StringName, source_ref: RefCounted = null) -> bool:
	var place := _workplace()
	return place!=null and place.id==workplace_id and runtime.data.inventory.amount==0 and world.game_time.get_phase()=="День" and not runtime.intents.player_controlled and runtime.intents.forced_priority==0 and not runtime.intents.has_current_action() and (source_ref == null or world.logistics.sources.ground_allowed(source_ref,runtime.view.get_sim_position(),place))
func _committed_workplace(id: StringName) -> bool:
	var target = world.player_control.get_building(id)
	return target!=null and target.is_built() and world.world_locations.get_position(id) is Vector2
func _stamp(place: RefCounted) -> Array:
	return world.logistics.sources.GroundAreas.identity(runtime.view.get_sim_position(),place) + [Engine.get_process_frames(),world.game_time.total_minutes,place.id,place.production_revision,world.logistics.availability_revision(),world.logistics.sources.revision,world.world_locations.navigation.revision,runtime.data.work_assignment_revision,runtime.view.get_sim_position(),world.game_time.get_phase()]
func _source_for(resource: int, place: RefCounted, checked: Dictionary) -> RefCounted:
	if not place.definition.allows_external_import(resource): return null
	if not checked.has(resource):
		checked[resource]=world.logistics.sources.find_first(resource,runtime.view.get_sim_position(),world.world_locations.get_position(place.id),place.id,place)
	return checked[resource]
func task() -> Dictionary:
	var place := _workplace()
	if place==null or runtime.data.inventory.amount!=0 or world.logistics.get_job(runtime.data.id)!=null: return {}
	var recipes: Array=place.definition.production_recipes
	if recipes.is_empty():
		if place.type==Types.Type.SHEPHERD_HUT: return _export(place,[preload("res://scripts/resource_type.gd").Type.WOOL])
		var natural: RefCounted=world.production.find_source(runtime.data)
		if natural!=null: return {"kind":&"GATHER","source":natural}
		return _export(place,[preload("res://scripts/resource_type.gd").Type.MUSHROOM])
	var identity := _stamp(place)
	if not _offer.is_empty() and _offer_stamp==identity:
		if _offer.kind!=&"SUPPLY" or (world.logistics.sources.available(_offer.source,_offer.resource) and world.logistics.sources.ground_allowed(_offer.source,runtime.view.get_sim_position(),place)): return _offer.duplicate()
	var checked: Dictionary={} # One lookup per missing concrete input in this read, including misses.
	var selected: Dictionary=place.select_production_work(runtime.data.id,_source_for.bind(place,checked))
	var result: Dictionary={}
	if not selected.is_empty():
		if selected.kind==&"SUPPLY":
			result=selected.duplicate()
			result.destination=place
		else: result={"kind":&"PRODUCTION"}
	else:
		var outputs: Array=[]
		for recipe in recipes:
			for resource in recipe.outputs:
				if resource not in outputs: outputs.append(resource)
		result=_export(place,outputs)
	# Only positive, same-frame proposals are reused. No durable negative cache.
	_offer=result.duplicate()
	_offer_stamp=identity
	return result
func _export(place: RefCounted, outputs: Array) -> Dictionary:
	var sources = world.logistics.sources
	var origin: Vector2=runtime.view.get_sim_position()
	var access: Vector2=world.world_locations.get_position(place.id)
	for resource in outputs:
		var reference := Source.new(Source.Kind.CONTAINER,place.id)
		if not sources.available(reference,resource) or not sources.reachable(origin,access): continue
		var destinations: Array=sources.storage_destinations(reference,resource,access)
		if not destinations.is_empty(): return {"kind":&"EXPORT","source":reference,"destination":destinations[0],"resource":resource}
	return {}
func has_work() -> bool: return not task().is_empty()
func _supply_valid(workplace_id: StringName, need_id: StringName) -> bool:
	var place = world.player_control.get_building(workplace_id)
	return place!=null and _committed_workplace(workplace_id) and place.supply.valid(need_id)
func _supply_eligible(workplace_id: StringName, need_id: StringName, revision: int, source_ref: RefCounted) -> bool:
	return runtime.data.work_assignment_revision==revision and _eligible(workplace_id,source_ref) and _supply_valid(workplace_id,need_id)
func _request_supply(place: RefCounted, candidate: Dictionary) -> bool:
	var need: Dictionary=place.supply.open(candidate.recipe_id,world.logistics)
	if need.is_empty(): return false
	var missing: Dictionary=place.supply.deficits(candidate.recipe_id)
	if not missing.has(candidate.resource) or not world.logistics.sources.available(candidate.source,candidate.resource):
		place.supply.end_claim(need,null)
		return false
	place.supply.begin_claim(need)
	var job=world.logistics.claim_transport(runtime.data.id,candidate.source,place,candidate.resource,_supply_eligible.bind(place.id,need.id,runtime.data.work_assignment_revision,candidate.source),true,_supply_valid.bind(place.id,need.id))
	if not place.supply.end_claim(need,job):
		if job!=null: world.logistics.cancel_transport(job,"снабжение не закреплено")
		return false
	if world.logistics.start_claimed_job(job,runtime.data.id) and job.is_active() and world.logistics.get_job(runtime.data.id)==job:
		place.supply.accept(need.id,job)
		return true
	world.logistics.cancel_transport(job,"снабжение не началось")
	return false
func request_work() -> bool:
	var place := _workplace()
	if place==null or not _eligible(place.id): return false
	var candidate := task()
	_offer={}
	if candidate.is_empty(): return false
	if candidate.kind==&"GATHER":
		var identity: Array=world.production.context(runtime.data)
		var valid: Callable=world.production.valid.bind(runtime.data,identity)
		var eligible: Callable=func(): return _eligible(place.id) and valid.call()
		var gathering=world.logistics.claim_transport(runtime.data.id,candidate.source,place,preload("res://scripts/resource_type.gd").Type.MUSHROOM,eligible,true,valid,false,0.0,place)
		if gathering!=null:
			gathering.finished.connect(_gathering_finished,CONNECT_ONE_SHOT)
			if world.logistics.start_claimed_job(gathering,runtime.data.id): return true
		world.logistics.cancel_transport(gathering,"сбор не начался")
		return false
	if candidate.kind==&"PRODUCTION": return runtime.recipe_work.request_work()
	if candidate.kind==&"SUPPLY": return _request_supply(place,candidate)
	var job=world.logistics.claim_transport(runtime.data.id,candidate.source,candidate.destination,candidate.resource,_eligible.bind(place.id,candidate.source),true,_committed_workplace.bind(place.id))
	if job==null: return false
	if world.logistics.start_claimed_job(job,runtime.data.id): return true
	world.logistics.cancel_job(job)
	return false

func _gathering_finished(job: RefCounted) -> void:
	if job.state==job.State.COMPLETED:
		runtime.data.add_skill_xp(preload("res://scripts/skill_type.gd").Type.GATHERING,1)
