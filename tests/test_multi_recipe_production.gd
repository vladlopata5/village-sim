extends "res://tests/test_sawmill.gd"
const Batch = preload("res://scripts/production_batch.gd")
const Recipe = preload("res://scripts/production_recipe.gd")
const Building = preload("res://scripts/building_instance.gd")
const Mode = Building.ProductionMode
const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const A = &"test_a"
const B = &"test_b"
const C = &"test_c"

func definition():
	var result = Definitions.for_type(Types.SAWMILL)
	result.production_recipes.clear()
	result.production_recipes.append(Recipe.new({Resources.LOG:1},{Resources.PLANK:1},10,A))
	result.production_recipes.append(Recipe.new({Resources.STONE:1},{Resources.FOOD:1},20,B))
	result.production_recipes.append(Recipe.new({Resources.LOG:1},{Resources.STONE:1},15,C))
	return result

func stock(target: RefCounted) -> void:
	target.resources.set_allowed_resource_types([])
	for resource in Resources.values(): target.resources.set_capacity(resource,40)
	target.resources.add(Resources.LOG,10)
	target.resources.add(Resources.STONE,10)

func factory():
	var data = definition()
	data.worker_capacity=3
	var result = Building.new(&"multi",data)
	stock(result)
	return result

func only(target: RefCounted, recipe_id: StringName) -> void:
	for recipe in target.definition.production_recipes:
		target.set_recipe_mode(recipe.id,Mode.UNLIMITED if recipe.id==recipe_id else Mode.OFF)

func take(target: RefCounted, worker: String):
	var batch = target.claim_production_work(worker)
	check(batch!=null,"Available useful production work can be claimed")
	if batch!=null:
		target.accept_production_batch(batch)
		check(batch.begin(worker),"Claim begins using its own reserved resources")
	return batch

func done(target: RefCounted, batch: RefCounted, worker: String) -> void:
	batch.advance(worker,batch.work_required)
	check(batch.finish(worker) and not batch.finish(worker),"Each independent batch publishes once")
	target.retire_production_batch(batch)

