extends SceneTree
const B=preload("res://scripts/building_instance.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
var checks:=0
var failures:=0
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var definition=D.for_type(T.HOME)
	definition.construction_requirements={R.LOG:11,R.STONE:7,R.PLANK:4}
	definition.construction_work_required=100
	var site=B.new(&"site",definition,Vector2.ZERO,B.State.UNDER_CONSTRUCTION)
	check(site.add_delivered_material(R.LOG,3),"Record delivered quantity only")
	check(site.set_work_direction(B.WorkDirection.DEMOLISH) and site.ready_for_removal(),"Zero-progress cancellation is immediately terminal")
	check(not site.reserve_construction_material(R.LOG,1),"Demolishing site cannot admit material reservations")
	check(site.get_delivered_amount(R.LOG)==3 and site.get_delivered_amount(R.STONE)==0,"Cancellation cannot invent recipe quantities")
	check(site.set_work_direction(B.WorkDirection.BUILD),"Undo before final removal remains possible")
	site.work_paused=false
	for resource in definition.construction_requirements:
		check(site.add_delivered_material(resource,definition.construction_requirements[resource]-site.get_delivered_amount(resource)),"Seed complete delivered fixture")
	check(site.add_construction_work(60) and site.construction_progress==60,"Initial build progress")
	for cycle in range(10):
		check(site.set_work_direction(B.WorkDirection.DEMOLISH),"Switch to demolition")
		site.work_paused=false
		check(site.add_construction_work(20) and site.construction_progress==40,"Same counter decreases")
		check(not site.can_complete_construction(),"Demolition cannot activate building")
		check(site.set_work_direction(B.WorkDirection.BUILD),"Switch back")
		site.work_paused=false
		check(site.add_construction_work(20) and site.construction_progress==60,"Restoration preserves remaining work")
		check(site.get_delivered_amount(R.LOG)==11,"No repeated material charge/refund")
	check(site.add_construction_work(1000) and site.construction_progress==100,"Upper clamp")
	check(site.complete_construction() and not site.complete_construction(),"Completion once")
	check(site.set_work_direction(B.WorkDirection.DEMOLISH) and site.construction_progress==100 and not site.is_built(),"Operational building begins at full structural work")
	site.work_paused=false
	check(site.add_construction_work(70) and site.construction_progress==30,"Seventy minutes demolished")
	check(site.set_work_direction(B.WorkDirection.BUILD),"Reverse built demolition")
	site.work_paused=false
	check(site.ready_for_structural_work() and site.work_remaining()==70,"Formerly built needs no new material")
	check(site.add_construction_work(70) and site.complete_construction(),"Restoration completes exact missing work")
	check(site.set_work_direction(B.WorkDirection.DEMOLISH),"Second demolition")
	site.work_paused=false
	check(site.add_construction_work(1000) and site.construction_progress==0,"Lower clamp")
	check(not site.add_construction_work(1),"Duplicate terminal callback cannot add work")
	var contents=preload("res://scripts/resource_container.gd").new(&"drain")
	contents.set_capacity(R.LOG,20);contents.add(R.LOG,11)
	contents.reserve_out(R.LOG,1)
	check(not contents.drain_for_removal().ok and contents.get_amount(R.LOG)==11,"Drain refuses outstanding owned reservation")
	contents.release_out(R.LOG,1)
	var nested: Array=[]
	contents.changed.connect(func(_r,_n):nested.append(contents.add(R.LOG,1)))
	var drained: Dictionary=contents.drain_for_removal()
	check(drained.ok and drained.contents[R.LOG]==11 and contents.get_amount(R.LOG)==0,"Physical stock drained once")
	check(nested==[false] and not contents.drain_for_removal().ok,"Closed container rejects reentrant refill and repeat drain")
	var clock=preload("res://scripts/game_time.gd").new();root.add_child(clock);clock.set_process(false)
	var ground=preload("res://scripts/ground_resources.gd").new();root.add_child(ground);ground.setup(clock);ground.enable_stack_mode()
	var cells: Array=[]
	for y in range(20,30):
		for x in range(20,30):cells.append(Vector2i(x,y))
	var allowed:=func(_cell):return true
	var result: Dictionary=ground.place_in_cells(R.LOG,500,cells,allowed)
	check(result.placed==500 and result.discarded==0 and ground.drops.size()==50,"Bulk 500 uses fifty objects, no unit loop")
	var partial: Dictionary=ground.try_place(R.STONE,2,cells[70]);var stack=partial.stack
	check(stack.reserve(&"owner",1),"Existing partial stone claim")
	var id: StringName=stack.id
	result=ground.place_in_cells(R.STONE,8,[cells[70],cells[70],cells[71]],allowed)
	check(result.placed==6 and result.discarded==2 and stack.id==id and stack.reserved_amount(&"owner")==1,"Capacity four, no duplicate cells or lost claim")
	result=ground.place_in_cells(R.FOOD,3,[Vector2.ZERO],allowed)
	check(result.remaining==3 and result.discarded==0,"Invalid domain is technical failure")
	result=ground.place_in_cells(R.FOOD,3,[cells[80]],func(_cell):return false)
	check(result.remaining==0 and result.discarded==3,"Valid exhausted geometry is approved loss")
	for connection in contents.changed.get_connections(): contents.changed.disconnect(connection.callable)
	result=ground.place_in_cells(R.FOOD,3,[cells[81]],func(_cell):return null)
	check(result.remaining==3 and result.discarded==0,"Invalid predicate response is technical failure, not exhaustion")
	var probes: Array=[0]
	var interrupted:=func(_cell):
		probes[0]+=1
		if probes[0]==1: return true
		return null
	var interrupted_cells: Array=[cells[90],cells[91],cells[92]]
	result=ground.place_in_cells(R.LOG,25,interrupted_cells,interrupted)
	check(result.placed==10 and result.remaining==15 and result.discarded==0,"Partial technical failure keeps exact uncommitted remainder")
	var retry: Dictionary=ground.place_in_cells(R.LOG,result.remaining,interrupted_cells,allowed)
	var actual:=0
	for target in interrupted_cells:actual+=ground.get_at(target).amount
	check(actual==25 and retry.placed==15 and retry.remaining==0,"Retry does not duplicate already placed units")
	ground.free();clock.free()
	print("Reversible construction: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
