extends "res://tests/test_sleep_fallback.gd"
const Slot=preload("res://scripts/world_3d/building_slot_3d.gd")
const Layouts=preload("res://scripts/world_3d/building_layouts_3d.gd")
const Geometry=preload("res://scripts/world_3d/world_geometry.gd")
func run() -> void:
	domain_upgrade()
	await inhabited_upgrade()
	await cancellation_stages()
	await second_unit_fallback()
	print("HOME upgrades: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func finish_upgrade(home: RefCounted) -> void:
	home.work_paused=false
	for stage in home.construction_definition().construction_stages:
		for resource in stage.materials:check(home.add_delivered_material(resource,stage.materials[resource]),"Upgrade accepts actual supplied stage material")
		check(home.add_construction_work(stage.work_minutes),"Only supplied stage labour applied")
	check(home.complete_construction(),"Existing B2 completes residential target")
func domain_upgrade() -> void:
	var home=B.new(&"home",D.for_type(T.HOME));var first=home.households[0];var plan=home.next_upgrade()
	var old_definition=home.definition;var footprint: Rect2=home.footprint()
	check(plan.is_valid() and plan.worker_capacity==0 and plan.household_count==2 and plan.housing_capacity==8,"Residential target derives eight places from two balance-sized units")
	check(plan.construction_requirements=={R.LOG:4,R.PLANK:6,R.BRICK:4} and plan.construction_work_required==180 and plan.max_builders==2,"Exact approved additional clay-brick recipe and labour")
	check(plan.construction_stages.map(func(stage):return stage.work_minutes)==[60,60,60] and plan.construction_stages.map(func(stage):return stage.materials)==[{R.LOG:4},{R.BRICK:4},{R.PLANK:6}],"Physical stages retain approved order")
	var invalid=preload("res://scripts/building_upgrade.gd").new()
	invalid.construction_requirements=plan.construction_requirements;invalid.construction_stages=plan.construction_stages
	invalid.worker_capacity=0
	check(not invalid.is_valid(),"Zero workers without a residential target remain invalid")
	invalid.household_count=2;invalid.capacities={R.LOG:1}
	check(not invalid.is_valid(),"Residential target cannot smuggle production/storage")
	var pc=Player.new();var population: Array=[]
	for index in 9:population.append(Data.new("tenant_%d"%index,"Житель",30))
	pc.setup(population,[home])
	for index in 4:check(pc.assign_household(population[index].id,first.id),"Initial residents use original unit")
	check(home.begin_upgrade() and home.is_housing_usable() and not home.is_built() and home.households==[first],"B2 fences new operation while keeping original housing")
	check(pc.get_home(population[0].id)==home and pc.clear_household(population[3].id),"Existing housing lookup and eviction remain usable during B2")
	check(not pc.assign_household(population[4].id,first.id) and not pc.assign_home(population[4].id,home.id) and pc.household_assignment_error(population[4].id,first.id).contains("улучшение"),"Both APIs reject new admission even into a vacancy")
	var published: Array=[]
	var callback=func():
		if home.level==2:
			published.append([home.households.size(),home.housing_capacity(),home.definition.housing_capacity,home.is_built()])
			check(home.households[0]==first and home.households.size()==2 and home.housing_capacity()==8,"Every final callback observes atomic household installation")
	home.construction_changed.connect(callback)
	finish_upgrade(home);home.ensure_households();home.complete_construction()
	check(published==[[2,8,8,true]] and home.households[0]==first and home.households[1].id==Household.id_for(home.id,2),"Exactly one final state; stable first object and unique second identity")
	check(pc.get_household_occupants(home.households[1].id).is_empty() and home.households[1].capacity==4,"Second unit starts empty")
	for index in range(4,8):check(pc.assign_household(population[index].id,home.households[1].id),"Second household has four independent places")
	check(not pc.assign_household(population[8].id,home.households[1].id) and not pc.assign_household(population[0].id,home.households[1].id) and population[0].household_id==first.id,"Full target rejects ninth resident and preserves failed move")
	check(pc.assign_household(population[4].id,first.id) and pc.assign_household(population[3].id,home.households[1].id),"Explicit movement between units uses ordinary capacity checks")
	check(home.footprint()==footprint and home.definition.footprint_cells==Vector2i(6,4) and old_definition.housing_capacity==4 and home.definition.worker_capacity==0 and home.definition.production_recipes.is_empty() and home.resources.get_total_amount()==0,"Same footprint, shared original definition unchanged, no invented job or stock")
	home.construction_changed.disconnect(callback)
func supply(world: Node,site: RefCounted) -> void:
	# The real warehouse must grant a quota to this new construction good.
	check(world.warehouse_data.resources.set_category_quota(C.PLANK,40) and world.warehouse_data.resources.set_category_quota(C.BRICK,10),"Test warehouse allocates clay-brick capacity without changing balance")
	for resource in site.construction_definition().construction_requirements:
		check(world.warehouse_data.resources.add(resource,site.get_required_amount(resource)),"Exact construction stock added through ordinary capacity checks")
func admit(world: Node,home: RefCounted,unit: RefCounted,person: RefCounted) -> bool:
	world.resident_selection.select_building(home)
	world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(unit.id)
	var button: Button=world.building_card_view().household_views[unit.id].button
	if DisplayServer.get_name()=="headless":button.pressed.emit()
	else:
		await process_frame;F.click(self,button);await process_frame
	world.settlement_panel.activate_row(person.id)
	return world.assignment_dialog.execute(&"home")
func quiet(world: Node) -> void:
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false);actor.schedule.work_decision=Callable()
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
func claim_snapshot(world: Node,home: RefCounted) -> Array:
	return world.building_uses.view(home.id).get_markers(Slot).filter(func(m):return m.purpose==Slot.Purpose.SLEEP and not m.occupant.is_empty()).map(func(m):return {"id":m.local_id,"household":m.household_index,"owner":m.occupant,"position":str(m.global_position)})
