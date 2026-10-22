extends "res://tests/test_staged_builder.gd"
const Slot=preload("res://scripts/world_3d/building_slot_3d.gd")
func run() -> void:
	await physical_lumberjack()
	await physical_kitchen()
	await physical_kitchen(true)
	await cancellations()
	await transport_and_removal()
	await outgoing_and_total_refund()
	await ordinary_discard_policy()
	print("Upgrade lifecycle: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func physical_lumberjack() -> void:
	var world=F.create(self);var hut=place(world,T.LUMBERJACK_HUT,Vector3(-20,0,-5));supply(world,hut)
	var builders=workers(world);await drive(world,hut,builders)
	var lumber=world.resident_runtimes[2]
	check(world.player_control.assign_workplace(lumber.data.id,hut.id,P.LUMBERJACK) and world._request_work(lumber),"Actually constructed hut admits normal forestry before upgrade")
	var identity: int=hut.get_instance_id();var container=hut.resources;var assigned: StringName=lumber.data.work_location_id
	await observe(world,hut,"hut_I")
	check(world.start_building_upgrade(hut.id) and hut.is_upgrading() and not world._request_work(lumber),"Upgrade fences normal forestry immediately")
	check(lumber.data.work_location_id==assigned and lumber.get_node("Lumberjack").kind.is_empty(),"Existing forestry is interrupted without dismissal")
	await observe(world,hut,"hut_upgrade_start")
	supply(world,hut)
	await drive(world,hut,builders)
	check(hut.level==2 and hut.is_built() and hut.get_instance_id()==identity and hut.resources==container and hut.resources.get_capacity(R.LOG)==22,"Real builders apply precisely twelve additional materials and180work to same hut")
	var second=world.resident_runtimes[3]
	check(world.player_control.assign_workplace(second.data.id,hut.id,P.LUMBERJACK) and world._request_work(lumber) and world._request_work(second),"Both preserved and new lumberjack resume ordinary forestry")
	check(lumber.get_node("Lumberjack").tree!=second.get_node("Lumberjack").tree,"Workers own independent existing targets")
	await observe(world,hut,"hut_II")
	world.free();await process_frame
func physical_kitchen(cancelled: bool = false) -> void:
	var world=F.create(self);var kitchen=place(world,T.FOOD,Vector3(-12,0,16));supply(world,kitchen)
	var builders=workers(world);await drive(world,kitchen,builders)
	var cook=world.resident_runtimes[2];world.player_control.assign_workplace(cook.data.id,kitchen.id,P.COOK)
	kitchen.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF);kitchen.set_production_order(&"bake_bread",4)
	kitchen.resources.add(R.FLOUR,1)
	for key in [&"fuel",&"water"]:
		var receiver=kitchen.consumable_receivers[key];var resource: int=R.LOG if key==&"fuel" else R.WATER
		receiver.reserve_in(resource,1);receiver.add_reserved(resource,1)
	if not await start_recipe(world,cook):world.free();return
	world.game_time.debug_skip_minutes(11)
	var batch=cook.recipe_work.batch;var fuel: int=kitchen.consumable_stocks[&"fuel"].amount;var water: int=kitchen.consumable_stocks[&"water"].amount
	await observe(world,kitchen,"kitchen_I_paid")
	check(world.start_building_upgrade(kitchen.id) and batch.state==batch.State.PAUSED and batch.progress==11 and kitchen.resources.get_reserved_in(R.BREAD)==2,"World pause retains original paid batch and its output promise")
	check(cook.data.work_location_id==kitchen.id and not cook.recipe_work.has_work(),"Cook remains assigned but does not work during upgrade")
	supply(world,kitchen)
	if cancelled:
		await drive(world,kitchen,builders,func():return kitchen.construction_progress>=41)
		check(world.cancel_building_upgrade(kitchen.id),"Cancel upgrade while retaining the paid production process")
	await drive(world,kitchen,builders)
	check(kitchen.level==(1 if cancelled else 2) and kitchen.consumable_stocks[&"fuel"].amount==fuel and kitchen.consumable_stocks[&"water"].amount==water and kitchen.resources.get_amount(R.BREAD)==0,"Construction never repays or completes the paused recipe")
	if await start_recipe(world,cook):
		check(cook.recipe_work.batch==batch and batch.progress==11,"Physical cook returns to same production process")
		world.game_time.debug_skip_minutes(19)
	check(kitchen.resources.get_amount(R.BREAD)==2 and kitchen.get_recipe_settings(&"bake_bread").produced==2 and kitchen.consumable_stocks[&"fuel"].amount==fuel and kitchen.consumable_stocks[&"water"].amount==water,"Exactly one original output, no duplicate payment on resume")
	await observe(world,kitchen,"kitchen_II_resumed")
	world.free();await process_frame
