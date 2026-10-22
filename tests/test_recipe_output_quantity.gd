extends "res://tests/test_recipe_supply.gd"
## Unit promises and indivisible batches; inherited physical fixtures retain F5c paths.
func definition():
	var result=super.definition()
	result.production_recipes[0].inputs={Resources.LOG:2}
	result.production_recipes[0].outputs={Resources.PLANK:2}
	return result
func definitions_and_snapshots() -> void:
	for quantity in [1,2,3]:
		var recipe=Recipe.new({Resources.LOG:2},{Resources.PLANK:quantity},10,A)
		check(recipe.is_valid() and recipe.counted_product()==Resources.PLANK and recipe.output_quantity()==quantity,"Positive integral output quantity "+str(quantity))
	for quantity in [0,-1,1.5,true]:
		var recipe=Recipe.new({Resources.LOG:2},{Resources.PLANK:quantity},10,A)
		var box=ResourceBox.new(&"invalid");box.set_capacity(Resources.LOG,4);box.set_capacity(Resources.PLANK,4);box.add(Resources.LOG,2)
		var batch=Batch.new(&"invalid_batch",recipe,box)
		check(not recipe.is_valid() and recipe.counted_product()==-1 and not batch.prepare("worker") and box.get_reserved_out(Resources.LOG)==0 and box.get_reserved_in(Resources.PLANK)==0,"Invalid output rejected before reservations: "+str(quantity))
	var compound=Recipe.new({Resources.LOG:1},{Resources.PLANK:1,Resources.FOOD:1},10,A)
	check(compound.counted_product()==-1 and compound.output_quantity()==0,"Multiple product kinds remain outside counted modes")
	var target=factory();only(target,A);target.set_production_order(A,1)
	var saved=target.prepare_production_batch("worker")
	target.definition.production_recipes[0].outputs={Resources.FOOD:9}
	target.definition.production_recipes[0].inputs={Resources.STONE:9}
	target.definition.production_recipes[0].work_required=999
	check(saved.outputs=={Resources.PLANK:2} and saved.inputs=={Resources.LOG:2} and saved.work_required==10,"Prepared snapshot does not follow mutable recipe definition")
	check(saved.begin("worker"),"Snapshot begins with original inputs")
	done(target,saved,"worker")
	check(target.resources.get_amount(Resources.PLANK)==2 and target.resources.get_amount(Resources.FOOD)==0 and target.get_recipe_settings(A).produced==2,"Completion and ORDER count snapshot output, not live product")
func output_space() -> void:
	for stock_amount in [8,9,10]:
		var kitchen=Building.new(&"kitchen",Definitions.for_type(Types.FOOD))
		kitchen.consumable_receivers[&"fuel"].reserve_in(Resources.LOG,1)
		kitchen.consumable_receivers[&"fuel"].add_reserved(Resources.LOG,1)
		kitchen.resources.add(Resources.MUSHROOM,1);kitchen.resources.add(Resources.FRIED_MUSHROOM,stock_amount)
		var batch=kitchen.prepare_production_batch("cook")
		check((batch!=null)==(stock_amount==8),"Full output required at stock "+str(stock_amount))
		if batch!=null:
			check(kitchen.resources.get_reserved_in(Resources.FRIED_MUSHROOM)==2 and batch.begin("cook"),"Full output promised before input payment")
			batch.advance("cook",30);check(batch.finish("cook") and not batch.finish("cook") and kitchen.resources.get_amount(Resources.FRIED_MUSHROOM)==10,"Indivisible output fits exactly and publishes once")
		else:check(kitchen.resources.get_amount(Resources.MUSHROOM)==1 and kitchen.resources.get_reserved_out(Resources.MUSHROOM)==0,"Failed start preserves raw input")
	var target=factory();only(target,A);target.resources.set_capacity(Resources.PLANK,4)
	var first=take(target,"one");var second=take(target,"two")
	check(target.claim_production_work("third")==null and target.resources.get_reserved_in(Resources.PLANK)==4,"Two independent double-output batches exhaust four places")
	first.advance("one",4);first.release_worker("one")
	check(first.can_resume() and target.resources.get_reserved_in(Resources.PLANK)==4,"Pause retains the entire output promise")
	check(first.claim("next") and first.begin("next") and target.resources.get_amount(Resources.LOG)==6,"Resume pays no second set of inputs")
	done(target,first,"next");done(target,second,"two")
	check(target.resources.get_amount(Resources.PLANK)==4 and target.resources.get_reserved_in(Resources.PLANK)==0,"Independent commits release only their own promises")
	target=factory();only(target,A);first=take(target,"remove");first.release_worker("remove");target.dispose_production()
	check(first.inputs_spent and first.state==Batch.State.CANCELLED and target.resources.get_amount(Resources.LOG)==8 and target.resources.get_reserved_in(Resources.PLANK)==0,"Removal loses paid WIP without refund and clears full output")
