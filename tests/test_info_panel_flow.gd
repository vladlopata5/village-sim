extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Def=preload("res://scripts/building_definition.gd")
const Types=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Slot=preload("res://scripts/world_3d/building_slot_3d.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.game_time.total_minutes=420
	for runtime in world.resident_runtimes:
		runtime.decision._deciding=true
		runtime.intents.abort_current(runtime.intents.current_intent)
		runtime.view.set_physics_process(false)
		for need in runtime.data.needs.values(): need.value=0
	var actor=world.resident_runtimes[0]
	var a=actor.data
	var b=world.residents[1]
	Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(5,0,8)))
	check(world._request_haul_work(actor),"Normal Porter workflow creates real committed job")
	var job=world.logistics.get_job(a.id)
	var destination=world.player_control.get_building(job.destination_location_id)
	var store_result: Dictionary=world.debug_spawn.spawn_building(Vector3(29,0,-15),Def.for_type(Types.STORAGE))
	check(store_result.ok,"New normal workplace registered")
	var store=store_result.objects[0]
	check(world.player_control.assign_workplace(a.id,store.id,P.PORTER),"Normal explicit reassignment")
	world.resident_selection.select(a)
	var panel=world.game_ui.info_panel
	panel.set_expanded(true)
	panel.select_tab(&"work")
	var resident=world.resident_card_view()
	check(resident.work_place_label.text.contains(store.display_name) and resident.intent_label.text.contains(destination.display_name),"New assignment and captured old delivery displayed separately")
	check(world.logistics.get_job(a.id)==job and job.is_active(),"Card/reassignment does not cancel or redirect committed job")
	resident.clear_work_button.pressed.emit()
	check(a.work_location_id.is_empty() and job.is_active() and resident.intent_label.text.contains(destination.display_name),"Clear workplace preserves committed transportation")
	world.resident_selection.select_building(destination)
	panel.select_tab(&"info")
	var building=world.building_card_view()
	var marker=world.building_uses.acquire(destination.id,Slot.Purpose.COURIER,a.id,actor.view.get_world_position())
	check(marker!=null,"Actual marker occupancy API")
	var body: VBoxContainer=building.get_node("%People")
	check(building.get_node("%StaffSummary").text.contains("Носильщики: 0 / 2") and body.get_children().any(func(row): return row is Label and row.text=="Курьерское посещение"),"Physical courier is visible separately and never counted as assigned Porter")
	check(body.get_children().any(func(row): return row is HBoxContainer and row.get_child(0) is Button and row.get_child(0).text==a.resident_name),"Visitor name remains independently visible")
	var people_before:=body.get_children()
	var tabs_before: Array=panel.get_node("Column/Tabs").get_children()
	for iteration in range(50): building._refresh()
	check(body.get_children()==people_before and panel.get_node("Column/Tabs").get_children()==tabs_before,"Unchanged refresh does not rebuild lists or tabs")
	world.building_uses.release(destination.id,marker,a.id)
	check(not body.get_children().any(func(row): return row is Label and row.text=="Курьерское посещение"),"Actual slots_changed removes released physical occupant")
	world.logistics.cancel_job(job)
	var homes: Array=[]
	for point in [Vector3(-15,0,15),Vector3(-25,0,15)]:
		var result: Dictionary=world.debug_spawn.spawn_building(point,Def.for_type(Types.HOME))
		check(result.ok,"Normal home registration")
		homes.append(result.objects[0])
	world.player_control.assign_home(b.id,homes[0].id)
	world.resident_selection.select_building(homes[0])
	var home_row=body.get_children().filter(func(node): return node is HBoxContainer)[0]
	var stale_clear: Button=home_row.get_child(1)
	world.player_control.assign_home(b.id,homes[1].id)
	stale_clear.pressed.emit()
	check(b.home_location_id==homes[1].id,"Stale housing action revalidates owner and preserves new assignment")
	world.resident_selection.select(a)
	a.set_opinion(StringName(b.id),8)
	a.set_opinion(StringName(b.id),0)
	check(resident.get_node("%RelationshipLinks").get_child_count()==1 and resident.get_node("%RelationshipLinks").get_child(0).text.ends_with("+0"),"Known neutral record remains visible without creating missing records")
	var stale_link: Button=resident.get_node("%RelationshipLinks").get_child(0)
	world.player_control.unregister_resident(b.id)
	stale_link.pressed.emit()
	check(world.resident_selection.selected_resident==a,"Stale relationship link resolves missing ID safely")
	world.free()
	print("E2 flow regressions: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