func settings_and_selection() -> void:
	var target = factory()
	var second = Building.new(&"other",target.definition)
	check(target.definition.production_recipes.size()==3 and Definitions.for_type(Types.SAWMILL).production_recipes.size()==1,"Recipe collection; real Sawmill still has only its original recipe")
	var saw = Building.new(&"saw",Definitions.for_type(Types.SAWMILL))
	check(saw.get_recipe_mode(&"sawmill_plank")==Mode.UNLIMITED and saw.production_capacity()==1,"Original balance/default UNLIMITED preserved")
	check(not target.set_recipe_mode(&"missing",Mode.OFF) and not target.set_recipe_mode(A,99) and not target.set_maintain_target(A,-1) and not target.set_production_order(A,-1),"Bad IDs, modes and negative targets rejected")
	check(target.get_recipe_settings(&"missing").is_empty() and target.get_order_remaining(&"missing")==-1,"Invalid reads are safe")
	target.set_recipe_mode(A,Mode.OFF)
	check(second.get_recipe_mode(A)==Mode.UNLIMITED,"Settings belong to instance, not shared definition")
	var snapshot = second.get_recipe_settings(A)
	snapshot.mode=Mode.OFF
	check(second.get_recipe_mode(A)==Mode.UNLIMITED,"Read settings cannot edit the instance indirectly")
	check(target.set_maintain_target(B,0) and not target.can_start_production(B),"MAINTAIN zero produces nothing")
	target.set_production_order(C,2)
	target.set_maintain_target(B,2)
	target.set_recipe_mode(A,Mode.UNLIMITED)
	check(target.select_production_work().recipe_id==C,"ORDER beats MAINTAIN and UNLIMITED")
	target.resources.reserve_out(Resources.LOG,10)
	check(target.select_production_work().recipe_id==B,"Unavailable ORDER is skipped, without an ingredient-wait task")
	target.resources.release_out(Resources.LOG,10)
	target.set_recipe_mode(C,Mode.OFF)
	check(target.select_production_work().recipe_id==B,"MAINTAIN beats UNLIMITED")
	target.set_recipe_mode(B,Mode.OFF)
	check(target.select_production_work().recipe_id==A,"UNLIMITED is final production fallback")
	only(target,A)
	var paused_batch = take(target,"first")
	paused_batch.advance("first",3); paused_batch.release_worker("first")
	target.set_recipe_mode(A,Mode.OFF); target.set_production_order(C,4)
	check(target.select_production_work().kind==&"RESUME" and target.select_production_work().batch==paused_batch,"Paid resume has highest priority even when recipe is OFF")
	check(target.claim_production_work("next")==paused_batch and paused_batch.begin("next") and target.resources.get_amount(Resources.LOG)==9,"Resume spends no second ingredient")
	done(target,paused_batch,"next")
	# Equal-level selection rotates only after accepting the prepared task.
	target=factory()
	for recipe in target.definition.production_recipes: target.set_production_order(recipe.id,5)
	for index in range(100): target.select_production_work("reader")
	check(target._recipe_cursors.is_empty() and target.production_batches.is_empty() and target.get_order_remaining(A)==5,"Read-only availability allocates no batch, changes no order or cursor")
	var failed = target.prepare_production_batch("unaccepted")
	failed.cancel(); target.retire_production_batch(failed)
	check(target.select_production_work().recipe_id==A and target._recipe_cursors.is_empty(),"Cancelled pre-acceptance preparation does not rotate")
	var picks: Array = []
	for index in range(6):
		var worker := "round_%d" % index
		var batch = take(target,worker)
		picks.append(batch.recipe_id)
		done(target,batch,worker)
	check(picks==[A,B,C,A,B,C],"Stable round-robin within equal priority")
	var compound = definition()
	compound.production_recipes[0].outputs[Resources.FOOD]=1
	var multi = Building.new(&"compound",compound); stock(multi)
	check(not multi.set_production_order(A,2) and not multi.set_maintain_target(A,2),"Ambiguous multiple products are explicitly rejected only for quantity modes")
	only(multi,A)
	var generic = take(multi,"multi_output")
	done(multi,generic,"multi_output")
	check(multi.resources.get_amount(Resources.FOOD)==1 and multi.resources.get_amount(Resources.PLANK)==1,"UNLIMITED keeps generic multi-output transactions")

