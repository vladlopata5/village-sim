extends "res://tests/test_households.gd"
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
var evidence: Array=[]
func prepare() -> Node:
	var world=F.create(self)
	world.game_time.total_minutes=1380
	for actor in world.resident_runtimes:
		actor.schedule.work_decision=Callable()
		actor.view.global_position=Vector3(-22,0,26)
	return world
func enclose(world: Node, home: RefCounted) -> Array:
	var point: Vector3=Coord.to_world(home.position)
	var half: float=maxf(home.definition.footprint_cells.x,home.definition.footprint_cells.y)*.25+3.0
	var boxes: Array=[Rect2(point.x-half,point.z-half,.5,2*half),Rect2(point.x+half-.5,point.z-half,.5,2*half),Rect2(point.x-half,point.z-half,2*half,.5),Rect2(point.x-half,point.z+half-.5,2*half,.5)]
	for index in boxes.size():world.navigation.add_blocker(StringName("sleep_ring_%s_%d" % [home.id,index]),boxes[index])
	return boxes
func trace_actor(actor: Node) -> Dictionary:
	var trace: Dictionary={"routes":[],"failures":[],"intents":[]}
	actor.intents.intent_changed.connect(func(intent):
		if intent.reason_id not in [&"night_home",&"night_outdoor"]:return
		trace.intents.append(intent)
		trace.routes.append({"reason":intent.reason_id,"building":intent.building_id,"household":intent.sleep_household_id,"target":str(intent.target_position)}))
	actor.view.intent_failed.connect(func(intent):trace.failures.append({"building":intent.building_id,"reason":intent.reason_id}))
	return trace
func finish_sleep(actor: Node) -> void:
	for step in 5000:
		actor.view._physics_process(.05)
		if actor.data.activity==Activity.SLEEPING and not actor.view.movement.is_moving():return
func ordinary_cases() -> void:
	for mode in ["home","blocked_home","blocked_center","blocked_both","blocked_after_start"]:
		var world=prepare();var actor=world.resident_runtimes[0];var center=world.warehouse_data
		var home=F.building(world,T.HOME,Vector3(-12,0,16))
		var assigned: bool=mode!="blocked_center"
		if assigned:check(world.player_control.assign_household(actor.data.id,home.households[0].id),"Concrete household assigned before sleep")
		var permanent: StringName=actor.data.household_id
		var rings: Array=[]
		if mode in ["blocked_home","blocked_both"]:rings+=enclose(world,home)
		if mode in ["blocked_center","blocked_both"]:rings+=enclose(world,center)
		var home_entry: Vector3=world.building_uses.entrance(home.id)
		var center_entry: Vector3=world.building_uses.entrance(center.id)
		check(world.navigation.is_world_walkable(home_entry) and world.navigation.is_world_walkable(center_entry),"Endpoints remain valid; enclosure tests actual connectivity")
		if mode in ["blocked_home","blocked_both"]:check(world.navigation.find_raw_path(actor.view.global_position,home_entry).is_empty(),"Raw A* proves HOME unreachable without mocking failure")
		if mode in ["blocked_center","blocked_both"]:check(world.navigation.find_raw_path(actor.view.global_position,center_entry).is_empty(),"Raw A* proves CENTER unreachable without mocking failure")
		var trace=trace_actor(actor)
		actor.schedule._on_phase_changed("Ночь")
		await observe(world,home,mode+"-initial")
		if mode=="blocked_after_start":
			actor.view._physics_process(.005);rings+=enclose(world,home)
			check(world.navigation.find_raw_path(actor.view.global_position,home_entry).is_empty(),"New geometry invalidates an already prepared HOME route")
		if mode in ["blocked_home","blocked_both","blocked_after_start"]:
			actor.view._physics_process(.05)
			check(trace.failures.size()==1 and trace.failures[0].building==home.id and actor.intents.current_intent.building_id==center.id,"Actual executor A* failure replaces HOME with CENTER")
			await observe(world,center,mode+"-after-failure")
		finish_sleep(actor)
		var expected: Array=[home.id] if mode=="home" else [home.id,center.id] if mode in ["blocked_home","blocked_after_start"] else [center.id,&""] if mode=="blocked_center" else [home.id,center.id,&""]
		check(trace.routes.map(func(row):return row.building)==expected,"Finite candidate order without a repeated HOME or CENTER: "+mode)
		var outdoor: bool=mode in ["blocked_center","blocked_both"]
		check(actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==(.6 if outdoor else 1.0),"Successful night sleep uses unchanged quality: "+mode)
		check(actor.data.household_id==permanent,"Fallback never changes permanent household")
		check(not world.building_uses.occupied_by(center.id,actor.data.id,3) if outdoor else world.building_uses.occupied_by(home.id if mode=="home" else center.id,actor.data.id,3),"Only successful indoor sleep owns physical SLEEP claim")
		if outdoor:check(actor.view._building.is_empty() and world.fallback_housing.count(center.id)==0,"Outdoor terminal state has no building or fallback claim")
		var count: int=trace.routes.size()
		for repeat in 20:
			actor.schedule.resume_current_phase()
			world._on_movement_failed(trace.intents[0],actor.data)
		check(trace.routes.size()==count,"Late route failures and ordinary retry cannot restart accepted fallback")
		if outdoor:check(not actor.schedule.on_sleep_slot_unavailable(actor.intents.current_intent),"Outdoor state cannot advance to another outdoor attempt")
		evidence.append({"case":mode,"routes":trace.routes,"failures":trace.failures,"rings":str(rings),"quality":actor.data.current_sleep_quality,"household":actor.data.household_id})
		await observe(world,home if mode=="home" else center,mode+"-sleeping")
		actor.schedule._on_phase_changed("Утро")
		check(world.building_uses.inside_count(home.id)==0 and world.building_uses.inside_count(center.id)==0 and world.fallback_housing.count(center.id)==0,"Wake clears physical and temporary claims")
		await observe(world,home,mode+"-released")
		world.free();await process_frame