func sleep_group(actors: Array) -> void:
	for actor in actors:actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
func inhabited_upgrade() -> void:
	var world=F.create(self);await physics_frame;await process_frame
	check(world.debug_spawn.spawn_residents(Vector3(-18,0,24),6,P.NONE).created==6,"Real ten-person world has two builders and eight tenants")
	quiet(world)
	var home=place(world,T.HOME,Vector3(-12,0,16));supply(world,home)
	var builders=workers(world);await drive(world,home,builders)
	world.game_time.total_minutes=420 # Begin the controlled overlap before normal evening wake/phase transitions.
	var tenants: Array=world.resident_runtimes.slice(2,10);var pc=world.player_control;var first=home.households[0]
	for index in 4:check(await admit(world,home,first,tenants[index].data),"Original four residents assigned through actual household UI")
	sleep_group(tenants.slice(0,4))
	check(claim_snapshot(world,home).size()==4 and tenants.slice(0,4).all(func(a):return a.data.activity==Activity.SLEEPING and a.data.current_sleep_quality==1.0),"Four actual portal arrivals sleep in unit one")
	var original: Array=claim_snapshot(world,home);var markers: Array=world.building_uses.view(home.id).get_markers(Slot);var footprint: Array=world.build_grid.occupied_cells(home.id)
	world.resident_selection.select_building(home);var card=world.building_card_view()
	world.game_ui.info_panel.select_tab(&"info")
	card._preview_upgrade()
	check(card.upgrade_summary.text.contains("180") and card.upgrade_summary.text.contains("4 → 8"),"Existing B2 UI previews residential capacity and labour")
	await observe(world,home,"home_I_sleep")
	card.upgrade_confirm.pressed.emit()
	check(home.is_upgrading() and not home.work_paused and claim_snapshot(world,home)==original,"Starting B2 neither evicts sleepers nor waits for morning")
	check(card.available_tabs()==[&"info",first.id] and card.household_views[first.id].button.disabled and card.household_views[first.id].title.text.contains("закрыты"),"Existing unit stays visible with an explicit admission block")
	check(not pc.assign_household(tenants[4].data.id,first.id),"Domain admission blocked independently of disabled button")
	# Wake/re-enter one original tenant while the additional project exists.
	tenants[0].schedule._on_phase_changed("Утро");tenants[0].schedule._on_phase_changed("Ночь");finish_sleep(tenants[0])
	check(claim_snapshot(world,home).size()==4 and world.building_uses.occupied_by(home.id,tenants[0].data.id,3),"Original resident can return during B2 through the unchanged entrance")
	supply(world,home)
	await observe(world,home,"inhabited_upgrade")
	await drive(world,home,builders,func():return home.get_delivered_amount(R.LOG)>0)
	await observe(world,home,"partial_delivery")
	await drive(world,home,builders)
	if not home.is_built():return # Report the preceding bounded physical-drive failure without cascading array errors.
	check(home.level==2 and home.households.size()==2 and home.households[0]==first and world.build_grid.occupied_cells(home.id)==footprint,"Two physical builders finish all material deliveries on the same inhabited footprint")
	check(claim_snapshot(world,home)==original and world.building_uses.view(home.id).get_markers(Slot)==markers,"Completion preserves existing physical claims and authored layout objects")
	check(Layouts.validate(world.building_uses.view(home.id).layout,home.definition),"Eight physical beds validate their level, groups and capsule separation")
	check(card.available_tabs()==[&"info",first.id,home.households[1].id] and card.housing_count.text=="Жильцы: 4 / 8", "Atomic completion updates existing dynamic tabs and total count")
	check(world.building_uses.choices(home.id,3,Vector3.ZERO,home.households[1].id).size()==4 and world.building_uses.choices(home.id,3,Vector3.ZERO,first.id).is_empty(),"Free second household cannot satisfy a full first household")
	check(world.building_uses.acquire(home.id,3,"ambiguous",Vector3.ZERO)==null,"HOME II refuses an ambiguous physical sleep without a committed unit")
	await observe(world,home,"home_II_empty_second")
	for index in range(4,8):check(await admit(world,home,home.households[1],tenants[index].data),"Player explicitly admits four new residents through the second household UI")
	sleep_group(tenants.slice(4,8))
	var occupied: Array=claim_snapshot(world,home)
	check(occupied.size()==8 and tenants.all(func(a):return a.data.activity==Activity.SLEEPING and a.data.current_sleep_quality==1.0),"Eight simultaneous actual sleepers at unchanged quality")
	for actor in tenants:
		var owned: Array=occupied.filter(func(row):return row.owner==actor.data.id)
		check(owned.size()==1 and owned[0].household==pc.get_household(actor.view._sleep_intent.sleep_household_id).local_index,"Each physical claim belongs to its accepted household snapshot")
	for i in occupied.size():
		for j in range(i+1,occupied.size()):check(tenants[i].view.global_position!=tenants[j].view.global_position,"Physical positions never coincide")
	await observe(world,home,"eight_sleepers")
	check(pc.clear_household(tenants[4].data.id) and pc.assign_household(builders[1].data.id,home.households[1].id),"Second-unit assignment vacancy does not release accepted physical sleep")
	builders[1].schedule._on_phase_changed("Ночь");finish_sleep(builders[1])
	check(world.fallback_housing.owns(builders[1].data.id,world.warehouse_data.id),"Full second unit also falls back to CENTER rather than borrowing a first-unit bed")
	builders[1].schedule._on_phase_changed("Утро");pc.clear_household(builders[1].data.id)

	# Accepted intent keeps its first-unit snapshot even if assignment moves before arrival.
	for actor in tenants:actor.schedule._on_phase_changed("Утро")
	check(world.building_uses.inside_count(home.id)==0,"Morning releases all eight claims through the portal")
	pc.clear_household(tenants[4].data.id)
	tenants[0].schedule._on_phase_changed("Ночь");var accepted=tenants[0].intents.current_intent
	check(pc.assign_household(tenants[0].data.id,home.households[1].id),"Move a committed traveller into a free second-unit permanent place")
	finish_sleep(tenants[0])
	check(tenants[0].view._marker.household_index==1 and accepted.sleep_household_id==first.id,"Arrival uses accepted unit rather than later membership")
	# Refill the first unit with already committed sleepers, then another tenant must use CENTER.
	for actor in tenants.slice(1,4):actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
	check(pc.assign_household(builders[0].data.id,first.id),"Permanent vacancy exists after movement despite old accepted sleep")
	builders[0].schedule._on_phase_changed("Ночь");finish_sleep(builders[0])
	check(world.fallback_housing.owns(builders[0].data.id,world.warehouse_data.id),"Full own unit falls back to CENTER, never the other unit's free bed")
	# True D1 remains strict and clears both units, including sleepers.
	var second=home.households[1]
	check(world.change_construction_direction(home.id,true),"Real D1 accepts upgraded HOME")
	check(pc.get_home_occupants(home.id).is_empty() and tenants.all(func(a):return a.data.household_id.is_empty()) and world.building_uses.inside_count(home.id)==0,"Demolition clears both household memberships and every physical claim")
	check(world.change_construction_direction(home.id,false),"Cancel D1 restores existing structure through ordinary direction reversal")
	# At the untouched final progress, restoration can complete immediately.
	world._poll_building_work()
	check(home.is_built() and home.level==2 and home.households==[first,second] and pc.get_home_occupants(home.id).is_empty(),"D1 cancellation preserves both unit identities without automatic resettlement")
	await observe(world,home,"demolition_restored")
	world.free();await process_frame