func cancellations() -> void:
	for when in [&"immediate",&"delivery",&"boundary",&"working",&"last"]:
		var world=F.create(self);var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-12,0,16));var builders=workers(world,1 if when==&"last" else 2)
		var worker=world.resident_runtimes[2];world.player_control.assign_workplace(worker.data.id,hut.id,P.LUMBERJACK)
		check(world.start_building_upgrade(hut.id),"Cancellation fixture starts normal upgrade");supply(world,hut)
		if when==&"delivery":
			check(world._request_work(builders[0]),"Accept real construction supply before cancellation")
		elif when==&"boundary":await drive(world,hut,builders,func():return hut.construction_progress==40 and hut.get_delivered_amount(R.LOG)>0)
		elif when==&"working":await drive(world,hut,builders,func():return hut.construction_progress>=55)
		elif when==&"last":await drive(world,hut,builders,func():return hut.construction_progress>=179)
		var owned: Dictionary=hut.construction_delivered
		for actor in builders:
			if actor.data.inventory.amount>0:owned[actor.data.inventory.resource_type]=int(owned.get(actor.data.inventory.resource_type,0))+actor.data.inventory.amount
		await observe(world,hut,"cancel_%s"%when)
		check(world.cancel_building_upgrade(hut.id),"Cancel project through ordinary local management")
		if hut.is_upgrading():await drive(world,hut,builders)
		for step in 4:await process_frame
		check(not hut.is_upgrading() and hut.is_built() and hut.level==1 and worker.data.work_location_id==hut.id,"Cancel discards only additional project; original I and staff return")
		for resource in [R.LOG,R.PLANK,R.STONE]:
			var dropped: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==resource).reduce(func(total,drop):return total+drop.amount,0)
			check(dropped==int(owned.get(resource,0)) and world.warehouse_data.resources.get_reserved_out(resource)==0 and hut.get_construction_reserved_in(resource)==0,"Exactly actual delivered/carried material refunded once, no remaining claims")
		check(not world.cancel_building_upgrade(hut.id) and builders.all(func(actor):return actor.builder.site==null and actor.data.inventory.amount==0),"Repeated cancellation cannot refund or leak a second time")
		check(world.start_building_upgrade(hut.id),"Cancelled I may start a fresh additional project")
		world.cancel_building_upgrade(hut.id)
		world.free();await process_frame
func transport_and_removal() -> void:
	for carrying in [false,true]:
		var world=F.create(self);var kitchen=F.building(world,T.FOOD,Vector3(16,0,16));var cook=world.resident_runtimes[0]
		world.player_control.assign_workplace(cook.data.id,kitchen.id,P.COOK)
		world.warehouse_data.resources.add(R.LOG,1)
		check(world._request_work(cook),"Ordinary kitchen supply is active before upgrade")
		var job=world.logistics.get_job(cook.data.id)
		if carrying:
			for step in 16000:
				Step.move_3d(cook,.05)
				if cook.data.inventory.amount==1:break
			check(cook.data.inventory.amount==1,"Physical pickup precedes upgrade cancellation")
		var ground: int=world.ground_resources.drops.reduce(func(total,drop):return total+drop.amount,0)
		check(world.start_building_upgrade(kitchen.id) and job.state==job.State.CANCELLED and world.logistics.get_job(cook.data.id)==null,"Start immediately cancels ordinary transport with existing executor")
		check(cook.data.inventory.amount==0 and kitchen.consumable_receivers[&"fuel"].get_reserved_in(R.LOG)==0 and world.warehouse_data.resources.get_reserved_out(R.LOG)==0,"Ordinary cancellation releases both endpoints and cargo")
		check(world.ground_resources.drops.reduce(func(total,drop):return total+drop.amount,0)==ground+(1 if carrying else 0),"Carried unit follows unchanged ordinary ground-drop policy")
		world.cancel_building_upgrade(kitchen.id);world.free();await process_frame
	var demolition_world=F.create(self);var hut=F.building(demolition_world,T.LUMBERJACK_HUT,Vector3(-12,0,16));var builders=workers(demolition_world)
	demolition_world.start_building_upgrade(hut.id);supply(demolition_world,hut)
	await drive(demolition_world,hut,builders,func():return hut.construction_progress>=41)
	check(demolition_world.change_construction_direction(hut.id,true),"D1 demolition during upgrade first cancels its additional project")
	for step in 10:await process_frame
	# Reverse additional work, then the original structure, via the same physical builders.
	await drive(demolition_world,hut,builders)
	for cycle in 4:
		await process_frame
		if hut.state==B.State.REMOVED:break
		if not hut.is_built():await drive(demolition_world,hut,builders)
	check(hut.state==B.State.REMOVED and demolition_world.player_control.get_building(hut.id)==null and hut.level==1 and not hut.is_upgrading(),"Demolition removes original entity only after project cleanup; no late II callback")
	demolition_world.free();await process_frame