func interruption_cases() -> void:
	for mode in ["player","forced","hunger","fatigue","phase","resident"]:
		var world=prepare();var actor=world.resident_runtimes[0]
		var home=F.building(world,T.HOME,Vector3(-12,0,16));world.player_control.assign_household(actor.data.id,home.households[0].id);enclose(world,home)
		var trace=trace_actor(actor);actor.schedule._on_phase_changed("Ночь")
		var previous: RefCounted=actor.intents.current_intent;var data: RefCounted=actor.data;var executor: Node=actor.view
		match mode:
			"player":check(world.player_control.move_to(data.id,Coord.to_sim(Vector3(-24,0,26))),"PlayerCommand replaces night route")
			"forced":check(actor.intents.force_set_intent(Intent.new(Intent.Type.MOVE_TO,&"test_forced",Coord.to_sim(Vector3(-24,0,26)),99,true),123),"New forced intent owns execution")
			"hunger":actor.decision._deciding=false;data.hunger=100;check(actor.intents.current_intent.reason_id==&"eat" and actor.intents.forced_priority==200,"Actual critical hunger replaces night route")
			"fatigue":actor.decision._deciding=false;data.fatigue=100;check(actor.intents.current_intent.reason_id==&"critical_sleep" and data.current_sleep_quality==.6 and data.activity==Activity.SLEEPING,"Actual critical fatigue sleeps immediately on spot")
			"phase":actor.schedule._on_phase_changed("Утро")
			"resident":actor.free()
		var replacement: RefCounted=actor.intents.current_intent if is_instance_valid(actor) else null
		# Simulate a late executor notification only here, never in physical A* cases.
		executor.intent_failed.emit(previous)
		if is_instance_valid(actor):
			actor._on_building_use_unavailable(previous)
			check(actor.intents.current_intent==replacement and trace.routes.size()==1,"Stale failure cannot replace new owner: "+mode)
		else:
			check(world.get_resident_runtime(data)==null and data.household_id.is_empty(),"Deleted runtime has no callback target or household")
			world.resident_selection.select(world.residents[1])
			check(world.resident_selection.selected_resident==world.residents[1],"Selection callbacks skip the physically deleted runtime")
		await observe(world,home,"interrupt-"+mode)
		world.free();await process_frame