func quantities_and_changes() -> void:
	var target = factory(); only(target,A)
	target.set_production_order(A,2)
	var first = target.prepare_production_batch("first")
	var second = target.prepare_production_batch("second")
	check(first!=null and second!=null and target.claim_production_work("third")==null and target.get_order_remaining(A)==2,"Prepared promises bound ORDER before any spending or completion")
	check(target.claim_production_work("first")==null,"One worker cannot own two batches")
	first.begin("first"); second.begin("second")
	check(target.get_order_remaining(A)==2 and target.resources.get_amount(Resources.LOG)==8,"Start spends two distinct inputs, not the order remainder")
	var observed: Array=[]
	target.resources.changed.connect(func(_resource,_amount): observed.append(target.get_order_remaining(A)),CONNECT_ONE_SHOT)
	done(target,first,"first")
	check(observed==[1] and target.get_order_remaining(A)==1,"Actual output callbacks see the decremented order, without a stale scheduling window")
	target.resources.try_take(Resources.PLANK,1)
	check(target.get_order_remaining(A)==1 and target.claim_production_work("third")==null,"Export does not replenish ORDER; remaining running promise prevents overshoot")
	done(target,second,"second")
	check(target.get_order_remaining(A)==0 and target.get_recipe_mode(A)==Mode.OFF,"Completed order switches to OFF")
	target.set_production_order(A,1)
	check(target.get_order_remaining(A)==1,"New ORDER replaces the previous target")
	# Incoming outputs count once; production's reserve_in must not be counted twice.
	target=factory(); only(target,A); target.set_maintain_target(A,3)
	target.resources.reserve_in(Resources.PLANK,1)
	first=target.prepare_production_batch("first"); second=target.prepare_production_batch("second")
	check(first!=null and second!=null and not target.can_start_production(A) and target.resources.get_reserved_in(Resources.PLANK)==3,"MAINTAIN counts external inbound + two production promises exactly once")
	first.cancel(); target.retire_production_batch(first)
	check(target.can_start_production(A) and target.resources.get_reserved_in(Resources.PLANK)==2,"Own cancellation keeps external and other batch promises")
	second.begin("second"); done(target,second,"second")
	target.resources.add_reserved(Resources.PLANK,1)
	check(target.can_start_production(A),"Internal stock remains below target regardless of unrelated village stock")
	target.resources.add(Resources.PLANK,1)
	check(not target.can_start_production(A),"Internal stock at target stops MAINTAIN")
	target.resources.try_take(Resources.PLANK,1)
	check(target.can_start_production(A),"Export reopens MAINTAIN")
	# Shrinking an order cancels unpaid excess but preserves mandatory paid output.
	target=factory(); only(target,A); target.set_production_order(A,3)
	first=take(target,"first"); second=take(target,"second")
	var unpaid = target.prepare_production_batch("unpaid")
	target.set_production_order(A,1)
	check(unpaid.state==Batch.State.CANCELLED and first.inputs_spent and second.inputs_spent and target.production_batches.size()==2 and target.resources.get_reserved_out(Resources.LOG)==0,"Reduced order cancels only unpaid preparation")
	first.release_worker("first")
	check(target.claim_production_work("replacement")==first and first.begin("replacement"),"Order shrink still permits completing paid paused work")
	done(target,first,"replacement"); done(target,second,"second")
	var result = target.get_recipe_settings(A)
	check(result.mode==Mode.OFF and result.remaining==0 and result.produced==2 and result.excess==1 and target.resources.get_amount(Resources.PLANK)==2,"Mandatory excess is actually produced and explicitly accounted")
	# A new order issued from an output callback must not count an already-issued product.
	target=factory(); only(target,A); target.set_production_order(A,1)
	first=take(target,"first")
	target.resources.changed.connect(func(_resource,_amount): target.set_production_order(A,2),CONNECT_ONE_SHOT)
	done(target,first,"first")
	check(target.get_order_remaining(A)==2 and target.get_recipe_settings(A).produced==0,"Replacement order during output callback excludes that already-finished product")
	# Incoming stock after preparation is revalidated on arrival, not blindly spent.
	target=factory(); only(target,A); target.set_maintain_target(A,1)
	first=target.prepare_production_batch("first")
	target.resources.reserve_in(Resources.PLANK,1)
	check(not target.validate_production_batch(first) and not first.inputs_spent and target.resources.get_reserved_in(Resources.PLANK)==1 and target.resources.get_amount(Resources.LOG)==10,"New inbound promise invalidates unpaid MAINTAIN without harming foreign reserve")
	target=factory(); only(target,A)
	target.resources.reservations_changed.connect(func(_resource): target.set_recipe_mode(A,Mode.OFF),CONNECT_ONE_SHOT)
	check(target.prepare_production_batch("nested")==null and target.production_batches.is_empty() and target.resources.get_amount(Resources.LOG)==10 and target.resources.get_reserved_out(Resources.LOG)==0 and target.resources.get_reserved_in(Resources.PLANK)==0,"OFF inside preparation callback unwinds only the new batch")


	# Reentrant contenders observe PREPARING's full promise before reserve_in exists.
	for mode in [Mode.ORDER,Mode.MAINTAIN]:
		target=factory(); only(target,A); target.set_recipe_mode(A,mode,1)
		var attempts: Array=[]
		target.resources.reservations_changed.connect(func(_resource): attempts.append(target.claim_production_work("nested_contender")==null),CONNECT_ONE_SHOT)
		first=target.prepare_production_batch("owner")
		check(first!=null and attempts==[true] and target.production_batches.size()==1 and target.resources.get_reserved_in(Resources.PLANK)==1,"Reentrant preparation cannot oversubscribe ORDER/MAINTAIN before output reservation")

