extends "res://tests/test_textile_production.gd"
const Expected=preload("res://tests/construction_recipe_expectations.gd")
const Recipe=preload("res://scripts/production_recipe.gd")
const Slot=preload("res://scripts/world_3d/building_slot_3d.gd")
func finish_plan(place: RefCounted) -> void:
	place.work_paused=false
	for stage in place.construction_definition().construction_stages:
		for resource in stage.materials:check(place.add_delivered_material(resource,stage.materials[resource]),"Actual additional stage material recorded")
		check(place.add_construction_work(stage.work_minutes),"Only supplied stage labour accepted")
	check(place.complete_construction(),"Same instance completes additional plan")
func run() -> void:
	definitions_and_identity()
	paid_and_unlock()
	reused_source_identity()
	await markers_and_ui()
	await reentrant_cancel()
	print("Building upgrades: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func definitions_and_identity() -> void:
	for type in T.values():
		var definition=D.for_type(type)
		var place=B.new(&"existing",definition,Vector2(100,200));place.quarter_turns=3
		var plan=place.next_upgrade()
		if type==T.HOME:
			check(plan!=null and plan.is_valid() and plan.worker_capacity==0,"Residential upgrade has a valid zero-worker target");continue
		if type not in [T.FOOD,T.LUMBERJACK_HUT]:check(plan==null and not place.begin_upgrade(),"No fictitious upgrade for unsupported type");continue
		check(plan.is_valid() and plan.construction_requirements=={R.LOG:4,R.PLANK:6,R.STONE:2} and plan.construction_work_required==180,"Both real upgrades have exact additional cost/time")
		check(plan.construction_stages.map(func(stage):return stage.work_minutes)==[40,60,80],"Upgrade uses concrete B1 order and boundaries")
		var untouched=B.new(&"other",definition)
		var identity: int=place.get_instance_id();var container=place.resources;var footprint: Rect2=place.footprint()
		place.work_area_override_id=&"custom_area"
		var product: int=R.LOG if type==T.LUMBERJACK_HUT else R.BREAD
		if type==T.LUMBERJACK_HUT:place.resources.set_allowed_resource_types([R.LOG]);place.resources.set_capacity(R.LOG,12)
		place.resources.add(product,3)
		var old_capacity: int=place.resources.get_capacity(product)
		var published: Array=[]
		var on_start=func():published.append([place.work_paused,place.construction_progress,place.is_upgrading()])
		place.construction_changed.connect(on_start)
		check(place.begin_upgrade() and not place.begin_upgrade() and not place.is_built(),"One immediate fenced project, no duplicate starts")
		place.construction_changed.disconnect(on_start)
		check(published==[[true,0,true]],"Start publishes one complete fenced project, never half-reset state")
		check(place.resources==container and container.get_amount(product)==3 and container.get_capacity(product)==old_capacity and place.level==1,"Stock, identity and level-I capacity persist throughout work")
		check(not place.reserve_construction_material(R.LOG,1) and not place.reserve_construction_material(R.PLANK,1),"No future material orders at first stone stage")
		finish_plan(place)
		check(place.get_instance_id()==identity and place.resources==container and place.footprint()==footprint and place.quarter_turns==3 and place.work_area_override_id==&"custom_area","Completion preserves entity/container identity, footprint, orientation and work area")
		check(place.level==2 and place.is_built() and place.next_upgrade()==null and not place.complete_construction() and not place.begin_upgrade(),"Exactly one level-II application, no third level/repeated payment")
		check(container.get_amount(product)==3 and container.get_capacity(product)==(22 if type==T.LUMBERJACK_HUT else 20),"Capacity enlargement creates no goods")
		check(untouched.definition==definition and definition.development_level==1 and untouched.level==1,"A shared definition never upgrades another instance")
		check(place.structural_material_amount(R.LOG)==definition.construction_requirements[R.LOG]+4 and place.structural_material_amount(R.PLANK)==definition.construction_requirements.get(R.PLANK,0)+6,"D1 base includes only completed additional investment")
		if type==T.FOOD:check(container.get_capacity(R.FOOD)==20 and place.consumable_stocks[&"fuel"].capacity==20 and place.consumable_stocks[&"water"].capacity==20,"Unrelated FOOD and both numerical capacities unchanged")
	var invalid=B.new(&"invalid",D.for_type(T.FOOD));invalid.definition.upgrades[0].construction_stages[0].work_minutes=0
	check(not invalid.begin_upgrade(),"Invalid additional plan cannot fence or charge a building")
func paid_and_unlock() -> void:
	var definition=D.for_type(T.FOOD);var place=B.new(&"kitchen",definition)
	var extra=Recipe.new({R.FLOUR:1},{R.FOOD:1},7,&"test_unlock")
	definition.upgrades[0].recipes.append(extra)
	check(definition.get_production_recipe(extra.id)==null and place.get_recipe_settings(extra.id).is_empty(),"Test-only recipe unavailable on level I")
	place.set_recipe_mode(&"fried_mushroom",B.ProductionMode.OFF)
	place.set_production_order(&"bake_bread",4)
	place.resources.add(R.FLOUR,1)
	for key in [&"fuel",&"water"]:var receiver=place.consumable_receivers[key];receiver.reserve_in(R.LOG if key==&"fuel" else R.WATER,1);receiver.add_reserved(R.LOG if key==&"fuel" else R.WATER,1)
	var fuel=place.consumable_stocks[&"fuel"];var water=place.consumable_stocks[&"water"]
	var batch=place.claim_production_work("cook");place.accept_production_batch(batch)
	check(batch!=null and batch.begin("cook"),"Prepare and pay ordinary bread batch")
	batch.advance("cook",11);batch.release_worker("cook")
	var fuel_paid: int=fuel.amount;var water_paid: int=water.amount;var settings: Dictionary=place.get_recipe_settings(&"bake_bread")
	check(place.begin_upgrade() and place.select_production_work("cook").is_empty() and place.production_batches==[batch],"No new/resumed production during upgrade; paid process retained")
	check(batch.progress==11 and batch.can_resume() and place.resources.get_reserved_in(R.BREAD)==2,"Paid progress and original output promise survive")
	finish_plan(place)
	check(place.get_recipe_settings(&"bake_bread")==settings and place.get_recipe_mode(&"fried_mushroom")==B.ProductionMode.OFF and place.consumable_stocks[&"fuel"]==fuel and place.consumable_stocks[&"water"]==water,"Orders, OFF, stock objects and quantities preserved")
	check(place.definition.get_production_recipe(extra.id)==extra and place.get_recipe_mode(extra.id)==B.ProductionMode.UNLIMITED,"Recipe unlock uses existing default settings only after final completion")
	var resumed=place.claim_production_work("cook")
	check(resumed==batch and batch.begin("cook") and batch.progress==11 and fuel.amount==fuel_paid and water.amount==water_paid,"Same paid batch resumes without a second payment")
	batch.advance("cook",19);check(batch.finish("cook") and place.resources.get_amount(R.BREAD)==2,"Exactly remaining nineteen minutes issue original output once");place.retire_production_batch(batch)
	place.set_recipe_mode(&"bake_bread",B.ProductionMode.OFF);place.resources.add(R.FLOUR,1)
	check(place.select_production_work("cook").recipe_id==extra.id,"Unlocked test recipe participates in the unchanged planner")
func markers_and_ui() -> void:
	var world=F.create(self);var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-12,0,16))
	var view=world.world_locations.get_view(hut.id);var old_markers: Array=view.get_markers(Slot)
	var worker_slots: Array=old_markers.filter(func(marker):return marker.purpose==Slot.Purpose.WORKER)
	check(worker_slots.size()==2 and world.building_uses.choices(hut.id,Slot.Purpose.WORKER,Vector3.ZERO).size()==1,"Second authored marker exists but is unavailable at I")
	var actor=world.resident_runtimes[0];world.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var assignment: int=actor.data.work_assignment_revision
	world.resident_selection.select_building(hut)
	var card=world.building_card_view();card._preview_upgrade()
	check(card.upgrade_button.visible==false and card.upgrade_confirm.visible and card.upgrade_summary.text.contains("180") and card.upgrade_summary.text.contains("12 → 22"),"Existing card previews exact real characteristics and price")
	check(world.player_control.start_building_upgrade(hut.id).ok and hut.is_upgrading(),"Player management command starts the same building")
	check(actor.data.work_location_id==hut.id and actor.data.profession==P.LUMBERJACK and actor.data.work_assignment_revision==assignment,"Upgrade never clears or reassigns original staff")
	check(card.upgrade_cancel.visible and card.construction_section.visible and card.construction_work.text.contains("этап 1/3"),"Selected card displays B1 progress and cancel during upgrade")
	finish_plan(hut)
	check(view.get_markers(Slot)==old_markers and world.building_uses.choices(hut.id,Slot.Purpose.WORKER,Vector3.ZERO).size()==2,"II enables additional authored point without replacing marker identities")
	var first=world.building_uses.acquire(hut.id,Slot.Purpose.WORKER,"one",Vector3.ZERO);var second=world.building_uses.acquire(hut.id,Slot.Purpose.WORKER,"two",Vector3.ZERO)
	check(first!=null and second!=null and first!=second and first.global_position.distance_to(second.global_position)>=.8 and world.building_uses.acquire(hut.id,Slot.Purpose.WORKER,"three",Vector3.ZERO)==null,"Physical worker occupancy remains exclusive and spatially separate")
	world.building_uses.release(hut.id,first,"one");world.building_uses.release(hut.id,second,"two")
	check(world.player_control.assign_workplace(world.resident_runtimes[1].data.id,hut.id,P.LUMBERJACK) and not card.upgrade_section.visible and card.name_label.text.ends_with("II"),"Additional staff admitted; no inert third-level button")
	var kitchen=F.building(world,T.FOOD,Vector3(16,0,16));var extra=Recipe.new({R.MUSHROOM:1},{R.FOOD:1},9,&"ui_unlock")
	kitchen.definition.upgrades[0].recipes.append(extra);world.resident_selection.select_building(kitchen)
	check(not card.recipe_views.has(extra.id),"Production UI has no unavailable test recipe")
	world.start_building_upgrade(kitchen.id);finish_plan(kitchen)
	check(card.recipe_views.has(extra.id) and card.recipe_views[extra.id].recipe==extra,"Existing recipe UI discovers newly unlocked test configuration")
	world.resident_selection.select_building(world.warehouse_data)
	check(not card.upgrade_section.visible,"Other buildings expose no fictitious upgrade")
	world.free();await process_frame