func cancellation_stages() -> void:
	for when in [&"immediate",&"delivery",&"boundary",&"working",&"last"]:
		var world=F.create(self);var home=F.building(world,T.HOME,Vector3(-12,0,16));var builders=workers(world,1 if when==&"last" else 2)
		var actor=world.resident_runtimes[2];var first=home.households[0];world.player_control.assign_household(actor.data.id,first.id);actor.schedule.work_decision=Callable()
		actor.schedule._on_phase_changed("Ночь");finish_sleep(actor);var position: Vector3=actor.view.global_position
		world.resident_selection.select_building(home);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(first.id)
		world.building_card_view().household_views[first.id].button.pressed.emit()
		world.settlement_panel.activate_row(world.resident_runtimes[3].data.id)
		check(world.start_building_upgrade(home.id) and actor.data.activity==Activity.SLEEPING,"Cancellation fixture starts B2 without waking its tenant")
		check(not world.assignment_dialog.execute(&"home") and world.resident_runtimes[3].data.household_id.is_empty(),"A previously opened assignment offer cannot bypass the new B2 domain fence")
		world.assignment_dialog.close()
		supply(world,home)
		if when==&"delivery":
			await drive(world,home,builders,func():return home.get_delivered_amount(R.LOG)>0)
		elif when==&"boundary":await drive(world,home,builders,func():return home.construction_progress==60 and home.get_delivered_amount(R.BRICK)>0)
		elif when==&"working":await drive(world,home,builders,func():return home.construction_progress>=75)
		elif when==&"last":await drive(world,home,builders,func():return home.construction_progress>=179)
		world.game_time.total_minutes=420
		if actor.data.activity!=Activity.SLEEPING:actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
		position=actor.view.global_position
		var owned: Dictionary=home.construction_delivered
		for worker in builders:
			if worker.data.inventory.amount>0:owned[worker.data.inventory.resource_type]=int(owned.get(worker.data.inventory.resource_type,0))+worker.data.inventory.amount
		await observe(world,home,"cancel_"+String(when))
		check(world.cancel_building_upgrade(home.id),"Cancel through existing B2 coordinator")
		if home.is_upgrading():await drive(world,home,builders)
		check(home.is_built() and home.level==1 and home.households==[first] and actor.data.household_id==first.id,"All cancellation stages restore original populated unit only")
		check(actor.data.activity==Activity.SLEEPING and actor.view.global_position==position and world.building_uses.occupied_by(home.id,actor.data.id,3),"Reversing and refunding the project preserves accepted sleep")
		for resource in [R.LOG,R.BRICK,R.PLANK]:
			var dropped: int=world.ground_resources.drops.filter(func(drop):return drop.resource_type==resource).reduce(func(total,drop):return total+drop.amount,0)
			check(dropped==int(owned.get(resource,0)) and world.warehouse_data.resources.get_reserved_out(resource)==0 and home.get_construction_reserved_in(resource)==0,"Ordinary B2 refunds exactly delivered/carried material and clears promises")
		check(not world.cancel_building_upgrade(home.id) and world.player_control.assign_household(world.resident_runtimes[3].data.id,first.id),"Repeat cancellation is harmless and ordinary admission reopens")
		await observe(world,home,"cancel_restored_"+String(when))
		world.free();await process_frame

