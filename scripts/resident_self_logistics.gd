extends Node
## Worker policy only: production first, own input supply, then own output to Storage.
const Profession = preload("res://scripts/resident_profession.gd")
const Types = preload("res://scripts/building_type.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
var runtime: Node
var world: Node
func setup(owner_runtime: Node, owner_world: Node) -> void:
	runtime = owner_runtime
	world = owner_world
func _workplace() -> RefCounted:
	var target = world.player_control.get_building(runtime.data.work_location_id)
	if target==null or not target.is_built() or not world.world_locations.get_position(target.id) is Vector2: return null
	if runtime.data.profession==Profession.Type.SAWYER and target.type==Types.Type.SAWMILL: return target
	if runtime.data.profession==Profession.Type.GATHERER and target.type==Types.Type.GATHERER_HUT: return target
	return null
func _production_available() -> bool:
	return runtime.recipe_work.has_work() if runtime.data.profession==Profession.Type.SAWYER else world.production.can_work(runtime.data)
func _eligible(workplace_id: StringName) -> bool:
	var place := _workplace()
	return place!=null and place.id==workplace_id and runtime.data.inventory.amount==0 and world.game_time.get_phase()=="День" and not runtime.intents.player_controlled and runtime.intents.forced_priority==0 and not runtime.intents.has_current_action()
func _committed_workplace(id: StringName) -> bool:
	var target = world.player_control.get_building(id)
	return target!=null and target.is_built() and world.world_locations.get_position(id) is Vector2
func task() -> Dictionary:
	var place := _workplace()
	if place==null or runtime.data.inventory.amount!=0 or world.logistics.get_job(runtime.data.id)!=null: return {}
	if _production_available(): return {"kind":&"PRODUCTION"}
	var origin: Vector2 = runtime.view.get_sim_position()
	var access: Vector2 = world.world_locations.get_position(place.id)
	var sources = world.logistics.sources
	if runtime.data.profession==Profession.Type.SAWYER:
		var recipe = place.definition.production_recipe
		var output_room: bool = recipe.outputs.keys().all(func(resource): return place.resources.get_available_free_capacity(resource)>=int(recipe.outputs[resource]))
		for resource in recipe.inputs:
			if not output_room: break
			if place.resources.get_amount(resource)+place.resources.get_reserved_in(resource)>=int(recipe.inputs[resource]) or place.resources.get_available_free_capacity(resource)<1: continue
			var matches: Array = sources.find(resource,origin,access,place.id)
			if not matches.is_empty(): return {"kind":&"SUPPLY","source":matches[0],"destination":place,"resource":resource}
	var outputs: Array = place.definition.production_recipe.outputs.keys() if runtime.data.profession==Profession.Type.SAWYER else [preload("res://scripts/resource_type.gd").Type.FOOD]
	for resource in outputs:
		var reference := Source.new(Source.Kind.CONTAINER,place.id)
		if not sources.available(reference,resource) or not sources.reachable(origin,access): continue
		var destinations: Array = sources.storage_destinations(reference,resource,access)
		if not destinations.is_empty(): return {"kind":&"EXPORT","source":reference,"destination":destinations[0],"resource":resource}
	return {}
func has_work() -> bool: return not task().is_empty()
func request_work() -> bool:
	var place := _workplace()
	if place==null or not _eligible(place.id): return false
	var candidate := task()
	if candidate.is_empty(): return false
	if candidate.kind==&"PRODUCTION": return runtime.recipe_work.request_work() if runtime.data.profession==Profession.Type.SAWYER else runtime.schedule.request_work()
	var job = world.logistics.claim_transport(runtime.data.id,candidate.source,candidate.destination,candidate.resource,_eligible.bind(place.id),true,_committed_workplace.bind(place.id))
	if job==null: return false
	if world.logistics.start_claimed_job(job,runtime.data.id): return true
	world.logistics.cancel_job(job)
	return false
