extends RefCounted
## Bounded future recipe kits. Actual quantities/reservations remain in containers/jobs.
const Job = preload("res://scripts/haul_job.gd")
var _owner: WeakRef
var _logistics: WeakRef
var needs: Array[Dictionary] = []
var _next_id := 1
var _reconciling := false
func _init(building: RefCounted) -> void: _owner=weakref(building)
func _touch() -> void:
	var building: RefCounted=_owner.get_ref()
	if building!=null: building.production_revision+=1
func find(recipe_id: StringName) -> Dictionary:
	for need in needs:
		if need.recipe_id==recipe_id: return need
	return {}
func get_need(id: StringName) -> Dictionary:
	for need in needs:
		if need.id==id: return need
	return {}
func _active_jobs(need: Dictionary) -> Array:
	return need.jobs.filter(func(row): return row.job.is_active())
func _replacement(recipe_id: StringName) -> Dictionary:
	var own := find(recipe_id)
	if not own.is_empty(): return own
	var building: RefCounted=_owner.get_ref()
	if building._active_batch_count()+needs.size()<building.production_capacity(): return {}
	# A dormant partial kit never blocks useful work forever. Do not cancel accepted trips.
	for need in needs:
		if not need.claiming and _active_jobs(need).is_empty(): return need
	return {}
func _outputs(resource: int, except_id: StringName = &"") -> int:
	var total := 0
	for need in needs:
		if need.id!=except_id: total+=int(need.recipe.outputs.get(resource,0))
	return total
func allows(recipe_id: StringName, replacement: Dictionary = {}) -> bool:
	var building: RefCounted=_owner.get_ref()
	if building==null or building.production_removed or not building.is_built(): return false
	var recipe = building.definition.get_production_recipe(recipe_id)
	if recipe==null or not recipe.is_valid(): return false
	var mode: int=building.get_recipe_mode(recipe_id)
	if mode<=building.ProductionMode.OFF: return false
	var replaced := _replacement(recipe_id) if replacement.is_empty() else replacement
	var ignored: StringName=replaced.get("id",&"")
	if building._active_batch_count()+needs.size()-(0 if ignored.is_empty() else 1)>=building.production_capacity(): return false
	if mode==building.ProductionMode.ORDER:
		var promised: int=building._promised_for_recipe(recipe_id)
		for need in needs:
			if need.id!=ignored and need.recipe_id==recipe_id: promised+=need.recipe.output_quantity()
		if building.get_order_remaining(recipe_id)-promised<1: return false
	if mode==building.ProductionMode.MAINTAIN:
		var product: int=recipe.counted_product()
		if building._maintain_stock(product)+_outputs(product,ignored)>=int(building.get_recipe_settings(recipe_id).target): return false
	for resource in recipe.outputs:
		if building.resources.get_available_free_capacity(resource)-_outputs(resource,ignored)<int(recipe.outputs[resource]): return false
	return true
func deficits(recipe_id: StringName) -> Dictionary:
	if not allows(recipe_id): return {}
	var building: RefCounted=_owner.get_ref()
	var recipe = building.definition.get_production_recipe(recipe_id)
	var own := find(recipe_id)
	if not own.is_empty() and own.claiming: return {}
	var replaced := _replacement(recipe_id)
	var rows: Array = needs.filter(func(need): return replaced.is_empty() or need.id!=replaced.id or need.recipe_id==recipe_id)
	var target: Dictionary=own if not own.is_empty() else {"recipe_id":recipe_id,"recipe":recipe,"jobs":[]}
	if own.is_empty(): rows.append(target)
	var pool: Dictionary={}
	var incoming: Dictionary={}
	# First protect inbound units already promised specifically to each kit.
	for need in rows:
		var owned: Dictionary={}
		for row in _active_jobs(need): owned[row.job.resource_type]=int(owned.get(row.job.resource_type,0))+1
		incoming[need.recipe_id]=owned
		for resource in need.recipe.inputs:
			if not pool.has(resource): pool[resource]=building.resources.get_available_amount(resource)+building.resources.get_reserved_in(resource)
		for resource in owned: pool[resource]=int(pool.get(resource,building.resources.get_available_amount(resource)+building.resources.get_reserved_in(resource)))-int(owned[resource])
	for need in rows:
		var missing: Dictionary={}
		for resource in need.recipe.inputs:
			var required: int=maxi(0,int(need.recipe.inputs[resource])-int(incoming[need.recipe_id].get(resource,0)))
			var assigned: int=mini(required,maxi(0,int(pool.get(resource,0))))
			pool[resource]=int(pool.get(resource,0))-assigned
			if required>assigned: missing[resource]=required-assigned
		if need.recipe_id==recipe_id: return missing
	return {}