func reentrant_cancel() -> void:
	var world=F.create(self);var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-12,0,16))
	var actor=world.resident_runtimes[0];world.player_control.assign_profession(actor.data.id,P.BUILDER)
	world.warehouse_data.resources.add(R.STONE,2)
	check(world.start_building_upgrade(hut.id),"Reentrant fixture starts upgrade")
	var calls: Array=[0]
	var cancel=func():
		if hut.is_upgrading() and hut.get_construction_reserved_in(R.STONE)>0 and calls[0]==0:
			calls[0]+=1
			world.cancel_building_upgrade(hut.id)
	hut.construction_changed.connect(cancel)
	world._request_work(actor)
	await process_frame;await process_frame
	hut.construction_changed.disconnect(cancel)
	check(calls[0]==1 and hut.is_built() and hut.level==1 and not hut.is_upgrading() and actor.builder.site==null,"Cancellation inside material reservation safely settles before restoration")
	check(world.warehouse_data.resources.get_reserved_out(R.STONE)==0 and hut._construction_reserved_in.is_empty() and actor.data.inventory.amount==0,"Nested cancellation leaves no source/project claim or duplicate cargo")
	world.free();await process_frame

func reused_source_identity() -> void:
	var provider=preload("res://scripts/resource_sources.gd").new()
	var original=B.new(&"reused",D.for_type(T.LUMBERJACK_HUT));original.resources.set_capacity(R.LOG,12);original.resources.add(R.LOG,1)
	var replacement=B.new(&"reused",D.for_type(T.LUMBERJACK_HUT));replacement.resources.set_capacity(R.LOG,12);replacement.resources.add(R.LOG,2);replacement.resources.reserve_out(R.LOG,1)
	var reference=preload("res://scripts/resource_source_ref.gd").new(preload("res://scripts/resource_source_ref.gd").Kind.CONTAINER,original.id)
	provider.buildings[original.id]=original
	check(provider.reserve(reference,R.LOG,&"builder"),"Additional project owns a unit in the original source")
	provider.buildings[original.id]=replacement
	check(not provider.reserved(reference,R.LOG,&"builder") and not provider.pickup(reference,R.LOG,&"builder"),"Same ID never transfers a material claim to a replacement source")
	check(provider.reserve(reference,R.LOG,&"new_owner") and provider.reserved(reference,R.LOG,&"new_owner"),"Replacement may own a different unit while the old object awaits cleanup")
	provider.release(reference,R.LOG,&"new_owner")
	provider.release(reference,R.LOG,&"builder")
	check(original.resources.get_reserved_out(R.LOG)==0 and replacement.resources.get_reserved_out(R.LOG)==1 and original.resources.get_amount(R.LOG)==1 and replacement.resources.get_amount(R.LOG)==2,"Cleanup releases the original obligation and preserves replacement stock/foreign claim")