func unavailable_cases() -> void:
	for mode in ["missing_unit","missing_home","unfinished","demolishing","no_center","remove_trip","remove_sleep","center_demolition"]:
		var world=prepare();var actor=world.resident_runtimes[0];var home=F.building(world,T.HOME,Vector3(-12,0,16));var pc=world.player_control;var center=world.warehouse_data
		pc.assign_household(actor.data.id,home.households[0].id)
		match mode:
			"missing_unit":actor.data.household_id=&"missing_household"
			"missing_home":pc.unregister_building(home.id)
			"unfinished":home._state=B.State.UNDER_CONSTRUCTION
			"demolishing":world.change_construction_direction(home.id,true)
			"no_center":pc.clear_household(actor.data.id);pc.unregister_building(center.id);world.building_uses.unregister(center.id)
			"center_demolition":pc.clear_household(actor.data.id)
		actor.schedule._on_phase_changed("Ночь")
		if mode=="remove_trip":pc.unregister_building(home.id);world.building_uses.unregister(home.id)
		if mode=="remove_sleep":finish_sleep(actor);world.change_construction_direction(home.id,true)
		if mode=="center_demolition":finish_sleep(actor);world.change_construction_direction(center.id,true)
		finish_sleep(actor)
		var outdoor: bool=mode in ["no_center","center_demolition"]
		check(actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==(.6 if outdoor else 1.0),"Missing/offline building completes fallback: "+mode)
		check(actor.view._building.is_empty() if outdoor else world.building_uses.occupied_by(center.id,actor.data.id,3),"Fallback destination after lifecycle change: "+mode)
		if mode in ["missing_unit","missing_home","demolishing","remove_trip","remove_sleep"]:check(actor.data.household_id.is_empty(),"Invalidation cleans membership through existing PlayerControl")
		world.free();await process_frame
func capacity_case() -> void:
	var world=prepare();check(world.debug_spawn.spawn_residents(Vector3(-22,0,26),12,P.NONE).created==12,"Actual population for four HOME and ten CENTER slots")
	var actors: Array=world.resident_runtimes;var home=F.building(world,T.HOME,Vector3(-12,0,16));var center=world.warehouse_data
	for actor in actors:
		actor.decision._deciding=true;actor.schedule.work_decision=Callable();actor.view.set_physics_process(false);actor.view.global_position=Vector3(-22,0,26)
	for index in 4:world.player_control.assign_household(actors[index].data.id,home.households[0].id)
	# Everyone plans before anyone arrives: no advance reservation of beds.
	var races: Dictionary={}
	for index in range(4,15):races[actors[index].data.id]=trace_actor(actors[index])
	for index in 15:actors[index].schedule._on_phase_changed("Ночь")
	for step in 3000:
		for index in 15:actors[index].view._physics_process(.05)
		if actors.slice(0,15).all(func(actor):return actor.data.activity==Activity.SLEEPING):break
	check(world.building_uses.inside_count(home.id)==4 and world.building_uses.inside_count(center.id)==10,"Simultaneous arrivals atomically fill exactly four and ten physical slots")
	var rejected: Array=actors.slice(4,15).filter(func(actor):return actor.data.current_sleep_quality==.6)
	check(rejected.size()==1 and races[rejected[0].data.id].routes.map(func(row):return row.building)==[center.id,&""],"Eleventh physical arrival, independent of walking speed, falls back after actual acquire refusal")
	var overflow: Node=rejected[0]
	world.player_control.clear_household(actors[0].data.id)
	check(world.player_control.assign_household(overflow.data.id,home.households[0].id),"Logical eviction does not free a sleeping physical bed")
	var trace=trace_actor(overflow);overflow.schedule._on_phase_changed("Ночь");finish_sleep(overflow)
	check(trace.routes.map(func(row):return row.building)==[home.id,&""] and overflow.data.current_sleep_quality==.6,"Full HOME skips known-full CENTER without another path and reaches outdoor once")
	actors[15].schedule._on_phase_changed("Ночь");finish_sleep(actors[15])
	check(actors[15].data.activity==Activity.SLEEPING and actors[15].view._building.is_empty(),"Eleventh homeless arrival cannot acquire an occupied center bed")
	check(world.debug_spawn.spawn_residents(Vector3(-25,0,26),1,P.NONE).created==1,"Spawn a new resident during the full-center night")
	var newcomer: Node=world.resident_runtimes[-1]
	check(newcomer.data.activity==Activity.SLEEPING and newcomer.data.current_sleep_quality==.6 and newcomer.intents.current_intent.reason_id==&"night_outdoor","Initial outdoor sleep succeeds before control registration completes")
	await observe(world,center,"full-center-outdoor")
	for actor in actors:actor.schedule._on_phase_changed("Утро")
	check(world.building_uses.inside_count(home.id)==0 and world.building_uses.inside_count(center.id)==0 and world.fallback_housing.count(center.id)==0,"All claims released after wake")
	await observe(world,center,"full-center-released")
	world.free();await process_frame
