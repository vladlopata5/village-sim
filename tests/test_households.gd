extends "res://tests/test_staged_builder.gd"
const Household=preload("res://scripts/household_data.gd")
const Data=preload("res://scripts/resident_data.gd")
const Player=preload("res://scripts/player_control.gd")
const Activity=preload("res://scripts/resident_activity.gd").Type
func run() -> void:
	domain_contract()
	await world_contract()
	print("Households: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func domain_contract() -> void:
	var a=B.new(&"house_a",D.for_type(T.HOME));var b=B.new(&"house_b",D.for_type(T.HOME))
	var site=B.new(&"new_site",D.for_type(T.HOME),Vector2.ZERO,B.State.UNDER_CONSTRUCTION)
	var center=B.new(&"town",D.for_type(T.TOWN_CENTER))
	var pc=Player.new();var population: Array=[]
	for index in 9:population.append(Data.new("tenant_%d"%index,"Житель",30,P.NONE))
	pc.setup(population,[a,b,site,center])
	var first=a.households[0];var second=b.households[0]
	check(a.households.size()==1 and first.capacity==4 and first.local_index==1,"Built HOME I owns one four-place unit")
	check(first.id==Household.id_for(a.id) and first.id!=second.id and pc.get_household_home(first.id)==a,"Stable unit identity and ownership without world registry")
	check(center.households.is_empty() and site.households.is_empty(),"Town Center and construction site have no household")
	check(first.get_property_list().all(func(property):return property.name not in [&"resident_ids",&"house_id"]),"No second membership or parent ledger")
	check(population[0].get_property_list().all(func(property):return property.name!=&"home_location_id"),"Resident has no second mutable home field")
	var copy: Array=a.households;copy.clear();a.ensure_households();a.definition.display_name="Новое имя"
	check(a.households==[first] and first.id==Household.id_for(a.id),"Queries, rename and repeated activation preserve original unit object")
	var events: Array=[];var home_events: Array=[]
	pc.household_changed.connect(func(id,old,next):
		events.append([id,old,next])
		check(pc.get_resident(id).household_id==next,"Callbacks see the completed relation"))
	pc.home_changed.connect(func(id,old,next):home_events.append([id,old,next]))
	for index in 4:check(pc.assign_household(population[index].id,first.id),"Four independent explicit assignments fit")
	check(pc.get_household_occupants(first.id).size()==4 and pc.get_home_occupants(a.id).size()==4 and home_events.size()==4,"Unit and compatibility home queries agree")
	var count: int=events.size()
	check(pc.assign_household(population[0].id,first.id) and events.size()==count and home_events.size()==count,"Repeated unit command is an idempotent no-op")
	check(not pc.assign_home(population[0].id,a.id) and events.size()==count,"Legacy same-home refusal remains harmless")
	check(not pc.assign_household(population[4].id,first.id) and population[4].household_id.is_empty(),"Fifth tenant rejected")
	check(not pc.assign_household("absent",first.id) and not pc.assign_household(population[4].id,Household.id_for(site.id)) and not pc.assign_household(population[4].id,&"absent"),"Unknown resident/unit/unbuilt home cannot be assigned")
	for index in range(4,8):check(pc.assign_household(population[index].id,second.id),"Second unit has its own capacity")
	check(not pc.assign_household(population[0].id,second.id) and population[0].household_id==first.id,"Rejected move retains previous membership")
	check(pc.clear_household(population[4].id) and pc.assign_household(population[0].id,second.id),"A successful move releases old place atomically")
	check(events[-1][1]==first.id and events[-1][2]==second.id and home_events[-1][1]==a.id and home_events[-1][2]==b.id,"Unit and compatible building events have correct IDs")
	population[0].profession=P.BUILDER;population[0].work_location_id=&"some_work"
	var health: Array=[population[0].hunger,population[0].fatigue,population[0].relationships.duplicate()]
	check(pc.clear_home(population[0].id) and population[0].profession==P.BUILDER and population[0].work_location_id==&"some_work" and health==[population[0].hunger,population[0].fatigue,population[0].relationships],"Housing eviction preserves profession, workplace, needs and relationships")
	count=events.size();check(not pc.clear_household(population[0].id) and events.size()==count,"Repeated cleanup creates no notification")
	pc.unregister_resident(population[1].id)
	check(population[1].household_id.is_empty() and pc.get_household_occupants(first.id).size()==2,"Unregister removes permanent membership")
	pc.unregister_building(b.id);pc.unregister_building(b.id)
	check(pc.get_household(second.id)==null and population.slice(5,8).all(func(tenant):return tenant.household_id.is_empty()),"Direct building invalidation clears tenants, repeat is safe")
	preload("res://tests/construction_recipe_expectations.gd").complete(site,false)
	check(site.complete_construction() and site.households.size()==1 and pc.get_home_occupants(site.id).is_empty(),"B1 completion creates an empty unit before notification")
	var site_unit=site.households[0];site.ensure_households();site.complete_construction()
	check(site.households==[site_unit] and not site.is_upgrading() and site.next_upgrade()==null,"Repeated completion preserves identity; HOME II is disabled")
	var rebuilt=B.new(&"different_house",D.for_type(T.HOME))
	check(rebuilt.households[0].id!=second.id,"New house identity cannot reuse demolished household ID")
	# Reentrant management cannot publish a stale outer home event or double-remove.
	var reentrant=Player.new();var person=Data.new("nested","Вложенный",30);var homes: Array=[a,rebuilt]
	reentrant.setup([person],homes)
	var published: Array=[]
	reentrant.household_changed.connect(func(_id,_old,next):
		if next==first.id:reentrant.assign_household(person.id,rebuilt.households[0].id))
	reentrant.home_changed.connect(func(_id,_old,next):published.append(next))
	check(reentrant.assign_household(person.id,first.id) and person.household_id==rebuilt.households[0].id and published==[rebuilt.id],"Nested move publishes no obsolete home state")
	reentrant.household_changed.connect(func(id,_old,next):
		if next.is_empty():reentrant.unregister_resident(id))
	reentrant.unregister_resident(person.id)
	check(reentrant.get_resident(person.id)==null and person.household_id.is_empty(),"Nested unregister cannot duplicate disconnect/cleanup")
	var cleanup=Player.new();var departing=Data.new("departing","Удаляемый",30)
	cleanup.setup([departing],[a,rebuilt]);cleanup.assign_household(departing.id,first.id)
	var rejected: Array=[]
	cleanup.household_changed.connect(func(id,_old,next):
		if next.is_empty():rejected.append(not cleanup.assign_household(id,first.id)))
	cleanup.unregister_building(a.id)
	check(rejected==[true] and departing.household_id.is_empty(),"Removal callbacks cannot reassign a tenant into the disappearing house")
	cleanup.assign_household(departing.id,rebuilt.households[0].id)
	cleanup.household_changed.connect(func(id,_old,next):
		if next.is_empty():rejected.append(not cleanup.assign_home(id,rebuilt.id)))
	cleanup.unregister_resident(departing.id)
	check(rejected==[true,true,true] and departing.household_id.is_empty(),"Resident removal rejects nested unit and legacy housing assignments")
	for control in [pc,reentrant,cleanup]:
		for event in [control.household_changed,control.home_changed]:
			for connection in event.get_connections():event.disconnect(connection.callable)
func sleep_arrival(actor: Node) -> void:
	for step in 5000:
		actor.view._physics_process(.05)
		if not actor.view.movement.is_moving():break
func world_contract() -> void:
	var world=F.create(self);await physics_frame;await process_frame
	var a=F.building(world,T.HOME,Vector3(-12,0,16));var b=F.building(world,T.HOME,Vector3(-22,0,16))
	check(world.debug_spawn.spawn_residents(Vector3(-18,0,24),1,P.NONE).created==1,"Fifth actual resident for capacity and fallback")
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
		actor.schedule.work_decision=Callable()
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	var actors: Array=world.resident_runtimes;var pc=world.player_control
	check(pc.get_home_occupants(a.id).is_empty() and pc.get_home_occupants(b.id).is_empty(),"Completed actual homes stay empty until player assignment")
	world.resident_selection.select_building(a)
	var card=world.building_card_view()
	for index in 4:
		card.staffing_buttons[&"home"].pressed.emit()
		world.settlement_panel.activate_row(actors[index].data.id)
		check(world.assignment_dialog.execute(&"home"),"Existing UI assigns HOME I through unit adapter")
	check(card.housing_count.text=="Жильцы: 4 / 4" and pc.get_home_occupants(a.id).size()==4,"Existing blue card shows all four tenants")
	card.staffing_buttons[&"home"].pressed.emit();world.settlement_panel.activate_row(actors[4].data.id)
	check(world.assignment_dialog.buttons[&"home"].disabled and not world.assignment_dialog.execute(&"home"),"Fifth UI assignment refused without weakening admission")
	world.assignment_dialog.close()
	await observe(world,a,"full")
	world.resident_selection.select_building(b)
	card.staffing_buttons[&"home"].pressed.emit();world.settlement_panel.activate_row(actors[0].data.id)
	check(world.assignment_dialog.execute(&"home") and pc.get_home_occupants(a.id).size()==3 and pc.get_home_occupants(b.id).size()==1,"Existing UI move releases former home place")
	check(pc.assign_home(actors[0].data.id,a.id),"Prepare assigned sleep in first home")
	world.game_time.total_minutes=1380
	for actor in actors:
		actor.view.global_position=Vector3(-17,0,24)
		actor.schedule._on_phase_changed("Ночь");sleep_arrival(actor)
	check(actors[0].data.activity==Activity.SLEEPING and world.building_uses.occupied_by(a.id,actors[0].data.id,3),"Ordinary sleep reaches original four SLEEP slots through household")
	check(actors[4].data.activity==Activity.SLEEPING and actors[4].data.current_sleep_quality==1.0 and actors[4].data.household_id.is_empty() and world.fallback_housing.owns(actors[4].data.id,world.warehouse_data.id),"Homeless resident uses temporary Town Center, not a household")
	var position: Vector3=actors[0].view.global_position
	check(pc.assign_household(actors[0].data.id,b.households[0].id) and actors[0].data.activity==Activity.SLEEPING and actors[0].view.global_position==position and world.building_uses.occupied_by(a.id,actors[0].data.id,3),"Sleeping move changes only next sleep destination")
	await observe(world,b,"sleeping-move")
	actors[0].schedule._on_phase_changed("Утро");actors[0].schedule._on_phase_changed("Ночь");sleep_arrival(actors[0])
	check(world.building_uses.occupied_by(b.id,actors[0].data.id,3) and actors[0].data.current_sleep_quality==1.0,"Next sleep uses new assigned household owner")
	var unit=a.households[0]
	check(world.change_construction_direction(a.id,true) and pc.get_home_occupants(a.id).is_empty() and actors.slice(1,4).all(func(actor):return actor.data.household_id.is_empty()),"D1 start immediately clears all related permanent assignments")
	check(not pc.assign_household(actors[1].data.id,unit.id) and a.households==[unit] and world.building_uses.inside_count(a.id)==0,"Demolishing unit is inactive, identity retained, physical occupancy released")
	check(world.change_construction_direction(a.id,false) and a.households==[unit] and pc.get_home_occupants(a.id).is_empty(),"D1 restoration preserves identity without automatic resettlement")
	await observe(world,a,"demolition-cleanup")
	var data=actors[0].data
	actors[0].free()
	check(data.household_id.is_empty() and pc.get_home_occupants(b.id).is_empty() and world.building_uses.inside_count(b.id)==0,"Physical runtime removal during sleep clears permanent and transient membership")
	var homeless_id: String=actors[4].data.id;actors[4].free()
	check(not world.fallback_housing.owns(homeless_id,world.warehouse_data.id) and world.building_uses.inside_count(world.warehouse_data.id)==0,"Physical homeless removal frees Town Center slot and fallback")
	world.free();await process_frame