func orders() -> void:
	for amount in [1,2,3,4,5,6]:
		var subject=factory();only(subject,A);check(subject.set_production_order(A,amount),"ORDER units accepted")
		var batches: Array=[];var count:=ceili(amount/2.0)
		for i in count:batches.append(take(subject,"worker_%d" % i))
		check(subject.claim_production_work("extra")==null and subject.get_order_remaining(A)==amount,"Promises prevent another batch before any completion")
		for i in count:done(subject,batches[i],"worker_%d" % i)
		var settings=subject.get_recipe_settings(A)
		check(settings.mode==Mode.OFF and settings.remaining==0 and settings.produced==count*2 and settings.excess==count*2-amount,"Indivisible ORDER "+str(amount))
		subject.resources.try_take(Resources.PLANK,count*2)
		check(subject.get_order_remaining(A)==0,"Physical export cannot reopen an ORDER")
	var target=factory();only(target,A);target.set_production_order(A,3)
	var first=target.prepare_production_batch("first");var second=target.prepare_production_batch("second")
	target.set_production_order(A,1)
	check(first.state==Batch.State.READY and second.state==Batch.State.CANCELLED and target.validate_production_batch(first),"Shrinking keeps the earliest unpaid batch for a positive remainder")
	check(first.begin("first"),"Retained rounded preparation can start");done(target,first,"first")
	target=factory();only(target,A);target.set_production_order(A,5)
	first=take(target,"first");second=take(target,"second")
	var unpaid=target.prepare_production_batch("unpaid")
	target.set_production_order(A,1)
	check(unpaid.state==Batch.State.CANCELLED and first.inputs_spent and second.inputs_spent and not target.can_start_production(A),"Shrink preserves paid WIP and cannot admit extra work")
	first.release_worker("first");first.claim("replacement");first.begin("replacement")
	done(target,first,"replacement");done(target,second,"second")
	check(target.get_recipe_settings(A).produced==4 and target.get_recipe_settings(A).excess==3,"Paid excess may exceed rounding after order shrink")
	target=factory();only(target,A);target.set_production_order(A,1)
	var nested: Array=[]
	target.resources.reservations_changed.connect(func(_resource):nested.append(target.prepare_production_batch("nested")),CONNECT_ONE_SHOT)
	first=take(target,"first")
	check(nested==[null] and target.production_batches.size()==1,"PREPARING already promises two units during synchronous reserve callbacks")
	var observed: Array=[]
	target.resources.changed.connect(func(_resource,_amount):observed.append([target.get_order_remaining(A),target.get_recipe_settings(A).produced,target.can_start_production(A)]),CONNECT_ONE_SHOT)
	done(target,first,"first")
	check(observed==[[0,2,false]],"Output callback sees entire committed quantity and no stale admission")
func maintain() -> void:
	for initial_amount in [0,4,5,6]:
		var subject=factory();only(subject,A);subject.resources.add(Resources.PLANK,initial_amount);subject.set_maintain_target(A,5)
		var count:=ceili(maxi(0,5-initial_amount)/2.0)
		var batches: Array=[]
		for i in count:batches.append(take(subject,"worker_%d" % i))
		check(subject.claim_production_work("extra")==null,"MAINTAIN counts all parallel output once")
		for i in count:done(subject,batches[i],"worker_%d" % i)
		check(subject.resources.get_amount(Resources.PLANK)==(6 if initial_amount<5 else initial_amount) and subject.get_recipe_settings(A).target==5,"MAINTAIN 5 from "+str(initial_amount))
		if initial_amount==0:
			subject.resources.try_take(Resources.PLANK,1);check(not subject.can_start_production(A),"Stock equal to subject still blocks")
			subject.resources.try_take(Resources.PLANK,1);check(subject.can_start_production(A),"Stock below subject reopens a full batch")
	var target=factory();only(target,A);target.set_maintain_target(A,0);check(not target.can_start_production(A),"MAINTAIN zero creates no batch")
	target.set_maintain_target(A,5);target.resources.reserve_in(Resources.PLANK,1)
	var first=take(target,"first");var second=take(target,"second")
	check(not target.can_start_production(A) and target.resources.get_reserved_in(Resources.PLANK)==5,"One external inbound plus two double WIP count once")
	target.set_recipe_mode(A,Mode.OFF)
	check(first.inputs_spent and second.inputs_spent and target.resources.get_reserved_in(Resources.PLANK)==5,"OFF preserves paid double output and foreign inbound")
	done(target,first,"first");done(target,second,"second");target.resources.add_reserved(Resources.PLANK,1)
	check(target.resources.get_amount(Resources.PLANK)==5 and target.resources.get_reserved_in(Resources.PLANK)==0,"OFF WIP finishes entire promised quantity")
func physical_supply() -> void:
	var f=setup_supply_world();var world=f.world;var target=f.target;var actor=f.actors[0]
	target.definition.production_recipes[0].outputs={Resources.PLANK:3}
	world.warehouse_data.resources.add(Resources.LOG,2);target.set_production_order(A,1)
	for trip in range(2):
		check(world._request_work(actor),"Ordinary physical SUPPLY leg "+str(trip))
		var job=world.logistics.get_job(actor.data.id)
		check(job!=null and job.amount==1 and job.resource_type==Resources.LOG,"Quantity input still travels one unit per haul")
		arrive(actor);world.game_time.debug_skip_minutes(10)
		check(actor.data.inventory.amount==1,"One-unit source pickup")
		arrive(actor);world.game_time.debug_skip_minutes(10)
		check(job.state==Haul.State.COMPLETED and actor.data.inventory.amount==0,"Same unit physically unloads once")
	check(target.resources.get_amount(Resources.LOG)==2 and target.supply.deficits(A).is_empty(),"Exactly one two-log kit is complete")
	check(world._request_work(actor),"Supplied generic quantity recipe can start");arrive(actor)
	check(target.resources.get_amount(Resources.LOG)==0 and target.resources.get_reserved_in(Resources.PLANK)==3,"Generic START pays two logs and promises three boards")
	world.game_time.debug_skip_minutes(10)
	check(target.resources.get_amount(Resources.PLANK)==3 and target.get_recipe_settings(A).produced==3 and target.get_recipe_settings(A).excess==2,"One physical batch completes three indivisible units")
	assert_no_promises(target,world,"Generic output complete")
	world.free()
func run() -> void:
	definitions_and_snapshots();output_space();orders();maintain();physical_supply()
	print("Recipe output quantities: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
