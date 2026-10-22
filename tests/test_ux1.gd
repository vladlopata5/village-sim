extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const D=preload("res://scripts/building_definition.gd")
const Stacks=preload("res://tests/ground_stack_fixture.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
func professions() -> void:
	var w=F.create(self);var pc=w.player_control;var a=w.residents[1]
	var cook=F.building(w,T.FOOD,Vector3(-12,0,-18))
	var saw=F.building(w,T.SAWMILL,Vector3(-24,0,10))
	var gather=F.building(w,T.GATHERER_HUT,Vector3(-24,0,-18))
	pc.clear_work_assignment(a.id)
	for role in [P.COOK,P.SAWYER,P.GATHERER,P.PORTER,P.LUMBERJACK,P.MINER,P.BUILDER,P.NONE]:
		check(pc.assign_profession(a.id,role) and a.profession==role and a.work_location_id.is_empty(),"Profession without an automatic building: "+str(role))
	pc.assign_profession(a.id,P.COOK)
	check(pc.assign_workplace(a.id,cook.id,P.COOK,true),"Explicit current-profession assignment")
	var revision: int=a.work_assignment_revision
	pc.assign_profession(a.id,P.COOK)
	check(a.work_location_id==cook.id and a.work_assignment_revision==revision,"Compatible same role is unchanged")
	pc.assign_profession(a.id,P.PORTER)
	check(a.work_location_id==cook.id and pc.get_porters(cook.id)==[a] and pc.get_production_workers(cook.id).is_empty(),"Compatible role retains the exact current building")
	pc.assign_profession(a.id,P.SAWYER)
	check(a.work_location_id.is_empty() and pc.get_porters(cook.id).is_empty(),"Incompatible role releases membership without finding the available sawmill")
	check(not pc.assign_workplace(a.id,cook.id,P.COOK,true) and a.profession==P.SAWYER,"UI admission cannot change profession")
	check(pc.assign_workplace(a.id,saw.id,P.SAWYER,true),"Sawyer explicitly takes sawmill")
	check(pc.assign_workplace(a.id,gather.id,P.GATHERER) and a.profession==P.GATHERER,"Explicit scenario bootstrap remains supported")
	w.free()
func contexts() -> void:
	var w=F.create(self);var pc=w.player_control;var selection=w.resident_selection
	var a=w.residents[1];var b=w.residents[3]
	var kitchen=F.building(w,T.FOOD,Vector3(-12,0,-18))
	var other=F.building(w,T.FOOD,Vector3(4,0,-18))
	pc.assign_profession(a.id,P.COOK);pc.assign_profession(b.id,P.COOK)
	selection.select(a);w.game_ui.info_panel.set_expanded(true)
	w.game_ui.open_window(&"buildings");await settle()
	var before: int=a.work_assignment_revision
	w.buildings_window.activate_row(kitchen.id)
	var dialog=w.assignment_dialog
	check(dialog.visible and selection.selected_resident==a and a.work_location_id.is_empty(),"Resident + Buildings captures two distinct objects without assignment")
	check(not dialog.buttons[P.COOK].disabled and dialog.buttons[P.PORTER].disabled,"Only the matching role can be confirmed")
	var stale_action: Callable=dialog.buttons[P.COOK].pressed.get_connections()[0].callable
	dialog.close();w.buildings_window.activate_row(other.id)
	check(not stale_action.call() and a.work_location_id.is_empty(),"Old button callback cannot confirm a newly opened target")
	dialog.close();w.buildings_window.activate_row(kitchen.id)
	check(dialog.execute(P.COOK) and a.work_location_id==kitchen.id and a.work_assignment_revision==before+1,"Confirmation assigns exactly once")
	check(not dialog.execute(P.COOK) and a.work_assignment_revision==before+1,"Repeated callback has no effect")
	selection.select(b);w.buildings_window.activate_row(kitchen.id)
	check(dialog.buttons[P.COOK].disabled and not dialog.execute(P.COOK) and b.work_location_id.is_empty(),"Full workplace rejected in reverse list")
	dialog.close();selection.select_building(kitchen);w.game_ui.open_window(&"residents");await settle()
	w.settlement_panel.activate_row(b.id)
	check(dialog.buttons[P.COOK].disabled,"Building + Residents uses the same full-place check")
	dialog.close();pc.clear_work_assignment(a.id)
	w.settlement_panel.activate_row(b.id)
	check(not dialog.buttons[P.COOK].disabled and dialog.execute(P.COOK) and b.work_location_id==kitchen.id,"Forward direction assigns with the same API")
	pc.assign_profession(a.id,P.MINER);selection.select(a);w.game_ui.open_window(&"buildings");await settle()
	w.buildings_window.activate_row(other.id)
	check(dialog.buttons[P.COOK].disabled and not dialog.execute(P.COOK) and a.profession==P.MINER,"Incompatible profession is never silently changed")
	dialog.close();pc.assign_profession(a.id,P.COOK)
	w.buildings_window.activate_row(other.id);selection.select(b)
	check(not dialog.visible and not dialog.execute(P.COOK) and a.work_location_id.is_empty(),"Changing resident invalidates captured action")
	selection.select(a);w.buildings_window.activate_row(other.id);w.game_ui.close_window()
	check(not dialog.visible and not dialog.execute(P.COOK),"Closing list cancels its action immediately")
	w.game_ui.open_window(&"buildings");w.buildings_window.activate_row(other.id);w.game_ui.info_panel._close()
	check(not dialog.visible and not dialog.execute(P.COOK),"Closing card clears context")
	selection.select(a);w.buildings_window.activate_row(other.id)
	pc.unregister_building(other.id)
	check(not dialog.visible and a.work_location_id.is_empty(),"Removed target cannot be assigned")
	selection.select(a);w.buildings_window.activate_row(kitchen.id)
	dialog.view_button.pressed.emit()
	check(selection.selected_building==kitchen and not dialog.visible,"Context action retains ordinary object-card viewing")
	w.game_ui.open_window(&"residents");w.settlement_panel.activate_row(a.id)
	dialog.focus_button.pressed.emit()
	check(selection.selected_resident==a and not w.settlement_panel.visible,"Show on map still selects and focuses the list target")
	w.free()
func areas() -> void:
	var w=F.create(self);var pc=w.player_control;var selection=w.resident_selection
	var a=w.residents[1];pc.assign_profession(a.id,P.LUMBERJACK)
	var area=w.work_areas.create(C.to_sim(Vector3(-15,0,-20)),C.length_to_sim(12))
	var other=w.work_areas.create(C.to_sim(Vector3(10,0,-20)),C.length_to_sim(8))
	var hut=F.building(w,T.LUMBERJACK_HUT,Vector3(-24,0,-18))
	var kitchen=F.building(w,T.FOOD,Vector3(4,0,-18))
	selection.select(a);w.game_ui.open_window(&"areas");await settle()
	var revision: int=a.work_assignment_revision
	w.work_areas_window.activate_row(area.id)
	check(w.area_departure_dialog.visible and not w.area_departure_dialog.confirm_button.disabled and a.work_area_id.is_empty(),"Resident + Areas requires confirmation even without a workplace")
	w._confirm_resident_area()
	check(a.work_area_id==area.id and a.work_assignment_revision==revision+1,"Confirmed personal area uses existing assignment")
	w._confirm_resident_area()
	check(a.work_assignment_revision==revision+1,"Area confirmation is one-shot")
	w.game_ui.open_window(&"areas");w.work_areas_window.activate_row(other.id)
	selection.select_building(hut)
	check(not w.area_departure_dialog.visible and a.work_area_id==area.id,"Context change cannot apply the old area offer")
	w.game_ui.open_window(&"areas");w.work_areas_window.activate_row(other.id)
	check(w.area_departure_dialog.visible and hut.work_area_override_id.is_empty(),"Building + Areas is also explicit")
	w._confirm_resident_area()
	check(hut.work_area_override_id==other.id,"Supported building receives actual shared WorkArea")
	selection.select_building(kitchen);w.game_ui.open_window(&"areas");w.work_areas_window.activate_row(area.id)
	check(not w.area_departure_dialog.visible and selection.selected_work_area==area,"Unsupported kitchen context opens ordinary area inspection")
	w._confirm_resident_area();check(kitchen.work_area_override_id.is_empty(),"Disabled building action cannot be forced")
	w.area_departure_dialog.close();pc.assign_profession(a.id,P.COOK);selection.select(a)
	w.work_areas_window.activate_row(area.id)
	check(not w.area_departure_dialog.visible and selection.selected_work_area==area and a.work_area_id.is_empty(),"Cook context only inspects the area and cannot receive a personal assignment")
	w.area_departure_dialog.view_button.pressed.emit()
	check(selection.selected_work_area==area and a.work_area_id.is_empty(),"Viewing an area does not assign it")
	pc.assign_profession(a.id,P.LUMBERJACK);selection.select(a);w.game_ui.open_window(&"areas");w.work_areas_window.activate_row(area.id)
	pc.remove_work_area(area.id)
	check(not w.area_departure_dialog.visible and a.work_area_id.is_empty(),"Deleted area invalidates pending confirmation")
	w.game_ui.open_window(&"areas");w.work_areas_window.activate_row(other.id);w.game_ui.close_window()
	w._confirm_resident_area();check(a.work_area_id.is_empty(),"Closed list cannot apply pending area action")
	w.free()
func radii() -> void:
	for role in [P.BUILDER,P.PORTER]:
		var w=F.create(self);var pc=w.player_control;var actor=w.resident_runtimes[1]
		for building in w.buildings:
			for r in R.values():building.resources.try_take(r,building.resources.get_available_amount(r))
		actor.view.global_position=Vector3(0,0,25)
		var workplace: RefCounted
		if role==P.BUILDER:
			var definition=D.for_type(T.HOME);definition.construction_requirements={R.PLANK:1}
			preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
			w.placement.select(definition);w.placement.update_world_position(Vector3(-40,0,25));workplace=w.placement.confirm()
			check(workplace!=null,"Builder range fixture has a real site")
			pc.assign_profession(actor.data.id,role)
		else:
			workplace=F.building(w,T.STORAGE,Vector3(-40,0,25));pc.assign_workplace(actor.data.id,workplace.id,role)
		for pair in [[3.0,true],[6.0,true],[9.0,false],[-25.0,true],[-19.0,false]]:
			var candidate_drop=Stacks.create(w.ground_resources,R.PLANK,1,C.to_sim(Vector3(pair[0],0,25)))
			await settle()
			var available: bool=actor.builder.has_work() if role==P.BUILDER else w.logistics.has_available_job(actor.data.id)
			check(available==pair[1],"Role %d: old/new/outside resident or workplace radius at x=%s" % [role,pair[0]])
			w.ground_resources.remove_drop(candidate_drop)
			await settle()
		var drop=Stacks.create(w.ground_resources,R.PLANK,1,C.to_sim(Vector3(6,0,25)))
		var route: Callable=w.logistics.sources.route_available
		w.logistics.sources.route_available=func(_from,_to):return false
		await settle()
		if role==P.BUILDER:
			# Builder uses the existing raw material planner, not Source.route_available.
			var planner: Callable=actor.builder.material_planner
			actor.builder.material_planner=func(_from,_source,_to):return {}
			actor.builder._availability_dirty=true
			check(not actor.builder.has_work(),"Expanded builder radius does not override rejected geometry/routes")
			actor.builder.material_planner=planner
		else:check(not w.logistics.has_available_job(actor.data.id),"Expanded porter radius does not override rejected routes")
		w.logistics.sources.route_available=route
		check(w.logistics.sources.ground_candidates(R.PLANK,actor.view.get_sim_position(),workplace).is_empty(),"Other professions and ordinary SUPPLY retain old admission circles")
		if role==P.BUILDER:
			actor.builder._availability_dirty=true
			check(actor.builder.request_work(),"Builder accepts a physical pickup from the additional radius")
			var phases=preload("res://scripts/resident_builder_controller.gd").Phase
			for phase in [phases.GOING_TO_SOURCE,phases.CARRYING_TO_SITE]:
				for step in range(12000):
					if actor.builder.phase!=phase:break
					preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
				preload("res://tests/handling_test_step.gd").finish(actor)
			check(workplace.get_delivered_amount(R.PLANK)==1 and actor.data.inventory.amount==0 and workplace.get_construction_reserved_in(R.PLANK)==0,"Additional-radius Builder pickup is delivered once with reservations cleared")
		w.ground_resources.remove_drop(drop);w.free()
func run() -> void:
	professions();await contexts();await areas();await radii()
	await process_frame
	print("UX1: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
