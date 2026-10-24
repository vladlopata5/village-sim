extends SceneTree
const HH=preload("res://scripts/household_data.gd")
const F=preload("res://tests/residents_ui_fixture.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const D=preload("res://scripts/building_definition.gd")
const Candidate=preload("res://scripts/delivery_candidate.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const Job=preload("res://scripts/haul_job.gd")
class NavigationProbe extends "res://scripts/navigation_grid.gd":
	var requests := 0
	func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
		requests+=1
		return super.find_raw_path(start,target)
	func find_path_to_radius(start: Vector3, center: Vector3, radius: float, inner_radius: float=0.0) -> PackedVector3Array:
		requests+=1
		return super.find_path_to_radius(start,center,radius,inner_radius)
var checks:=0
var failures:=0
var notifications:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func state(world: Node) -> Array:
	var result:=[]
	for resident in world.player_control.get_residents(): result.append([resident.id,resident.profession,resident.work_location_id,resident.work_area_id,resident.household_id,resident.work_assignment_revision,resident.inventory.amount])
	for building in world.buildings:
		for resource in R.values():
			if building.resources!=null: result.append([building.id,resource,building.resources.get_amount(resource),building.resources.get_reserved_in(resource),building.resources.get_reserved_out(resource)])
	result.append(world.logistics.jobs.duplicate())
	return result
func run() -> void:
	var world=F.create(self)
	var pc=world.player_control
	var dialog=world.assignment_dialog
	var window=world.settlement_panel
	var saw=F.building(world,T.SAWMILL,Vector3(-15,0,10))
	var gather=F.building(world,T.GATHERER_HUT,Vector3(-15,0,-20))
	var house=F.building(world,T.HOME,Vector3(8,0,-18))
	var house2=F.building(world,T.HOME,Vector3(18,0,-22))
	var store=F.building(world,T.STORAGE,Vector3(30,0,24))
	var a=world.residents[1]
	var b=world.residents[2]
	var c=world.residents[3]
	pc.assign_profession(a.id,P.SAWYER);pc.assign_profession(b.id,P.SAWYER)
	var baseline:=state(world)
	var observer:=func(_id): notifications+=1
	pc.profession_changed.connect(observer);pc.work_assignment_changed.connect(observer)
	pc.home_changed.connect(func(_id,_old,_new): notifications+=1)
	var nav_checks: int=world.navigation.last_smoothing_checks
	var original_navigation = world.navigation
	var probe := NavigationProbe.new()
	world.navigation=probe
	world.world_locations.navigation=probe
	world.building_uses.navigation=probe
	for person in pc.get_residents():
		for role in P.values(): check(pc.profession_eligibility_error(person.id,role).is_empty(),"Registered resident eligible independently of buildings")
		pc.get_workplace_roles(saw.id);pc.get_workplace_roles(house.id)
		pc.home_assignment_error(person.id,house.id)
		pc.workplace_assignment_error(person.id,saw.id,P.SAWYER)
	check(probe.requests==0,"Read-only admission queries perform zero point/radius path searches")
	world.navigation=original_navigation
	world.world_locations.navigation=original_navigation
	world.building_uses.navigation=original_navigation
	check(state(world)==baseline and notifications==0 and world.navigation.last_smoothing_checks==nav_checks,"Read-only queries preserve fields/revision/signals/jobs/reservations/navigation diagnostics")
	check(not pc.profession_eligibility_error("missing",P.SAWYER).is_empty() and not pc.profession_eligibility_error(a.id,999).is_empty(),"Query rejects missing resident/unknown profession")
	world.game_ui.open_window(&"residents")
	world.resident_selection.select_building(saw)
	dialog.open_for(a.id)
	check(dialog.buttons.keys()==[P.SAWYER,P.PORTER],"Sawmill exposes exactly Sawyer and Porter")
	check(dialog.execute(P.SAWYER) and a.profession==P.SAWYER and a.work_location_id==saw.id,"Explicit real PlayerControl assignment")
	check(not dialog.visible and window.visible and world.resident_selection.selected_building==saw,"Success closes only dialog, keeps window/building")
	window._flush()
	check(window.rows[a.id].get_text(1)=="Пильщик" and pc.get_production_workers(saw.id)==[a],"Actual row and personnel count updated")
	dialog.open_for(a.id)
	check(dialog.buttons[P.SAWYER].disabled and dialog.reasons[P.SAWYER].visible and dialog.reasons[P.SAWYER].text.contains("уже"),"Already assigned disabled with visible reason")
	dialog.close()
	pc.assign_profession(b.id,P.LUMBERJACK)
	var area=world.work_areas.create(Vector2(-700,-250),375)
	pc.assign_work_area(b.id,area.id)
	dialog.open_for(b.id)
	check(dialog.buttons[P.SAWYER].disabled and dialog.reasons[P.SAWYER].text.contains("профессию"),"A FREE lumberjack is not implicitly changed to Sawyer")
	var old: Array=[b.profession,b.work_location_id,b.work_area_id,b.work_assignment_revision]
	check(not dialog.execute(P.SAWYER) and old==[b.profession,b.work_location_id,b.work_area_id,b.work_assignment_revision],"Capacity refusal preserves previous FREE assignment atomically")
	check(dialog.visible and window.visible and world.resident_selection.selected_building==saw,"Refusal preserves all context")
	check(not pc.assign_workplace(b.id,saw.id,P.SAWYER) and old==[b.profession,b.work_location_id,b.work_area_id,b.work_assignment_revision],"Explicit bootstrap also preserves FREE assignment on full capacity")
	dialog.close()
	pc.clear_work_assignment(a.id)
	pc.assign_profession(b.id,P.SAWYER) # A separate explicit player choice, before the workplace offer.
	dialog.open_for(b.id)
	check(not dialog.buttons[P.SAWYER].disabled,"Freed role available")
	pc.assign_workplace(c.id,saw.id,P.SAWYER)
	check(dialog.buttons[P.SAWYER].disabled and not dialog.execute(P.SAWYER) and b.work_area_id.is_empty(),"Fresh recheck rejects capacity occupied while dialog open")
	world.resident_selection.select_building(gather)
	check(not dialog.visible and window.visible,"A2 closes stale dialog on building change")
	dialog.open_for(b.id)
	check(dialog.buttons.keys()==[P.GATHERER,P.PORTER],"Gatherer exposes only real worker/Porter roles")
	world.resident_selection.select_building(house)
	dialog.open_for(b.id)
	check(dialog.buttons.has(&"home") and dialog.buttons.has(&"clear_home") and not dialog.buttons.has(P.PORTER),"House housing actions, no fictional Porter")
	check(dialog.execute(&"home") and b.household_id==HH.id_for(house.id),"Housing through existing assign_home")
	check(world.building_card_view().housing_count.text=="Жильцы: 1 / 4","Home signal updates Blue housing counter without a different general snapshot")
	dialog.open_for(b.id)
	check(dialog.buttons[&"home"].disabled and not dialog.buttons[&"clear_home"].disabled,"Already housed state and existing clear_home action")
	check(dialog.execute(&"clear_home") and b.household_id==&"","Existing clear_home executes")
	check(world.building_card_view().housing_count.text=="Жильцы: 0 / 4","Clear home updates Blue count immediately")
	pc.assign_home(b.id,house2.id)
	# Normal registered residents fill all four beds, without changing house capacity.
	var extras:=[]
	for index in range(4):
		var resident=preload("res://scripts/resident_data.gd").new("bed_%d"%index,"Жилец",24)
		pc.register_resident(resident);pc.assign_home(resident.id,house.id);extras.append(resident)
	dialog.open_for(b.id)
	check(dialog.buttons[&"home"].disabled and dialog.reasons[&"home"].text.contains("свободных"),"Full house visible reason")
	check(not dialog.execute(&"home") and b.household_id==HH.id_for(house2.id),"Failed housing preserves old home")
	dialog.close()
	pc.clear_home(extras[0].id)
	dialog.open_for(b.id)
	pc.assign_home(extras[0].id,house.id)
	check(not dialog.execute(&"home") and b.household_id==HH.id_for(house2.id),"Housing capacity rechecked at execute")
	dialog.close()
	world.placement.select(D.for_type(T.SAWMILL))
	world.placement.update_world_position(Vector3(-42,0,20))
	var site=world.placement.confirm()
	world.resident_selection.select_building(site)
	dialog.open_for(b.id)
	check(dialog.buttons.keys()==[P.SAWYER,P.PORTER] and dialog.buttons.values().all(func(button): return button.disabled),"UC applicability known, both roles disabled")
	check(dialog.reasons[P.SAWYER].text=="Здание ещё строится","UC readable reason")
	preload("res://tests/construction_recipe_expectations.gd").complete(site,false)
	check(site.complete_construction(),"Existing domain completion after real required materials/work")
	check(site.is_built() and not dialog.buttons[P.SAWYER].disabled,"Same UC to BUILT live admission updates without stale callback")
	world.cancel_construction(site.id) # BUILT deletion remains forbidden; no new demolition.
	dialog.close()
	world.resident_selection.select_building(saw)
	dialog.open_for(extras[1].id)
	pc.unregister_resident(extras[1].id)
	check(not dialog.visible,"Removed resident closes dialog immediately")
	dialog.open_for(b.id)
	pc.unregister_building(saw.id)
	check(not dialog.visible,"Removed destination closes dialog immediately")
	# Captured identity rejects a different instance reusing the same ID.
	world.resident_selection.select_building(gather)
	dialog.open_for(b.id)
	var replacement=preload("res://scripts/building_instance.gd").new(gather.id,gather.definition,gather.position)
	var index: int=world.buildings.find(gather)
	world.buildings[index]=replacement
	check(not dialog.execute(P.GATHERER) and not dialog.visible,"Same ID different building identity rejected")
	world.buildings[index]=gather
	# Committed actual carrying is not cancelled by the assignment UI.
	var actor=world.resident_runtimes[0]
	pc.assign_workplace(actor.data.id,world.warehouse_data.id,P.PORTER)
	world.warehouse_data.resources.add(R.LOG,1)
	var candidate=Candidate.new()
	candidate.source=world.warehouse_data
	candidate.source_ref=Source.new(Source.Kind.CONTAINER,world.warehouse_data.id)
	candidate.destination=gather;candidate.resource_type=R.LOG
	# Gatherer does not accept LOG. Use a registered new Sawmill destination.
	var dest=F.building(world,T.SAWMILL,Vector3(0,0,-20))
	candidate.destination=dest
	var job=world.logistics._claim_delivery(actor.data,candidate)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Actual committed Porter haul starts")
	if job!=null:
		for step in range(4000):
			actor.view._physics_process(0.05)
			if world.logistics._executors[actor.data.id].handling.operation==&"loading": break
		world.game_time.debug_skip_minutes(10)
		check(job.state in [Job.State.CARRYING,Job.State.GOING_TO_DESTINATION] and actor.data.inventory.amount==1,"Actual pickup/handling enters carrying")
		world.resident_selection.select_building(store)
		dialog.open_for(actor.data.id)
		check(dialog.execute(P.PORTER) and actor.data.work_location_id==store.id and job.is_active(),"UI reassigns Porter without cancelling old committed job")
		for leg in range(8):
			if not job.is_active(): break
			F.walk(world,actor)
			world.game_time.debug_skip_minutes(10)
		check(job.state==Job.State.COMPLETED and dest.resources.get_amount(R.LOG)==1 and actor.data.inventory.amount==0,"Captured old destination receives cargo exactly once after UI reassign")
		check(world.warehouse_data.resources.get_reserved_out(R.LOG)==0 and dest.resources.get_reserved_in(R.LOG)==0,"Committed haul reservations fully released")
	world.free()
	print("E4 assignment dialog: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
