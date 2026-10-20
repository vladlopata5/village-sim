extends "res://scripts/production_batch.gd"
## ProductionBatch work/reservation lifecycle with a one-place minimum and partial settlement.
const WOOL=preload("res://scripts/resource_type.gd").Type.WOOL
var potential := 0
var result: Dictionary = {}
func _init(identity: StringName, resources: RefCounted) -> void:
	super(identity,preload("res://scripts/production_recipe.gd").new({},{WOOL:1},120,&"shearing"),resources)
func begin_shearing(worker: String, random: RandomNumberGenerator) -> bool:
	if not begin(worker): return false
	potential=random.randi_range(3,5)
	return true
func settle(worker: String, animal: RefCounted, accepting: Callable) -> Dictionary:
	if not result.is_empty(): return result.duplicate()
	if worker!=worker_id or _mutating: return {}
	_mutating=true
	var produced := floori(float(potential)*progress/work_required) if inputs_spent else 0
	var removed := ceili(15.0*progress/work_required) if inputs_spent else 0
	var held: int=_outputs.get(WOOL,0)
	if _resources.get_reserved_in(WOOL)<held: held=0
	_outputs={}
	state=State.COMPLETED if progress==work_required else State.CANCELLED
	worker_id=""
	result={"produced":produced,"saved":0,"discarded":produced,"levels":removed,"minutes":progress,"potential":potential}
	# Terminal before wool/resource callbacks; a second settlement cannot publish again.
	animal.wool_growth=maxi(animal.wool_growth-removed,0)
	if accepting.call() and produced>0:
		var extra := mini(maxi(produced-held,0),_resources.get_available_free_capacity(WOOL))
		if extra>0 and _resources.reserve_in(WOOL,extra): held+=extra
		var saved := mini(produced,held)
		if saved>0 and accepting.call() and _resources.transform_reserved({},{WOOL:saved}):
			held-=saved
			result.saved=saved
			result.discarded=produced-saved
	if held>0: _resources.release_in(WOOL,held)
	_mutating=false
	return result.duplicate()