func capacity_and_cleanup() -> void:
	var target = factory(); only(target,A)
	var first = take(target,"first")
	var second = take(target,"second")
	var third = take(target,"third")
	first.advance("first",3); first.release_worker("first")
	second.advance("second",7)
	check(target.production_batches.size()==3 and target.production_progress==0 and not target.can_start_production(A),"Paid PAUSED process occupies logical capacity; no summed progress")
	check(first.progress==3 and second.progress==7 and third.progress==0,"Independent batch progress")
	check(target.prepare_production_batch("fourth")==null and target.claim_production_work("fourth")==first and not first.claim("fifth"),"Full capacity can resume but cannot add a fourth batch or second claimant")
	first.begin("fourth")
	second.cancel(); target.retire_production_batch(second)
	check(first.progress==3 and third.progress==0 and target.resources.get_reserved_in(Resources.PLANK)==2,"Cancelling one process never frees another's output promise")
	target.dispose_production(); target.dispose_production()
	check(target.production_batches.is_empty() and target.resources.get_reserved_out(Resources.LOG)==0 and target.resources.get_reserved_in(Resources.PLANK)==0 and target.resources.get_amount(Resources.LOG)==7,"Deletion clears all own promises without refunding three paid inputs")
	check(not target.set_production_order(A,3) and target.select_production_work().is_empty() and target.get_recipe_settings(A).is_empty(),"Removed building cannot receive settings or jobs")
	# Scarce inputs/output capacity and repeated unavailable reads remain side-effect free.
	target=factory(); only(target,A)
	target.resources.try_take(Resources.LOG,9)
	first=target.prepare_production_batch("first")
	for index in range(50): target.select_production_work("second")
	check(target.production_batches.size()==1 and target.prepare_production_batch("second")==null and target.resources.get_reserved_out(Resources.LOG)==1,"Last input cannot fund two preparations")
	first.cancel(); target.retire_production_batch(first)
	target.resources.set_capacity(Resources.PLANK,1); target.resources.reserve_in(Resources.PLANK,1)
	check(target.prepare_production_batch("blocked")==null and target.resources.get_amount(Resources.LOG)==1 and target.resources.get_reserved_out(Resources.LOG)==0,"Foreign output claim prevents spending input")

func physical_building(world: Node):
	var data = Building.new(&"parallel_fixture",definition(),Coordinates.to_sim(Vector3(4,0,14)))
	world.buildings.append(data)
	# Assemble test-only authored geometry before assigning any workers.
	world._show_building(data)
	var presentation: Node = world.world_locations.get_view(data.id)
	presentation.layout.free()
	presentation.layout = preload("res://tests/fixtures/parallel_production_layout.tscn").instantiate()
	presentation.add_child(presentation.layout)
	presentation.rebuild_marker_index()
	data.definition.worker_capacity=3
	check(Layouts.validate(presentation.layout,data.definition),"Three authored test WORKER markers match logical capacity")
	world.building_uses.register(data,presentation)
	stock(data)
	return data

