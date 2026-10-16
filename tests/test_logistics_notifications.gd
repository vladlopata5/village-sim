extends SceneTree
const Setup=preload("res://tests/behavior_test_setup.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world=Setup.make_scene(self)
	world.game_time.total_minutes=420
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		world.player_control.assign_profession(actor.data.id,P.NONE)
		actor.schedule._phase="День"
		actor.data.activity=0
		actor.decision.work_available=world._work_available.bind(actor)
		actor.decision.work_request=world._request_work.bind(actor)
		actor.schedule.work_decision=actor.decision.request_decision
	for building in world.buildings:
		for resource in R.values():
			var stock:int=building.resources.get_available_amount(resource)
			if stock>0:assert(building.resources.try_take(resource,stock))
	var workers=[world.resident_runtimes[1],world.resident_runtimes[3]]
	for actor in workers:
		assert(world.player_control.assign_workplace(actor.data.id,world.warehouse_data.id,P.PORTER))
		world.logistics.use_executor(actor.data,world.game_time,world.world_locations,actor.intents,actor.schedule)
	await process_frame
	await process_frame
	for actor in workers:
		actor.decision._deciding=false
		actor.decision.request_decision("free")
	var before:int=workers[0].decision.decision_count+workers[1].decision.decision_count
	var notices:={"count":0}
	world.logistics.changed.connect(func():notices.count+=1)
	var start:int=world.game_time.total_minutes
	assert(world.gatherer_hut_data.resources.add(R.FOOD,1))
	assert(notices.count==1,"One amount change is validated once, without Main's duplicate changed binding")
	await process_frame
	await process_frame
	var event_decisions:int=workers[0].decision.decision_count+workers[1].decision.decision_count-before
	assert(event_decisions==0 and world.logistics.jobs.is_empty(),"New stock does not wake idle Porters")
	for minute in range(40):
		if not world.logistics.jobs.is_empty():break
		world.game_time.debug_skip_minutes(1)
	assert(world.logistics.jobs.size()==1)
	var latency:int=world.game_time.total_minutes-start
	assert(latency>0 and latency<=30,"Next ordinary IDLE retry discovers the real unreserved unit")
	var job=world.logistics.jobs[0]
	assert(world.gatherer_hut_data.resources.get_reserved_out(R.FOOD)==1)
	assert(world.logistics._buildings[job.destination_location_id].resources.get_reserved_in(R.FOOD)==1)
	for actor in world.resident_runtimes:actor.decision._deciding=true
	world.logistics._executors[job.assigned_resident_id].cancel("controlled cleanup")
	for actor in world.resident_runtimes:actor.intents.abort_current(actor.intents.current_intent)
	for building in world.buildings:
		for resource in R.values():
			var stock:int=building.resources.get_available_amount(resource)
			if stock>0:building.resources.try_take(resource,stock)
	await process_frame
	var metrics:={"routes":0}
	var route:Callable=world.logistics.sources.route_available
	world.logistics.sources.route_available=func(a,b):
		metrics.routes+=1
		return route.call(a,b)
	var idle_before:=0
	for actor in workers:
		actor.data.activity=0
		actor.decision._deciding=false
		idle_before+=actor.decision.decision_count
	var wall:=Time.get_ticks_usec()
	world.game_time.debug_skip_minutes(4320)
	var idle_decisions:=0
	for actor in workers:idle_decisions+=actor.decision.decision_count
	var result:={"latency_game_minutes":latency,"decisions_from_arrival":event_decisions,"competing_porters":2,"claims_for_one_unit":1,"idle_game_minutes":4320,"idle_wall_us":Time.get_ticks_usec()-wall,"idle_decisions":idle_decisions-idle_before,"idle_route_checks":metrics.routes,"active_jobs":world.logistics.jobs.size(),"inbound_remaining":world.logistics._inbound.size()}
	assert(result.idle_decisions<1000 and result.idle_route_checks==0,"Empty work across three game days has bounded ordinary decisions and no route probes")
	assert(result.active_jobs==0 and result.inbound_remaining==0,"Controlled cancellation leaves no promises or owned jobs")
	print("Logistics notifications: all assertions passed; ",JSON.stringify(result))
	world.free()
	quit()
