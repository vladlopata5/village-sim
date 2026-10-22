extends "res://tests/test_staged_builder.gd"
func run() -> void:
	for type in [T.CLAY_HUT,T.POTTERY_WORKSHOP]:
		await building_lifecycle(type)
	print("Clay construction: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func building_lifecycle(type: int) -> void:
	var world=F.create(self);var site=place(world,type,Vector3(-12,0,16));supply(world,site)
	var actors=workers(world)
	world.game_time.set_speed(20)
	check(not world.player_control.assign_workplace(world.resident_runtimes[2].data.id,site.id) and site.resources.get_capacity(R.CLAY)==0 and not world.logistics._buildings.has(site.id),"No CL1 work, buffers or logistics before B1 completion")
	world.resident_selection.select_building(site)
	await observe(world,site,"cl1_initial")
	await drive(world,site,actors)
	check(site.is_built() and site.construction_progress==180 and site.construction_delivered==site.definition.construction_requirements and site.active_builder_ids.is_empty(),"Two builders physically deliver exact approved materials and finish all three stages")
	check(world._activated_buildings.has(site.id) and world.logistics._buildings.has(site.id) and site.resources.get_capacity(R.CLAY)==(12 if type==T.CLAY_HUT else 10),"Final stage alone activates actual clay buffers and logistics")
	check(world.player_control.assign_workplace(world.resident_runtimes[2].data.id,site.id),"Completed building admits its real profession")
	await observe(world,site,"cl1_built")
	check(world.change_construction_direction(site.id,true),"D1 demolition accepts CL1 building")
	await drive(world,site,actors)
	check(site.state==B.State.REMOVED and world.player_control.get_building(site.id)==null and not world.logistics._buildings.has(site.id),"Ordinary demolition removes workplace and logistic registration")
	for resource in site.definition.construction_requirements:
		check(site.get_construction_reserved_in(resource)==0 and world.warehouse_data.resources.get_reserved_out(resource)==0,"No owned reserve survives demolition")
	world.free();await process_frame
	world=F.create(self);site=place(world,type,Vector3(-12,0,16));supply(world,site);actors=workers(world)
	world.game_time.set_speed(20)
	await drive(world,site,actors,func():return site.completed_construction_stage_count()==1)
	check(not site.is_built() and world.cancel_construction(site.id),"Unfinished CL1 building can be cancelled after actual material delivery")
	await drive(world,site,actors)
	check(site.state==B.State.REMOVED and actors.all(func(actor):return actor.data.inventory.amount==0 and actor.builder.site==null),"Cancellation performs reverse labour and cleans cargo/assignments")
	for resource in site.definition.construction_requirements:check(world.warehouse_data.resources.get_reserved_out(resource)==0 and site.get_construction_reserved_in(resource)==0,"Cancelled CL1 project releases reserves")
	world.free();await process_frame
