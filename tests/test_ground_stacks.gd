extends SceneTree
const Ground=preload("res://scripts/ground_resources.gd")
const Sources=preload("res://scripts/resource_sources.gd")
const Ref=preload("res://scripts/resource_source_ref.gd")
const R=preload("res://scripts/resource_type.gd").Type
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func removed_reference(ground: Node, cell: Vector2i) -> WeakRef:
	var result: Dictionary=ground.try_place(R.LOG,1,cell)
	var reference: WeakRef=weakref(result.stack)
	ground.remove_drop(result.stack)
	return reference
func run() -> void:
	var clock=preload("res://scripts/game_time.gd").new()
	root.add_child(clock)
	clock.set_process(false)
	var ground=Ground.new()
	root.add_child(ground)
	ground.setup(clock)
	var origin:=Vector2i(128,80)
	check(ground.try_place(R.LOG,1,origin).placed==0,"Strict core requires explicit opt-in")
	check(ground.enable_stack_mode() and not ground.enable_stack_mode(),"Enable once on empty owner only")
	check(ground.create_drop(R.LOG,1,Vector2.ZERO)==null,"Legacy emitter cannot bypass an enabled cell index")
	var added_observer=func(drop):
		check(ground.get_at(drop.cell)==drop and ground.get_by_id(drop.id)==drop and drop.amount<=drop.capacity,"Added observers see both indexes and bounded quantity")
	ground.added.connect(added_observer)
	ground.removed.connect(func(drop):check(ground.get_at(drop.cell)==null and ground.get_by_id(drop.id)==null and drop.reserved_total()==0,"Removed observes absent indexes and no owners"))
	var first=ground.try_place(R.LOG,6,origin)
	var log_stack=first.stack
	var original_id: StringName=log_stack.id
	log_stack.amount=-1
	check(log_stack.amount==6,"Direct writes cannot bypass stack quantity invariants")
	check(log_stack.capacity==10 and log_stack.amount==6 and log_stack.cell==origin,"LOG capacity and cell")
	var point: Vector2=ground.position_from_cell(origin)
	check(log_stack.world_position==point and ground.cell_from_position(point)==origin,"BuildGrid half-world-cell round trip")
	log_stack.world_position=Vector2.ZERO
	check(log_stack.world_position==point,"An indexed stack never moves implicitly")
	log_stack.id=&"changed_id"
	log_stack.resource_type=R.STONE
	check(log_stack.id==original_id and log_stack.resource_type==R.LOG,"Identity and resource type stay stable")
	check(log_stack.reserve(&"a",4) and log_stack.reserve(&"b",2),"Independent partial owners")
	check(not log_stack.reserve(&"a",1) and log_stack.reserved_amount(&"a")==4,"Repeated reservation never inflates ownership")
	check(not log_stack.reserve(&"c",1),"Cannot reserve more than unowned quantity")
	check(not log_stack.release(&"a",5) and not log_stack.release(&"a",0),"Invalid partial release is inert")
	var copy: Dictionary=log_stack.reservations
	copy.clear()
	check(log_stack.reserved_total()==6,"Reservation inspection cannot mutate owned ledger")
	clock.total_minutes+=10
	var more=ground.try_place(R.LOG,9,origin)
	check(more.placed==4 and more.remaining==5 and more.stack==log_stack and log_stack.id==original_id and log_stack.reserved_amount(&"a")==4,"Replenish to capacity without changing identity or owners")
	check(log_stack.created_at==clock.total_minutes,"Replenishment refreshes whole-stack lifetime")
	var renewed: int=log_stack.created_at
	clock.total_minutes+=1
	check(ground.try_place(R.LOG,1,origin).placed==0 and log_stack.created_at==renewed,"A failed full-stack add does not renew lifetime")
	check(ground.try_place(R.STONE,1,origin).placed==0 and ground.get_at(origin)==log_stack,"Another resource cannot replace a cell")
	check(log_stack.release(&"a",2) and log_stack.reserved_amount(&"a")==2 and log_stack.reserved_amount(&"b")==2,"Partial release leaves another owner unchanged")
	check(ground.take_reserved(log_stack,&"a",1) and log_stack.amount==9 and log_stack.reserved_amount(&"a")==1 and log_stack.reserved_amount(&"b")==2,"Partial pickup consumes exactly its own quantity")
	check(not ground.take_reserved(log_stack,&"a",2) and log_stack.amount==9,"Over-pickup is inert")
	var sources=Sources.new()
	sources.bind_ground(ground)
	var reference=Ref.new(Ref.Kind.GROUND,original_id)
	var generation: int=sources.revision
	check(sources.reserve(reference,R.LOG,&"job") and sources.reserved(reference,R.LOG,&"job") and sources.available(reference,R.LOG),"Source adapter sees free units despite other stack owners")
	check(sources.pickup(reference,R.LOG,&"job") and sources.resolve(reference)==log_stack and log_stack.reserved_amount(&"b")==2,"One-unit worker adapter preserves other owners and ID")
	check(sources.revision>generation,"Quantity and reservations invalidate existing offers synchronously")
	log_stack.release(&"a")
	log_stack.release(&"b")
	check(log_stack.reserve(&"last",log_stack.amount),"Reserve remaining quantity for final take")
	var final_observer=func():check(ground.get_by_id(original_id)==null and ground.get_at(origin)==null and log_stack.amount==0,"Final pickup notifications never expose a zero-quantity indexed stack")
	log_stack.availability_changed.connect(final_observer)
	check(ground.take_reserved(log_stack,&"last",log_stack.amount),"Final partial-batch take succeeds")
	log_stack.availability_changed.disconnect(final_observer)
	check(sources.resolve(reference)==null and not ground.take_reserved(log_stack,&"last"),"Old SourceRef and repeated take are invalid")
	var replacement=ground.try_place(R.FOOD,1,origin).stack
	check(replacement.id!=original_id,"A new stack in the old cell has a new ID")
	ground.remove_drop(replacement)
	for resource in R.values():
		var row=ground.try_place(resource,50,origin)
		check(row.placed==(4 if resource==R.STONE else 10) and row.remaining==50-row.placed,"Configured capacity for each resource")
		ground.remove_drop(row.stack)
	var calls: Array=[]
	var allowed=func(cell):calls.append(cell);return true
	check(ground.find_placement(R.LOG,origin,8,allowed)==origin and calls==[origin],"Search stops at the first suitable cell without eager geometry")
	calls.clear()
	var reachable=func(cell):return cell!=origin
	var candidate: Variant=ground.find_placement(R.LOG,origin,2,allowed,reachable)
	check(candidate==origin+Vector2i(0,-1) and calls==[origin,origin+Vector2i(0,-1)],"Unreachable center is skipped; nearest equal-distance order is stable")
	var deny=func(_cell):return false
	calls.clear()
	check(ground.find_placement(R.LOG,origin,2,func(cell):calls.append(cell);return false)==null and calls.size()==13,"Natural search is a finite 13-cell disk")
	calls.clear()
	check(ground.find_placement(R.LOG,origin,8,func(cell):calls.append(cell);return false)==null and calls.size()==197,"Worker search is bounded to 197 geometric candidates")
	var batch=ground.place_near(R.STONE,9,origin,Ground.PlacementMode.NATURAL)
	check(batch.placed==9 and batch.discarded==0 and batch.stack_ids.size()==3,"STONE batch distributes as 4+4+1 across cells")
	check(ground.get_at(origin).amount==4 and ground.get_at(origin+Vector2i(0,-1)).amount==4,"Stable placement order fills origin then nearest")
	for drop in ground.drops.duplicate():ground.remove_drop(drop)
	var overflow=ground.place_near(R.STONE,60,origin,Ground.PlacementMode.NATURAL)
	check(overflow.placed==52 and overflow.discarded==8 and overflow.remaining==0,"Natural overflow destroys only the new unplaced remainder")
	for drop in ground.drops.duplicate():ground.remove_drop(drop)
	var worker=ground.place_near(R.LOG,1,origin,Ground.PlacementMode.WORKER,deny)
	check(worker.placed==0 and worker.discarded==1 and ground.drops.is_empty(),"Approved worker failure returns one discarded unit")
	check(ground.place_near(R.LOG,2,origin,Ground.PlacementMode.WORKER).remaining==2,"Worker policy never silently accepts a multi-unit load")
	check(ground.try_place(R.LOG,1,Vector2i(-1,0)).placed==0,"Out of bounds cannot populate either index")
	# Expiry removes unowned units, never a claim; release after expiry is collected immediately.
	var expiring=ground.try_place(R.LOG,8,origin).stack
	expiring.reserve(&"protected",3)
	clock.total_minutes=expiring.created_at+expiring.lifetime
	ground._on_minute(clock.total_minutes)
	check(ground.get_at(origin)==expiring and expiring.amount==3 and expiring.reserved_amount(&"protected")==3,"Expired stack preserves reserved units only")
	ground._on_minute(clock.total_minutes+100)
	check(expiring.amount==3,"Repeated expiry cannot remove protected units")
	check(ground.take_reserved(expiring,&"protected",1) and expiring.amount==2,"Owner may still pick expired protected units")
	expiring.release(&"protected",1)
	check(expiring.amount==1 and expiring.reserved_amount(&"protected")==1,"Expired released unit is removed without touching the remaining reservation")
	expiring.release(&"protected")
	check(ground.get_by_id(expiring.id)==null and ground.get_at(origin)==null,"Final expired release removes empty identity and cell")
	var refreshed=ground.try_place(R.FOOD,1,origin).stack
	var old_birth: int=refreshed.created_at
	clock.total_minutes+=4000
	ground.try_place(R.FOOD,1,origin)
	ground._on_minute(old_birth+4320)
	check(ground.get_at(origin)==refreshed and refreshed.amount==2,"Refreshed entire stack survives original expiry")
	clock.total_minutes=refreshed.created_at+4320
	ground._on_minute(clock.total_minutes)
	check(ground.get_at(origin)==null,"Unreserved renewed stack eventually expires")
	# Reentrant amount observers see completed mutation and cannot overfill a stack.
	var nested=ground.try_place(R.LOG,5,origin).stack
	var seen:={"once":false}
	nested.availability_changed.connect(func():
		check(nested.reserved_total()<=nested.amount and nested.amount<=nested.capacity,"Reentrant observer sees valid quantity and reservations")
		if not seen.once:
			seen.once=true
			ground.try_place(R.LOG,10,origin))
	ground.try_place(R.LOG,1,origin)
	check(nested.amount==10 and nested.id==ground.get_at(origin).id,"Reentrant replenishment remains bounded and indexed")
	ground.remove_drop(nested)
	var gone:=removed_reference(ground,origin)
	check(gone.get_ref()==null,"Removed stacks are not retained by a bound signal self-cycle")
	var live=ground.try_place(R.LOG,1,origin).stack
	var another=Ground.new()
	root.add_child(another)
	another.setup(clock)
	another.enable_stack_mode()
	check(not another.register_drop(live),"A stack cannot belong to two live registries")
	another.free()
	ground.remove_drop(live)
	# Legacy owner stays uncapped/unmerged and exclusive until E1.2.
	var legacy=Ground.new()
	root.add_child(legacy)
	legacy.setup(clock)
	var old=legacy.create_drop(R.LOG,20,Vector2.ZERO)
	var other=legacy.create_drop(R.STONE,1,Vector2.ZERO)
	check(not legacy.enable_stack_mode() and old!=other and legacy.get_at(legacy.cell_from_position(Vector2.ZERO))==null,"Nonempty legacy world cannot be half-switched to a cell index")
	check(old.reserve(&"one") and old.available_amount()==0 and not old.reserve(&"two"),"Legacy multi-amount drop keeps exclusive admission")
	legacy.free()
	await process_frame
	ground.free()
	clock.free()
	print("Ground stack core: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
