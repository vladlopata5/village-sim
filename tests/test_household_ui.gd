extends "res://tests/test_households.gd"
## Actual canonical cards and existing picker; synthetic second unit tests only UI extensibility.
func select_unit(world: Node, home: RefCounted, unit: RefCounted) -> void:
	world.resident_selection.select_building(home)
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.info_panel.select_tab(unit.id)
func offer(world: Node, home: RefCounted, unit: RefCounted, person: RefCounted) -> bool:
	select_unit(world,home,unit)
	world.building_card_view().household_views[unit.id].button.pressed.emit()
	check(world.settlement_panel.visible and world.assignment_dialog.household_id==unit.id,"Existing picker captures selected stable household ID before resident selection")
	world.settlement_panel.activate_row(person.id)
	return world.assignment_dialog.visible and world.assignment_dialog.household_id==unit.id
func run() -> void:
	var world=F.create(self);await process_frame
	var pc=world.player_control;var panel=world.game_ui.info_panel;var card=world.building_card_view();var dialog=world.assignment_dialog
	check(world.debug_spawn.spawn_residents(Vector3(-18,0,24),5,P.NONE).created==5,"Additional actual residents for independent units and full-house refusal")
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.view.set_physics_process(false)
	var people: Array=world.residents
	var site=place(world,T.HOME,Vector3(3,0,22))
	world.resident_selection.select_building(site);panel.set_expanded(true)
	check(panel._tabs==[&"info"] and card.household_views.is_empty() and card.construction_section.visible,"Unfinished HOME exposes construction controls without housing")
	preload("res://tests/construction_recipe_expectations.gd").complete(site,false);site.complete_construction()
	check(panel._tabs==[&"info",site.households[0].id] and card.household_views[site.households[0].id].title.text=="Хозяйство №1 — 0/4" and not card.construction_section.visible,"B1 completion exposes exactly one empty household tab")
	var a=F.building(world,T.HOME,Vector3(-12,0,16));var b=F.building(world,T.HOME,Vector3(-22,0,16))
	var first=a.households[0];var other=b.households[0]
	select_unit(world,a,first);panel.select_tab(&"info")
	check(panel._tabs==[&"info",first.id] and panel.active_tab==&"info","HOME I uses Info and exactly one real household")
	check(card.tab_title(first.id)=="Хозяйство 1" and card.housing_summary.text.contains("Уровень: I") and card.housing_summary.text.contains("Хозяйств: 1") and card.housing_summary.text.contains("вместимость: 4"),"Info shows level, household count and capacity")
	check(not card.get_node("%Demolish").disabled and not card.upgrade_section.visible,"Existing D1 retained; HOME II upgrade not invented")
	await observe(world,a,"info")
	panel.select_tab(first.id)
	var view: Dictionary=card.household_views[first.id]
	check(view.title.text=="Хозяйство №1 — 0/4" and view.places.get_child_count()==4,"Empty household has its own title and four places")
	check(view.places.get_children().all(func(row):return row.get_child(0).text.ends_with("Свободно")),"All four empty places explicitly marked free")
	check(view.body.visible and not card.get_node("%Info").visible and card.get_node("%People").get_child_count()==0,"No duplicate tenants list in Info")
	await observe(world,a,"empty")
	var role: Array=[people[0].profession,people[0].work_location_id]
	check(offer(world,a,first,people[0]),"Existing assignment dialog opens for concrete unit")
	check(dialog.title_label.text.contains("Хозяйство №1"),"Dialog shows target unit")
	await observe(world,a,"assignment-dialog")
	check(dialog.execute(&"home") and people[0].household_id==first.id and role==[people[0].profession,people[0].work_location_id],"Unit assignment leaves profession and work intact")
	check(card.household_views[first.id].places.get_child(0).get_child(0).text==people[0].resident_name,"Real resident name appears synchronously")
	var changes: Array=[]
	pc.household_changed.connect(func(id,old,next):changes.append([id,old,next]))
	check(pc.assign_household(people[0].id,first.id) and changes.is_empty(),"Repeated domain command has no duplicate membership/event")
	check(offer(world,a,first,people[0]) and dialog.buttons[&"home"].disabled and not dialog.execute(&"home") and changes.is_empty(),"Repeated UI action cannot create extra assignment")
	dialog.close()
	for index in range(1,4):check(offer(world,a,first,people[index]) and dialog.execute(&"home"),"Four normal assignments fit")
	check(view.title.text=="Хозяйство №1 — 4/4" and view.places.get_child_count()==4 and pc.get_household_occupants(first.id).size()==4,"Full unit has exactly four unique rows")
	check(view.places.get_children().map(func(row):return row.get_child(0).text)==people.slice(0,4).map(func(person):return person.resident_name),"All names correspond to actual membership")
	await observe(world,a,"full")
	check(pc.assign_household(people[4].id,other.id),"Fifth resident has another prior home")
	check(offer(world,a,first,people[4]) and dialog.buttons[&"home"].disabled and not dialog.execute(&"home") and people[4].household_id==other.id,"Full-unit refusal preserves previous household and shows a reason")
	check(not dialog.reasons[&"home"].text.is_empty(),"Capacity refusal is readable")
	dialog.close()
	check(offer(world,b,other,people[0]) and dialog.execute(&"home") and pc.get_household_occupants(first.id).size()==3 and pc.get_household_occupants(other.id).size()==2,"UI performs atomic cross-house move")
	await observe(world,b,"move")
	select_unit(world,a,first)
	var sleeper: Node=world.resident_runtimes[1];sleeper.schedule.work_decision=Callable()
	world.game_time.total_minutes=1380;sleeper.schedule._on_phase_changed("Ночь");sleep_arrival(sleeper)
	var committed: RefCounted=sleeper.intents.current_intent
	var needs: Array=[sleeper.data.hunger,sleeper.data.fatigue,sleeper.data.profession,sleeper.data.work_location_id]
	check(sleeper.data.activity==Activity.SLEEPING and world.building_uses.occupied_by(a.id,sleeper.data.id,3),"Prepare actual occupied physical sleep slot for UI eviction")
	card.household_views[first.id].places.get_child(0).get_child(1).pressed.emit()
	check(sleeper.data.household_id.is_empty() and sleeper.data.activity==Activity.SLEEPING and sleeper.intents.current_intent==committed and world.building_uses.occupied_by(a.id,sleeper.data.id,3),"Household eviction changes permanent residence without waking accepted sleep")
	check(card.household_views[first.id].title.text=="Хозяйство №1 — 2/4" and card.household_views[first.id].places.get_child_count()==4 and needs==[sleeper.data.hunger,sleeper.data.fatigue,sleeper.data.profession,sleeper.data.work_location_id],"Freed logical place and unchanged needs/work are independent of temporary bed claim")
	sleeper.schedule._on_phase_changed("Утро");world.game_time.total_minutes=420
	world.resident_selection.select(people[0]);panel.set_expanded(true);panel.select_tab(&"bio")
	check(world.resident_card_view().home_label.text.contains(str(b.id)) and world.resident_card_view().home_label.text.contains("Хозяйство: №1"),"Resident card resolves home and local household number")
	await observe(world,b,"resident-household")
	# Observer captures may select the house; select resident explicitly for the existing clear action.
	world.resident_selection.select(people[0]);world.resident_card_view().get_node("%ClearHome").pressed.emit()
	check(people[0] in pc.get_residents() and people[0].household_id.is_empty() and world.resident_card_view().home_label.text=="Жильё: Не назначено","Resident eviction keeps the resident and updates homeless text")
	await observe(world,b,"eviction")
	check(offer(world,a,first,people[0]),"Prepare stale dialog")
	var stale_offer: Callable=dialog.buttons[&"home"].pressed.get_connections()[0].callable
	world.resident_selection.select_building(b)
	check(not dialog.visible and not world.settlement_panel.visible and not stale_offer.call() and people[0].household_id.is_empty(),"Changing building cancels both captured dialog and old picker context")
	check(offer(world,a,first,people[0]),"Prepare tab invalidation")
	panel.select_tab(&"info")
	check(not dialog.visible and not world.settlement_panel.visible and people[0].household_id.is_empty(),"Changing tab cannot retarget an open household offer")
	check(offer(world,a,first,people[0]),"Prepare closed-card invalidation")
	panel._close()
	check(not dialog.visible and not world.settlement_panel.visible and world.resident_selection.selected_entity==null,"Closing card clears pending household context")
	check(offer(world,a,first,people[0]),"Prepare collapsed-card invalidation")
	panel.set_expanded(false)
	check(not dialog.visible and not world.settlement_panel.visible,"Collapsed household tab cannot keep an actionable offer")
	select_unit(world,a,first);card.household_views[first.id].button.pressed.emit()
	panel.select_tab(&"info");world.settlement_panel.activate_row(people[0].id)
	check(not dialog.visible and not world.settlement_panel.visible and people[0].household_id.is_empty(),"Tab invalidation before choosing a resident also closes the stale picker")
	# Controlled domain fixture only: no HOME II level, upgrade plan or physical slots enabled.
	a.definition.housing_capacity=8;a.ensure_households();a.construction_changed.emit()
	var second=a.households[1]
	select_unit(world,a,first)
	var retained: Node
	check(panel._tabs==[&"info",first.id,second.id] and card.tab_title(second.id)=="Хозяйство 2","Actual second unit generates its own tab dynamically")
	check(offer(world,a,first,people[6]),"Prepare switch to a different household")
	panel.select_tab(second.id)
	check(not dialog.visible and people[6].household_id.is_empty(),"Switching to second household cancels first offer rather than retargeting it")
	check(offer(world,a,second,people[5]) and dialog.execute(&"home") and people[5].household_id==second.id,"Assignment targets second stable ID, not first unit or ordinal guess")
	check(pc.get_household_occupants(second.id)==[people[5]] and pc.get_household_occupants(first.id).size()==2,"Second unit displays independent occupants")
	world.resident_selection.select(people[5]);check(world.resident_card_view().home_label.text.contains("Хозяйство: №2"),"Resident card shows second unit number")
	select_unit(world,a,second)
	var stale_clear: Button=card.household_views[second.id].places.get_child(0).get_child(1)
	pc.clear_household(people[5].id);pc.assign_household(people[5].id,second.id)
	stale_clear.pressed.emit()
	check(people[5].household_id==second.id,"Removed row callback cannot evict a later assignment to the same household")
	var tabs: Array=panel.get_node("Column/Tabs").get_children();var rows: Array=card.household_views[second.id].places.get_children()
	var requests: int=world.decision_dispatcher.requests
	for repeat in 30:card._refresh()
	check(panel.get_node("Column/Tabs").get_children()==tabs and card.household_views[second.id].places.get_children()==rows and world.decision_dispatcher.requests==requests,"Unchanged polling reuses rows/tabs and triggers no AI")
	check(offer(world,a,second,people[6]),"Prepare removal of active unit")
	retained=card.household_views[first.id].body
	pc.clear_household(people[5].id);a._households.erase(second);a.definition.housing_capacity=4;a.construction_changed.emit()
	check(panel.active_tab==&"info" and not card.household_views.has(second.id) and not dialog.visible,"Missing active household falls back safely and cancels offer")
	check(card.household_views[first.id].body==retained,"Adding/removing another unit preserves first unit view")
	# Same ID, new object must not reuse an old widget/offer identity.
	select_unit(world,a,first)
	var old_view: Node=card.household_views[first.id].body;var old_button: Button=card.household_views[first.id].button
	a._households[0]=Household.new(a.id,1);a.construction_changed.emit()
	old_button.pressed.emit()
	check(card.household_views[first.id].body!=old_view and not world.settlement_panel.visible,"Recreated unit invalidates old widget identity")
	first=a.households[0]
	check(offer(world,a,first,people[7]),"Prepare resident removal")
	pc.unregister_resident(people[7].id)
	check(not dialog.visible and not dialog.execute(&"home"),"Removed resident cannot execute captured offer")
	check(offer(world,a,first,people[0]),"Prepare D1 invalidation")
	check(world.change_construction_direction(a.id,true),"D1 starts via existing building command")
	check(not dialog.visible and panel._tabs==[&"info"] and card.household_views.is_empty() and pc.get_home_occupants(a.id).is_empty(),"D1 removes accessible household tabs and assignments immediately")
	check(world.change_construction_direction(a.id,false) and panel._tabs==[&"info",first.id] and card.household_views[first.id].title.text=="Хозяйство №1 — 0/4","Restored house retains ID and returns empty household tab")
	await observe(world,a,"demolition-context")
	check(offer(world,a,first,people[0]),"Prepare direct building removal")
	pc.unregister_building(a.id)
	check(not dialog.visible and world.resident_selection.selected_entity==null,"Direct unregister closes housing card and offer")
	world.free();await process_frame
	print("Household UI: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