func second_unit_fallback() -> void:
	var world=prepare();var home=F.building(world,T.HOME,Vector3(-12,0,16));var actor=world.resident_runtimes[0]
	check(world.start_building_upgrade(home.id),"Prepare actual HOME II for unreachable destination")
	finish_upgrade(home)
	check(world.player_control.assign_household(actor.data.id,home.households[1].id),"Assign concrete second unit before night routing")
	var trace=trace_actor(actor);enclose(world,home)
	actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
	check(trace.failures.size()==1 and trace.routes.map(func(row):return row.building)==[home.id,world.warehouse_data.id] and world.fallback_housing.owns(actor.data.id,world.warehouse_data.id),"Real A* failure from HOME II uses finite existing CENTER fallback")
	actor.commands.move_to(Vector2(-600,650))
	check(not actor.view.is_inside_building(world.warehouse_data.id) and world.fallback_housing.count(world.warehouse_data.id)==0,"Player command releases the fallback claim")
	actor.intents.abort_current(actor.intents.current_intent);actor.intents.player_controlled=false
	actor.decision._deciding=false;actor.data.fatigue=100
	check(actor.data.activity==Activity.SLEEPING and actor.intents.current_intent.reason_id==&"critical_sleep" and actor.data.current_sleep_quality==.6 and not actor.view.is_inside_building(home.id),"Critical fatigue retains immediate outdoor sleep without seeking a bed")
	world.free();await process_frame
