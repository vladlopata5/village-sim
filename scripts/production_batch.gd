extends RefCounted
## Building-owned process and its own reservation obligations, never resource stock.
const Recipe = preload("res://scripts/production_recipe.gd")
enum State { PREPARING, READY, RUNNING, PAUSED, COMPLETED, CANCELLED }
var id: StringName
var recipe_id: StringName
var recipe: RefCounted
var state := State.PREPARING
var progress := 0
var inputs_spent := false
var order_revision := -1 # Which current building order may receive this output.
var selection_accepted := false
var worker_id := ""
var work_required: int
var inputs: Dictionary
var outputs: Dictionary
var optional_outputs: Dictionary
var _resources: RefCounted
var _inputs: Dictionary = {}
var _outputs: Dictionary = {}
var _mutating := false
var _cancel_pending := false
var _release_pending := false

func _init(batch_id: StringName, definition: RefCounted, resources: RefCounted) -> void:
	id = batch_id
	recipe = definition
	recipe_id = definition.id
	work_required = definition.work_required
	inputs = definition.inputs.duplicate()
	outputs = definition.outputs.duplicate()
	optional_outputs = definition.optional_outputs.duplicate()
	_resources = resources

func output_quantity() -> int:
	return int(outputs.values()[0]) if outputs.size()==1 else 0 # The batch snapshot, never the live definition.

func is_terminal() -> bool: return state in [State.COMPLETED,State.CANCELLED]

func _holds(claims: Dictionary, incoming: bool) -> bool:
	for resource in claims:
		var reserved: int = _resources.get_reserved_in(resource) if incoming else _resources.get_reserved_out(resource)
		if reserved < int(claims[resource]): return false
	return true

func reserves_valid() -> bool:
	return not is_terminal() and _holds(_inputs,false) and _holds(_outputs,true)

func prepare(worker: String) -> bool:
	if state != State.PREPARING or _mutating or not worker_id.is_empty() or worker.is_empty() or work_required<=0: return false
	if outputs.is_empty() or not Recipe.valid_quantities(inputs) or not Recipe.valid_quantities(outputs): return false
	worker_id = worker
	_mutating = true
	var ok := true
	for resource in inputs:
		_inputs[resource] = inputs[resource] # Ownership precedes synchronous resource callbacks.
		if not _resources.reserve_out(resource,inputs[resource]):
			_inputs.erase(resource)
			ok = false
			break
		if _cancel_pending or _release_pending: break
	if ok and not _cancel_pending and not _release_pending:
		for resource in outputs:
			_outputs[resource] = outputs[resource]
			if not _resources.reserve_in(resource,outputs[resource]):
				_outputs.erase(resource)
				ok = false
				break
			if _cancel_pending or _release_pending: break
	if ok: state = State.READY
	_mutating = false
	if not ok: _cancel_pending = true
	_settle()
	return state == State.READY and reserves_valid()

func can_resume() -> bool:
	return state == State.PAUSED and worker_id.is_empty() and not _mutating and reserves_valid()

func claim(worker: String) -> bool:
	if worker.is_empty() or not can_resume(): return false
	worker_id = worker
	return true

func begin(worker: String) -> bool:
	if _mutating or worker != worker_id or worker.is_empty() or not reserves_valid(): return false
	if state == State.PAUSED and inputs_spent:
		state = State.RUNNING
		return true # Resume uses the original output reservation, without new inputs.
	if state != State.READY or inputs_spent: return false
	_mutating = true
	state = State.RUNNING
	inputs_spent = true
	var consumed := _inputs
	_inputs = {}
	var done: bool = _resources.transform_reserved(consumed,{})
	if not done: # A failed transaction emits no callbacks and changes no quantities.
		_inputs = consumed
		inputs_spent = false
		state = State.READY
	_mutating = false
	_settle()
	return done and state == State.RUNNING

func advance(worker: String, minutes: int) -> void:
	if state == State.RUNNING and worker == worker_id and not _mutating:
		progress = mini(progress+maxi(minutes,0),work_required)

func finish(worker: String) -> bool:
	if _mutating or state != State.RUNNING or not inputs_spent or worker != worker_id or progress < work_required or not reserves_valid(): return false
	_mutating = true
	state = State.COMPLETED # A nested callback cannot publish or cancel a committed completion.
	worker_id = ""
	# Only mandatory outputs have occupied capacity during work. Try optional
	# capacity now, accounting for all foreign inbound promises. A miss is lost,
	# not debt and never blocks the mandatory transaction.
	for resource in optional_outputs:
		if _outputs.has(resource) or _resources.get_available_free_capacity(resource)<int(optional_outputs[resource]):continue
		_outputs[resource]=optional_outputs[resource]
		if not _resources.reserve_in(resource,optional_outputs[resource]):_outputs.erase(resource)
	var produced := _outputs
	_outputs = {}
	var done: bool = _resources.transform_reserved({},produced)
	if not done:
		_outputs = produced
		state = State.RUNNING
		worker_id = worker
	_mutating = false
	_settle()
	return done

func release_worker(worker: String) -> void:
	if worker_id != worker or worker.is_empty() or is_terminal(): return
	if _mutating:
		_release_pending = true
		return
	if not inputs_spent:
		cancel()
		return
	worker_id = ""
	state = State.PAUSED # The output reservation belongs to the process, not its worker.

func cancel() -> void:
	if is_terminal(): return
	if _mutating:
		_cancel_pending = true
		return
	state = State.CANCELLED
	worker_id = ""
	var outgoing := _inputs
	var incoming := _outputs
	_inputs = {}
	_outputs = {}
	# Clear obligations before release can reenter deletion/cleanup.
	for resource in outgoing: _resources.release_out(resource,outgoing[resource])
	for resource in incoming: _resources.release_in(resource,incoming[resource])

func _settle() -> void:
	var cancelled := _cancel_pending
	var released := _release_pending
	_cancel_pending = false
	_release_pending = false
	if cancelled: cancel()
	elif released: release_worker(worker_id)

func reserved_output(resource: int) -> int:
	return int(_outputs.get(resource,0))