func open(recipe_id: StringName, logistics: RefCounted) -> Dictionary:
	if not allows(recipe_id): return {}
	var own := find(recipe_id)
	if not own.is_empty(): return own if not own.claiming else {}
	var replaced := _replacement(recipe_id)
	if not replaced.is_empty(): _remove(replaced)
	if not allows(recipe_id): return {}
	var building: RefCounted=_owner.get_ref()
	_logistics=weakref(logistics)
	var need: Dictionary={"id":StringName("%s:supply_%04d" % [building.id,_next_id]),"recipe_id":recipe_id,"recipe":building.definition.get_production_recipe(recipe_id),"jobs":[],"claiming":false}
	_next_id+=1
	needs.append(need)
	_touch()
	return need
func valid(id: StringName) -> bool:
	var need := get_need(id)
	return not need.is_empty() and allows(need.recipe_id,need)
func begin_claim(need: Dictionary) -> void:
	need.claiming=true
	_touch()
func end_claim(need: Dictionary, job: Job) -> bool:
	need.claiming=false
	if job!=null and job.is_active() and valid(need.id):
		need.jobs.append({"job":job,"accepted":false})
		job.finished.connect(_finished.bind(weakref(self),need.id),CONNECT_ONE_SHOT)
		_touch()
		return true
	if _active_jobs(need).is_empty() and not get_need(need.id).is_empty(): _remove(need)
	return false
func accept(id: StringName, job: Job) -> void:
	var need := get_need(id)
	if need.is_empty() or not job.is_active(): return
	for row in need.jobs:
		if row.job==job and not row.accepted:
			row.accepted=true
			_owner.get_ref().accept_recipe_task(need.recipe_id)
			return
static func _finished(job: Job, plan_ref: WeakRef, need_id: StringName) -> void:
	var plan: RefCounted=plan_ref.get_ref()
	if plan!=null: plan._on_finished(job,need_id)
func _on_finished(job: Job, id: StringName) -> void:
	var need := get_need(id)
	if need.is_empty(): return
	need.jobs=need.jobs.filter(func(row): return row.job!=job)
	_touch()
	if not valid(id) or (job.state==Job.State.CANCELLED and _active_jobs(need).is_empty()): _remove(need)
func _remove(need: Dictionary) -> void:
	if get_need(need.id).is_empty(): return
	needs.erase(need) # Validation fails before any cancellation can reenter.
	_touch()
	var logistics: RefCounted=_logistics.get_ref() if _logistics!=null else null
	if logistics!=null:
		for row in _active_jobs(need): logistics.cancel_transport(row.job,"рецептурная потребность снята")
func consume_for_start(recipe_id: StringName) -> void:
	var replaced := _replacement(recipe_id)
	if not replaced.is_empty(): _remove(replaced)
func reconcile() -> void:
	if _reconciling: return
	_reconciling=true
	var snapshot := needs.duplicate()
	snapshot.reverse() # Drop newest excess first when a limit shrinks.
	for need in snapshot:
		if not valid(need.id): _remove(need)
	_reconciling=false
func clear() -> void:
	for need in needs.duplicate(): _remove(need)

func input_room(recipe_id: StringName, resource: int) -> bool:
	var building: RefCounted=_owner.get_ref()
	var replaced := _replacement(recipe_id)
	var ignored: StringName=replaced.get("id",&"")
	var output: int=building.definition.get_production_recipe(recipe_id).outputs.get(resource,0)
	return building.resources.get_available_free_capacity(resource)-_outputs(resource,ignored)-output>=1
