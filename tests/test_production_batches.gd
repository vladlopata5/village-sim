extends "res://tests/test_sawmill.gd"
const Batch = preload("res://scripts/production_batch.gd")
const Recipe = preload("res://scripts/production_recipe.gd")
const Building = preload("res://scripts/building_instance.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Haul = preload("res://scripts/haul_job.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type

func domain() -> void:
	var building = Building.new(&"batch_test",Definitions.for_type(Types.SAWMILL))
	building.resources.set_capacity(Resources.LOG,3)
	building.resources.set_capacity(Resources.PLANK,2)
	building.resources.add(Resources.LOG,1)
	var batch = building.prepare_production_batch("first")
	check(batch!=null and batch.recipe_id==&"sawmill_plank" and batch.state==Batch.State.READY,"Stable recipe ID and prepared batch")
	check(building.resources.get_amount(Resources.LOG)==1 and building.resources.get_reserved_out(Resources.LOG)==1 and building.resources.get_reserved_in(Resources.PLANK)==1 and not batch.inputs_spent,"Preparation holds inputs and future space, without spending")
	check(building.prepare_production_batch("second")==null and not batch.claim("second"),"One slot and batch have exactly one claimant")
	check(batch.begin("first") and not batch.begin("first") and building.resources.get_amount(Resources.LOG)==0 and building.resources.get_amount(Resources.PLANK)==0,"Start spends once and emits no product")
	batch.advance("first",12)
	batch.release_worker("first")
	batch.advance("first",500)
	check(batch.can_resume() and batch.progress==12 and building.resources.get_reserved_in(Resources.PLANK)==1,"Paused batch freezes, retaining promised output")
	check(batch.claim("second") and batch.begin("second") and building.resources.get_amount(Resources.LOG)==0,"A different owner resumes without a second ingredient")
	batch.advance("second",18)
	var nested: Array = []
	building.resources.changed.connect(func(_resource,_amount): nested.append(batch.finish("second")),CONNECT_ONE_SHOT)
	check(batch.finish("second") and nested==[false] and not batch.finish("second"),"Reentrant and repeated finish cannot publish again")
	check(building.resources.get_amount(Resources.PLANK)==1 and building.resources.get_reserved_in(Resources.PLANK)==0 and building.resources.get_reserved_out(Resources.LOG)==0,"Only one finished product, no owned reservations")
	var identity: StringName = batch.id
	building.retire_production_batch(batch)
	building.resources.add(Resources.LOG,1)
	var next = building.prepare_production_batch("third")
	check(next.id!=identity and batch.id==identity and building.production_batches.size()==1,"ID is stable and never reused for the next batch")
	next.release_worker("third")
	building.retire_production_batch(next)
	check(building.resources.get_amount(Resources.LOG)==1 and building.resources.get_reserved_out(Resources.LOG)==0 and building.resources.get_reserved_in(Resources.PLANK)==0 and building.production_batches.is_empty(),"Pre-start cancellation returns reservations, never spends input")
	# A generic multi-input/output definition, isolated from all gameplay definitions.
	var box = ResourceBox.new(&"generic")
	for resource in Resources.values(): box.set_capacity(resource,4)
	box.add(Resources.LOG,1); box.add(Resources.STONE,1)
	box.reserve_in(Resources.FOOD,1) # An unrelated pre-existing incoming promise.
	var recipe = Recipe.new({Resources.LOG:1,Resources.STONE:1},{Resources.PLANK:1,Resources.FOOD:1},5,&"generic_test")
	var generic = Batch.new(&"generic:1",recipe,box)
	check(generic.prepare("worker") and generic.begin("worker"),"The same mechanism supports recipe data beyond one log/plank")
	check(box.get_amount(Resources.LOG)==0 and box.get_amount(Resources.STONE)==0 and box.get_amount(Resources.FOOD)==0,"All ingredients are consumed before any product exists")
	generic.advance("worker",5)
	check(generic.finish("worker") and box.get_amount(Resources.PLANK)==1 and box.get_amount(Resources.FOOD)==1 and box.get_reserved_in(Resources.FOOD)==1,"Generic output transaction preserves another incoming reservation")
	# Output admission fails after inputs were reserved: rollback affects only this process.
	box = ResourceBox.new(&"full_output")
	box.set_capacity(Resources.LOG,2); box.set_capacity(Resources.PLANK,1)
	box.add(Resources.LOG,2); box.reserve_out(Resources.LOG,1); box.reserve_in(Resources.PLANK,1)
	var blocked = Batch.new(&"blocked",Definitions.for_type(Types.SAWMILL).production_recipe,box)
	check(not blocked.prepare("worker") and box.get_amount(Resources.LOG)==2 and box.get_reserved_out(Resources.LOG)==1 and box.get_reserved_in(Resources.PLANK)==1,"Failed output reservation rolls back own inputs, preserving foreign promises")
	# Cancellation during the atomic input transaction observes already-spent inputs.
	box = ResourceBox.new(&"start_callback")
	box.set_capacity(Resources.LOG,1); box.set_capacity(Resources.PLANK,1); box.add(Resources.LOG,1)
	var interrupted = Batch.new(&"interrupted",Definitions.for_type(Types.SAWMILL).production_recipe,box)
	interrupted.prepare("worker")
	box.changed.connect(func(_resource,_amount): interrupted.release_worker("worker"),CONNECT_ONE_SHOT)
	check(not interrupted.begin("worker") and interrupted.state==Batch.State.PAUSED and interrupted.inputs_spent and box.get_amount(Resources.LOG)==0 and box.get_reserved_in(Resources.PLANK)==1,"Interruption immediately after consumption pauses a paid batch")
	interrupted.cancel(); interrupted.cancel()
	check(box.get_amount(Resources.LOG)==0 and box.get_reserved_in(Resources.PLANK)==0,"Repeated destruction never refunds spent input or releases twice")

func paused_replacement() -> void:
	var world = scene()
	var saw = place(world)
	finish(saw)
	var first = world.resident_runtimes[1]
	var second = world.resident_runtimes[2]
	world.player_control.assign_workplace(first.data.id,saw.id)
	saw.resources.add(Resources.LOG,1)
	var serial: int = saw._next_batch_id
	var offers_work := true
	for index in range(100): offers_work = first.recipe_work.has_work() and offers_work
	check(offers_work and saw.production_batches.is_empty() and saw._next_batch_id==serial,"100 read-only has_work calls never create a batch")
	check(world._request_work(first),"Prepared real route is accepted")
	var before = first.recipe_work.batch
	check(before.state==Batch.State.READY and saw.resources.get_amount(Resources.LOG)==1,"Walking to WORKER is not input consumption")
	first.commands.move_to(Vector2(0,500))
	check(before.state==Batch.State.CANCELLED and saw.production_batches.is_empty() and saw.resources.get_amount(Resources.LOG)==1 and saw.resources.get_reserved_in(Resources.PLANK)==0,"Player cancellation before arrival releases preparation")
	first.commands.cancel_current(); first.intents.abort_current(first.intents.current_intent)
	begin(world,first)
	var saved = first.recipe_work.batch
	minute(world,first,9)
	first.commands.move_to(Vector2(0,500))
	check(saved.state==Batch.State.PAUSED and saved.progress==9 and saved.inputs_spent and saved.worker_id.is_empty() and first.view._marker==null,"Real interrupted work leaves paid process and frees physical slot")
	world.game_time.debug_skip_minutes(5)
	check(saved.progress==9 and saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==1,"No worker means no progress; output remains reserved")
	world.player_control.assign_profession(first.data.id,Profession.NONE)
	world.player_control.assign_workplace(second.data.id,saw.id)
	saw.resources.add(Resources.LOG,1)
	saw.resources.add(Resources.PLANK,11)
	check(second.self_logistics.task().kind==&"PRODUCTION" and second.recipe_work.has_work(),"Resume beats new production/supply/export even with no unreserved output space")
	begin(world,second)
	check(second.recipe_work.batch==saved and saw.resources.get_amount(Resources.LOG)==1 and saw.resources.get_reserved_in(Resources.PLANK)==1,"Different physical worker inherits ID/progress and the same output promise")
	minute(world,second,21)
	check(saved.state==Batch.State.COMPLETED and saw.production_batches.is_empty() and saw.resources.get_amount(Resources.PLANK)==12 and saw.resources.get_reserved_in(Resources.PLANK)==0,"Resumed batch completes exactly once")
	var porter = world.resident_runtimes[0]
	var candidate = Candidate.new()
	candidate.source=saw; candidate.source_ref=Source.new(Source.Kind.CONTAINER,saw.id)
	candidate.destination=world.warehouse_data; candidate.resource_type=Resources.PLANK
	var job = world.logistics._claim_delivery(porter.data,candidate)
	check(job!=null and world.logistics.start_claimed_job(job,porter.data.id),"Ordinary Porter accepts completed output")
	if job!=null:
		walk(porter,&"haul_source"); walk(porter)
		check(job.state==Haul.State.COMPLETED and saw.resources.get_amount(Resources.PLANK)==11 and world.warehouse_data.resources.get_amount(Resources.PLANK)==1,"Produced board follows the real existing delivery executor")
	check(saw.resources.get_amount(Resources.LOG)==1 and saved.inputs_spent and saw.resources.get_amount(Resources.PLANK)+world.warehouse_data.resources.get_amount(Resources.PLANK)==12,"Ledger: two inputs received, one spent; eleven fixture boards plus one product, one delivery")
	world.free()

func callbacks_and_removal() -> void:
	for stage in ["reserve","consume","consume_remove","finish_remove","prepare_remove","running_remove","paused_remove","input_lost","hunger","shift_prepare"]:
		var world = scene()
		var saw = place(world); finish(saw)
		var actor = world.resident_runtimes[1]
		world.player_control.assign_workplace(actor.data.id,saw.id)
		saw.resources.add(Resources.LOG,1)
		if stage in ["reserve","prepare_remove"]:
			saw.resources.reservations_changed.connect(func(_resource):
				if stage=="reserve": actor.commands.move_to(Vector2(0,500))
				else: world.logistics.remove_building(saw.id),CONNECT_ONE_SHOT)
			check(not world._request_work(actor) and saw.resources.get_amount(Resources.LOG)==1 and saw.resources.get_reserved_out(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0 and saw.production_batches.is_empty(),"No input spent and no dangling preparation on "+stage)
		elif stage=="consume":
			check(world._request_work(actor),"Route exists before start callback")
			var batch = actor.recipe_work.batch
			saw.resources.changed.connect(func(resource,_amount):
				if resource==Resources.LOG: actor.commands.move_to(Vector2(0,500)),CONNECT_ONE_SHOT)
			walk(actor)
			check(batch.inputs_spent and batch.state==Batch.State.PAUSED and batch.progress==0 and saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==1,"Start callback interruption spends once and retains unfinished output")
		elif stage=="shift_prepare":
			world.game_time.total_minutes=1019
			saw.resources.reservations_changed.connect(func(_resource): world.game_time.debug_skip_minutes(1),CONNECT_ONE_SHOT)
			check(not world._request_work(actor) and saw.resources.get_amount(Resources.LOG)==1 and saw.production_batches.is_empty() and saw.resources.get_reserved_out(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0,"Shift ending inside preparation rejects a not-yet-accepted action without spending")
		elif stage in ["consume_remove","finish_remove"]:
			check(world._request_work(actor),"Accepted route before reentrant removal")
			var batch = actor.recipe_work.batch
			if stage=="consume_remove":
				saw.resources.changed.connect(func(_resource,_amount): world.logistics.remove_building(saw.id),CONNECT_ONE_SHOT)
			walk(actor)
			if stage=="finish_remove":
				saw.resources.changed.connect(func(_resource,_amount): world.logistics.remove_building(saw.id),CONNECT_ONE_SHOT)
				minute(world,actor,30)
			check(batch.inputs_spent and saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0 and saw.resources.get_reserved_out(Resources.LOG)==0 and saw.production_batches.is_empty() and actor.recipe_work.phase==RecipeWork.Phase.NONE,"Reentrant removal leaves no resource/worker claims: "+stage)
			check(saw.resources.get_amount(Resources.PLANK)==(1 if stage=="finish_remove" else 0),"Only a fully completed transaction publishes its single product: "+stage)
		elif stage=="hunger":
			begin(world,actor); minute(world,actor,4)
			var batch = actor.recipe_work.batch
			actor.decision._deciding=false
			actor.data.hunger=100
			check(actor.recipe_work.phase==RecipeWork.Phase.NONE and batch.state==Batch.State.PAUSED and batch.progress==4 and actor.intents.forced_priority>0 and saw.resources.get_reserved_in(Resources.PLANK)==1,"Critical hunger still interrupts accepted production and protects paid progress")
		elif stage=="input_lost":
			check(world._request_work(actor),"Prepared route before reservation loss")
			saw.resources.release_out(Resources.LOG,1); saw.resources.try_take(Resources.LOG,1)
			walk(actor)
			check(actor.recipe_work.phase==RecipeWork.Phase.NONE and saw.production_batches.is_empty() and saw.resources.get_amount(Resources.PLANK)==0 and saw.resources.get_reserved_in(Resources.PLANK)==0,"Lost input cannot create paid progress or a phantom output")
		else:
			begin(world,actor); minute(world,actor,5)
			var batch = actor.recipe_work.batch
			if stage=="paused_remove": actor.commands.move_to(Vector2(0,500))
			world.logistics.remove_building(saw.id)
			world.building_uses.unregister(saw.id)
			check(batch.state==Batch.State.CANCELLED and batch.inputs_spent and saw.production_batches.is_empty() and saw.resources.get_reserved_in(Resources.PLANK)==0 and saw.resources.get_amount(Resources.LOG)==0 and saw.resources.get_amount(Resources.PLANK)==0 and actor.recipe_work.phase==RecipeWork.Phase.NONE,"Removal terminates paid WIP without refund, reserve or active worker: "+stage)
		world.free()

func shift_boundaries() -> void:
	var world = scene()
	var saw = place(world); finish(saw)
	var actor = world.resident_runtimes[1]
	world.player_control.assign_workplace(actor.data.id,saw.id)
	saw.resources.add(Resources.LOG,2)
	world.game_time.total_minutes=1010
	begin(world,actor)
	world.game_time.debug_skip_minutes(10)
	check(actor.schedule.get_phase()=="Вечер" and actor.recipe_work.phase==RecipeWork.Phase.WORKING and actor.data.activity==Activity.WORKING and actor.view._marker!=null,"Real day boundary tracks phase but retains accepted physical production")
	world.game_time.debug_skip_minutes(20)
	check(actor.recipe_work.phase==RecipeWork.Phase.NONE and saw.resources.get_amount(Resources.PLANK)==1 and saw.resources.get_amount(Resources.LOG)==1 and not actor.recipe_work.request_work(),"Accepted board finishes in evening; a new cycle is rejected")
	world.free()
	# A task accepted in daytime keeps its route, without spending before arrival.
	world = scene(); saw = place(world); finish(saw)
	actor = world.resident_runtimes[1]
	world.player_control.assign_workplace(actor.data.id,saw.id)
	saw.resources.add(Resources.LOG,2)
	world.game_time.total_minutes=1019
	check(world._request_work(actor),"Production route accepted before day ends")
	world.game_time.debug_skip_minutes(361)
	check(actor.schedule.get_phase()=="Ночь" and actor.recipe_work.phase==RecipeWork.Phase.GOING_TO_WORK and saw.resources.get_amount(Resources.LOG)==2,"Accepted route survives phases, but consumes nothing remotely")
	walk(actor)
	check(actor.recipe_work.phase==RecipeWork.Phase.WORKING and saw.resources.get_amount(Resources.LOG)==1,"Only arrival starts the previously accepted batch")
	world.game_time.debug_skip_minutes(30)
	check(saw.resources.get_amount(Resources.PLANK)==1 and not actor.recipe_work.request_work(),"No new production is accepted at night")
	actor.decision._deciding=false
	actor.decision.request_decision("after_batch")
	await preload("res://tests/ai_queue_fixture.gd").drain(world)
	check(actor.data.activity==Activity.SLEEPING or actor.intents.current_intent.reason_id in [&"night_home",&"night_outdoor"],"After completing accepted production normal night schedule resumes")
	world.free()

func run() -> void:
	domain()
	paused_replacement()
	callbacks_and_removal()
	await shift_boundaries()
	print("Production batches: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