func committed_cases() -> void:
	for mode in ["move","evict"]:
		var world=prepare();var actor=world.resident_runtimes[0]
		var home=F.building(world,T.HOME,Vector3(-12,0,16));var other=F.building(world,T.HOME,Vector3(-30,0,16));var pc=world.player_control
		pc.assign_household(actor.data.id,home.households[0].id);enclose(world,home)
		var trace=trace_actor(actor);actor.schedule._on_phase_changed("Ночь");var original: RefCounted=actor.intents.current_intent
		if mode=="move":pc.assign_household(actor.data.id,other.households[0].id)
		else:pc.clear_household(actor.data.id)
		check(actor.intents.current_intent==original and original.sleep_household_id==home.households[0].id,"Committed household snapshot survives logical "+mode)
		finish_sleep(actor)
		check(trace.routes.map(func(row):return row.building)==[home.id,world.warehouse_data.id] and actor.data.current_sleep_quality==1.0,"Failed committed HOME proceeds to CENTER, not the newly assigned house")
		actor.schedule._on_phase_changed("Утро");actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
		check(actor.view._building==(other.id if mode=="move" else world.warehouse_data.id),"A new full sleep choice uses the new household")
		world.free();await process_frame
func reentrant_cases() -> void:
	for mode in ["acquire","fallback_claim"]:
		var world=prepare();var actor=world.resident_runtimes[0];var fired: Array=[]
		var callback: Callable
		if mode=="acquire":
			callback=func(_id,_purpose):
				if not fired.is_empty():return
				fired.append(true);world.player_control.move_to(actor.data.id,Coord.to_sim(Vector3(-24,0,26)))
			world.building_uses.slots_changed.connect(callback)
		else:
			callback=func():
				if not fired.is_empty() or world.fallback_housing.count(world.warehouse_data.id)==0:return
				fired.append(true);world.player_control.move_to(actor.data.id,Coord.to_sim(Vector3(-24,0,26)))
			world.fallback_housing.changed.connect(callback)
		actor.schedule._on_phase_changed("Ночь")
		for step in 5000:
			actor.view._physics_process(.05)
			if not fired.is_empty():break
		check(fired==[true] and actor.intents.player_controlled and actor.data.activity==Activity.MOVING and actor.intents.current_intent.reason_id==&"player_move","Reentrant "+mode+" callback cannot restore obsolete sleep")
		check(world.building_uses.inside_count(world.warehouse_data.id)==0 and world.fallback_housing.count(world.warehouse_data.id)==0,"Interrupted acquire/claim rolls back all sleep ownership")
		if mode=="acquire":world.building_uses.slots_changed.disconnect(callback)
		else:world.fallback_housing.changed.disconnect(callback)
		world.free();await process_frame
func invalidated_acquire_cases() -> void:
	for home_case in [true,false]:
		var world=prepare();var actor=world.resident_runtimes[0];var target: RefCounted=world.warehouse_data
		if home_case:
			target=F.building(world,T.HOME,Vector3(-12,0,16));world.player_control.assign_household(actor.data.id,target.households[0].id)
		var changed: Array=[]
		var callback: Callable=func(id,purpose):
			if id==target.id and purpose==3 and changed.is_empty():changed.append(true);target._state=B.State.UNDER_CONSTRUCTION
		world.building_uses.slots_changed.connect(callback)
		actor.schedule._on_phase_changed("Ночь");finish_sleep(actor)
		check(changed==[true] and actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==(1.0 if home_case else .6),"A target invalidated during physical acquire advances to the next candidate")
		check(world.building_uses.inside_count(target.id)==0,"Invalidated acquired bed cannot remain claimed during fallback")
		world.building_uses.slots_changed.disconnect(callback);world.free();await process_frame
func run() -> void:
	await ordinary_cases();await interruption_cases();await unavailable_cases();await capacity_case();await committed_cases();await reentrant_cases();await invalidated_acquire_cases()
	print("Sleep fallback: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
