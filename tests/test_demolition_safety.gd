extends "res://tests/test_demolition_world.gd"
func run() -> void:
	start_world();await physics_frame
	var first=world.resident_runtimes[0];var second=world.resident_runtimes[1];var third=world.resident_runtimes[2]
	for actor in [first,second,third]:world.player_control.assign_profession(actor.data.id,P.BUILDER)
	var site=site_at(Vector3(5,0,22));fill_site(site)
	begin_work(first);begin_work(second)
	check(not third.builder.request_work() and site.active_builder_ids.size()==2,"Two-builder capacity is atomic")
	world.game_time.debug_skip_minutes(1)
	check(site.construction_progress==2,"Each builder contributes actual worker minutes")
	world.game_time.advance(0.35);var fraction: float=world.game_time._fractional_minutes
	check(world.cancel_construction(site.id) and world.game_time._fractional_minutes==fraction and fraction>0,"Direction changes preserve fractional game time")
	begin_work(first);begin_work(second);world.game_time.debug_skip_minutes(1);world._poll_building_work()
	check(site.state==B.State.REMOVED and site.construction_progress==0,"Simultaneous terminal workers clamp once")
	check(ground_amount(R.LOG)==8 and ground_amount(R.STONE)==2 and site.active_builder_ids.is_empty(),"One exact refund and released builder claims")
	world._finish_building_removal(site)
	check(ground_amount(R.LOG)==8 and not world.change_construction_direction(site.id,false),"Terminal removal cannot be replayed or reversed")
	world.free();await process_frame
	start_world();await physics_frame
	var house=built_at(Vector3(5,0,22),T.HOME)
	house.resources.set_capacity(R.FOOD,10);house.resources.add(R.FOOD,10)
	var footprint: Array=world.build_grid.occupied_cells(house.id)
	var cells: Array=world._demolition_cells(footprint,123)
	var allowed_cell: Vector2i=footprint[0]
	var roads: Array=cells.filter(func(cell):return cell!=allowed_cell)
	world.roads.edit(roads,false) # Deliberately constrained geometry fixture.
	var view: Node=world.world_locations.get_view(house.id)
	var observations: Array=[]
	var watch:=func(_drop):
		observations.append(not view.visible and view.collision_layer==0 and world.world_locations.get_view(house.id)==null and world.build_grid.occupied_cells(house.id).is_empty())
		world._continue_building_refund(house.id) # Nested observer must not replay the current manifest.

	world.ground_resources.added.connect(watch)
	check(world.change_construction_direction(house.id,true),"Constrained house begins demolition")
	house.construction_progress=0;world._poll_building_work()
	check(house.state==B.State.REMOVED and ground_amount(R.FOOD)==10 and ground_amount(R.LOG)==0,"Contents take the only cell before structural materials")
	check(world.demolition_results[house.id].discarded[R.FOOD]==0 and world.demolition_results[house.id].discarded[R.LOG]==4 and world.demolition_results[house.id].discarded[R.STONE]==1,"Approved overflow distinct from planned half loss")
	check(observations==[true],"Hidden view, collision and released footprint precede first refund signal")
	world.ground_resources.added.disconnect(watch)
	world.free();await process_frame
	start_world();await physics_frame
	var warehouse=built_at(Vector3(5,0,22),T.STORAGE)
	var destination=built_at(Vector3(14,0,22),T.SAWMILL)
	warehouse.resources.add(R.LOG,2)
	var porter=world.resident_runtimes[1]
	world.player_control.assign_workplace(porter.data.id,warehouse.id,P.PORTER)
	var job=world.logistics.claim_transport(porter.data.id,Source.new(Source.Kind.CONTAINER,warehouse.id),destination,R.LOG,func():return true)
	check(job!=null and world.logistics.start_claimed_job(job,porter.data.id),"Real source pickup begins")
	var cancel_during_pickup:=func(resource,amount):
		if resource==R.LOG and amount==1:world.change_construction_direction(warehouse.id,true)
	warehouse.resources.changed.connect(cancel_during_pickup)
	for step in range(16000):
		porter.view._physics_process(0.05)
		if not porter.intents.current_intent.resource_handling.is_empty():world.game_time.debug_skip_minutes(10)
		if not warehouse.is_built():break
	warehouse.resources.changed.disconnect(cancel_during_pickup)
	world._poll_building_work()
	check(not warehouse.is_built() and porter.data.inventory.amount==0 and world.logistics.get_job(porter.data.id)==null,"Reentrant demolition settles cargo through existing cancel")
	check(warehouse.resources.get_amount(R.LOG)==1 and ground_amount(R.LOG)==1 and destination.resources.get_reserved_in(R.LOG)==0,"Picked unit belongs only to worker drop, not source snapshot")
	warehouse.construction_progress=0;world._poll_building_work()
	check(ground_amount(R.LOG)==3 and world.demolition_results[warehouse.id].placed[R.LOG]==2,"One cargo plus one stock plus one material refund, no duplication")
	world.free();await process_frame
	# Real rotated footprint at the map edge; refund may only use in-bounds allowed cells.
	start_world();await physics_frame
	var definition=D.for_type(T.HOME)
	var point: Vector3=world.build_grid.snap(Vector3(60,0,36),definition.footprint_cells,1)
	var rotated=B.new(&"edge_rotated",definition,C.to_sim(point))
	rotated.quarter_turns=1
	world.buildings.append(rotated);world._show_building(rotated)
	var occupied: Array=world.build_grid.occupied_cells(rotated.id)
	check(occupied.size()==24,"Rotated home retains real footprint size")
	check(world.change_construction_direction(rotated.id,true),"Rotated edge building can be demolished")
	rotated.construction_progress=0;world._poll_building_work()
	check(rotated.state==B.State.REMOVED and ground_amount(R.LOG)==4 and ground_amount(R.STONE)==1,"Edge refund preserves exact quantities")
	for stack in world.ground_resources.drops:
		check(world.build_grid.validation_reason([stack.cell]).is_empty() and world._ground_cell_allowed(stack.cell),"Every rotated edge stack obeys current geometry")
	world.free();await process_frame
	# Starter Town Center has separate presentation wiring; restore it through the same activation lifecycle.
	start_world();await physics_frame
	var center=world.warehouse_data
	first=world.resident_runtimes[0];second=world.resident_runtimes[1]
	for actor in [first,second]:world.player_control.assign_profession(actor.data.id,P.BUILDER)
	check(world.change_construction_direction(center.id,true),"Town Center shuts down")
	begin_work(first);begin_work(second);world.game_time.debug_skip_minutes(10)
	check(center.construction_progress==220 and not world.logistics._buildings.has(center.id),"Town Center uses full 240 work and is offline")
	check(world.change_construction_direction(center.id,false),"Restore Town Center")
	begin_work(first);begin_work(second);world.game_time.debug_skip_minutes(10)
	check(center.is_built() and world.logistics._buildings.get(center.id)==center and world.interactions._targets.has(center.id),"Starter activation restores logistics and context actions")
	check(center.resources.get_amount(R.PLANK)==60 and center.resources.get_amount(R.FOOD)==20,"Town Center restoration retains initial contents")
	check(world.change_construction_direction(center.id,true),"Demolish restored Town Center")
	for cycle in range(2):
		begin_work(first);begin_work(second);world.game_time.debug_skip_minutes(60);world._poll_building_work()
	check(center.state==B.State.REMOVED and world.player_control.get_building(center.id)==null,"Two builders remove Town Center after exactly 240 work")
	check(ground_amount(R.PLANK)==60 and ground_amount(R.FOOD)==20 and world.demolition_results[center.id].planned_loss.is_empty(),"Town Center refunds contents only, no invented material recipe")
	world.free();await process_frame
	print("Demolition safety: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