func outgoing_and_total_refund() -> void:
	var world=F.create(self);var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-12,0,16))
	hut.resources.add(R.LOG,1)
	var porter=world.resident_runtimes[2];world.player_control.assign_workplace(porter.data.id,world.warehouse_data.id,P.PORTER)
	check(world._request_work(porter),"Ordinary external porter discovers hut output")
	var job=world.logistics.get_job(porter.data.id)
	check(job!=null and job.source_location_id==hut.id,"Accepted outgoing source is the upgrade target")
	check(world.start_building_upgrade(hut.id) and job.state==job.State.CANCELLED and hut.resources.get_reserved_out(R.LOG)==0 and world.warehouse_data.resources.get_reserved_in(R.LOG)==0 and hut.resources.get_amount(R.LOG)==1,"Upgrade cancels outgoing transport without losing unpicked stock or either reserve")
	world.cancel_building_upgrade(hut.id)
	check(world.start_building_upgrade(hut.id),"Same building can start a fresh project after empty cancel")
	for stage in hut.construction_definition().construction_stages:
		for resource in stage.materials:hut.add_delivered_material(resource,stage.materials[resource])
		hut.add_construction_work(stage.work_minutes)
	check(hut.complete_construction() and hut.level==2,"Prepare completed investment for real D1 labour")
	var builders=workers(world)
	check(world.change_construction_direction(hut.id,true),"Level-II building enters unchanged D1 demolition")
	await drive(world,hut,builders)
	check(hut.state==B.State.REMOVED and world.demolition_results.has(hut.id),"Real builders remove improved entity without leftover project")
	var receipt: Dictionary=world.demolition_results[hut.id]
	check(receipt.placed.get(R.LOG,0)==8 and receipt.placed.get(R.PLANK,0)==3 and receipt.placed.get(R.STONE,0)==1 and receipt.discarded.values().all(func(amount):return amount==0),"Refund is floor((base+completed upgrade)/2) per resource plus the one physical stored log")
	world.free();await process_frame

func ordinary_discard_policy() -> void:
	var world=F.create(self);var kitchen=F.building(world,T.FOOD,Vector3(16,0,16));var cook=world.resident_runtimes[0]
	world.player_control.assign_workplace(cook.data.id,kitchen.id,P.COOK);world.warehouse_data.resources.add(R.LOG,1)
	check(world._request_work(cook),"Start real supply for ordinary no-space cancellation policy")
	var job=world.logistics.get_job(cook.data.id)
	for step in 16000:
		Step.move_3d(cook,.05)
		if cook.data.inventory.amount==1:break
	check(cook.data.inventory.amount==1,"Own an actual picked-up log")
	var center: Vector2i=world.ground_resources.cell_from_position(cook.view.get_drop_sim_position())
	for offset in world.ground_resources._ordered_offsets(8):
		var cell: Vector2i=center+offset
		if world._ground_cell_allowed(cell):world.ground_resources.try_place(R.STONE,4,cell)
	var logs: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.LOG).reduce(func(total,drop):return total+drop.amount,0)
	check(world.start_building_upgrade(kitchen.id) and job.state==job.State.CANCELLED and cook.data.inventory.amount==0,"Upgrade starts immediately despite the ordinary exhausted cargo-drop area")
	var executor=world.logistics._executors[cook.data.id]
	check(executor.last_drop_result==preload("res://scripts/cargo_drop_result.gd").Status.DISCARDED and world.ground_resources.drops.filter(func(drop):return drop.resource_type==R.LOG).reduce(func(total,drop):return total+drop.amount,0)==logs,"Existing executor deliberately discards one unit; no B2-specific cargo exception")
	world.cancel_building_upgrade(kitchen.id);world.free();await process_frame