func physical_parallel() -> void:
	var world = scene()
	var data = physical_building(world)
	var first = world.resident_runtimes[1]
	var second = world.resident_runtimes[2]
	var third = world.resident_runtimes[3]
	for actor in [first,second,third]: check(world.player_control.assign_workplace(actor.data.id,data.id),"Real profession/workplace assignment accepts one of three test places")
	check(world._request_work(first) and world._request_work(second),"Real SelfLogistics chooses two production actions")
	var batch_a = first.recipe_work.batch
	var batch_b = second.recipe_work.batch
	check(batch_a.recipe_id==A and batch_b.recipe_id==B and data.resources.get_amount(Resources.LOG)==10 and data.resources.get_amount(Resources.STONE)==10,"Distinct selected recipes reserve before movement, without spending")
	walk(first); walk(second)
	check(first.view._marker!=null and second.view._marker!=null and first.view._marker!=second.view._marker and data.resources.get_amount(Resources.LOG)==9 and data.resources.get_amount(Resources.STONE)==9,"Distinct actual WORKER slots start distinct paid batches")
	world.game_time.debug_skip_minutes(5)
	check(batch_a.progress==5 and batch_b.progress==5,"Both real controllers accrue their own progress")
	first.commands.move_to(Vector2(0,500))
	world.game_time.debug_skip_minutes(5)
	check(batch_a.state==Batch.State.PAUSED and batch_a.progress==5 and batch_b.progress==10 and first.view._marker==null,"Paused process frees physical marker, other worker continues")
	check(world._request_work(third),"Third real worker accepts paused process before new recipe")
	walk(third)
	check(third.recipe_work.batch==batch_a and data.resources.get_amount(Resources.LOG)==9,"Third worker resumes same paid ID without new input")
	world.game_time.debug_skip_minutes(5)
	check(batch_a.state==Batch.State.COMPLETED and batch_b.progress==15 and data.resources.get_amount(Resources.PLANK)==1 and data.resources.get_amount(Resources.FOOD)==0,"First independent result completes while second keeps working")
	world.game_time.debug_skip_minutes(5)
	check(data.production_batches.is_empty() and data.resources.get_amount(Resources.FOOD)==1 and data.resources.get_reserved_in(Resources.PLANK)==0 and data.resources.get_reserved_in(Resources.FOOD)==0,"Both physical results release only their own reservations")
	check(data.resources.get_amount(Resources.LOG)==9 and data.resources.get_amount(Resources.STONE)==9 and data.resources.get_amount(Resources.PLANK)==1 and data.resources.get_amount(Resources.FOOD)==1,"Physical ledger: ten inputs of each type, one spent each, one result each")
	world.free()
	world=scene(); data=physical_building(world)
	world.game_time.total_minutes=1015
	var actors: Array = world.resident_runtimes.slice(1,4)
	for actor in actors:
		world.player_control.assign_workplace(actor.data.id,data.id)
		check(actor.recipe_work.request_work(),"One of three actual concurrent batches is accepted")
		walk(actor)
	check(world.building_uses.inside_count(data.id)==3 and data.production_batches.size()==3 and data.prepare_production_batch("extra")==null,"Three simultaneous physical occupants, never a fourth logical process")
	world.game_time.debug_skip_minutes(5)
	check(actors.all(func(actor): return actor.recipe_work.phase==RecipeWork.Phase.WORKING) and world.game_time.get_phase()=="Вечер","Shift change preserves all three physically accepted batches")
	data.set_recipe_mode(A,Mode.OFF)
	check(actors[0].recipe_work.phase==RecipeWork.Phase.WORKING,"OFF does not cancel an already-paid real worker")
	world.logistics.remove_building(data.id)
	world.building_uses.unregister(data.id)
	check(actors.all(func(actor): return actor.recipe_work.phase==RecipeWork.Phase.NONE and actor.view._marker==null) and data.production_batches.is_empty(),"Removing a real multi-worker building clears every executor and marker")
	for resource in Resources.values(): check(data.resources.get_reserved_in(resource)==0 and data.resources.get_reserved_out(resource)==0,"No owned resource promises survive physical removal")
	world.free()
	world=scene(); data=physical_building(world)
	first=world.resident_runtimes[1]; second=world.resident_runtimes[2]
	world.player_control.assign_workplace(first.data.id,data.id); world.player_control.assign_workplace(second.data.id,data.id)
	check(first.recipe_work.request_work() and second.recipe_work.request_work(),"Two real unpaid preparations are accepted")
	var preparation = first.recipe_work.batch
	data.set_recipe_mode(A,Mode.OFF)
	check(preparation.state==Batch.State.CANCELLED and first.recipe_work.phase==RecipeWork.Phase.NONE and not first.intents.has_current_action() and second.recipe_work.phase==RecipeWork.Phase.GOING_TO_WORK,"OFF immediately cancels only its unpaid real route")
	walk(second)
	data.set_production_order(B,0)
	world.game_time.debug_skip_minutes(20)
	check(data.resources.get_amount(Resources.FOOD)==1 and data.get_recipe_settings(B).excess==1 and data.resources.get_reserved_in(Resources.FOOD)==0,"Real paid batch finishes mandatory output even under replacement ORDER zero")
	check(data.resources.get_amount(Resources.LOG)==10 and data.resources.get_reserved_out(Resources.LOG)==0,"Cancelled preparation never consumes its ingredient")
	world.free()

func run() -> void:
	settings_and_selection()
	quantities_and_changes()
	capacity_and_cleanup()
	physical_parallel()
	print("Multi-recipe production: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
