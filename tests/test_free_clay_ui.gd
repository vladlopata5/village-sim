extends "res://tests/test_resident_area_assignment_ui.gd"
var observer: Callable
func observe(world: Node,label: String) -> void:
	if observer.is_valid():await observer.call(world,label)
func finish_mining(world: Node,_actor: Node) -> void:
	world.game_time.debug_skip_minutes(60)
	await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	var world=F.create(self)
	var actor=world.resident_runtimes[0];var worker=actor.get_node("Miner")
	var camera: Camera3D=world.get_node("World/Camera3D")
	camera.set_process(false);camera.set_physics_process(false);camera.position=Vector3(-20,26,42);camera.look_at(Vector3(-20,0,16))
	var panel=world.developer_panel
	F.key(self,KEY_F10);await settle()
	check(panel.visible,"Real F10 opens developer tools")
	panel._tabs.current_tab=1;await settle()
	var buttons: Array=panel._tabs.get_child(1).get_children().filter(func(node):return node is Button and node.text=="Создать залежь глины")
	F.click(self,buttons[0]);await settle()
	var before: int=world.rocks.size()
	F.click_at(self,camera.unproject_position(Vector3(-20,0,16)));await physics_frame;await settle()
	check(world.rocks.size()==before+1 and not panel.active(),"Real F10 world click creates clay source")
	var source=world.rocks.back()
	await observe(world,"01-f10-deposit")
	F.key(self,KEY_F10);await settle()
	show_resident(world,actor);await settle()
	await create_timer(.3).timeout
	var card=world.resident_card_view()
	var index: int=card.profession_choice.get_item_index(P.CLAY_DIGGER)
	card.profession_choice.select(index);card.profession_choice.item_selected.emit(index)
	await settle()
	check(actor.data.profession==P.CLAY_DIGGER and card.area_button.visible,"Existing profession dropdown command enables personal-area controls")
	check(not worker.has_work(),"Profession alone does not grant automatic work area")
	var area=world.work_areas.create(source.position,C.length_to_sim(4))
	world.player_control.rename_work_area(area.id,"Глина — самостоятельная добыча")
	await press(card.area_button);await settle()
	await F.row_click(self,world.work_areas_window,str(area.id))
	check(world.area_departure_dialog.visible,"UX4 asks to confirm resident-area assignment")
	await press(world.area_departure_dialog.confirm_button);await settle()
	check(actor.data.work_area_id==area.id and actor.data.work_location_id.is_empty() and area.display_name in card.work_place_label.text,"Confirmed assignment shown as personal area without a hut")
	check(world.work_highlight.circle.visible and world.work_highlight.circle.position.is_equal_approx(C.to_world(area.center)+Vector3(0,.02,0)),"Selected clay digger shows personal circle")
	await observe(world,"02-personal-area")
	check(world._request_work(actor) and worker.rock==source,"Normal work entry accepts independent CLAY")
	F.walk(world,actor)
	check(worker.mining,"Worker physically reaches source")
	await observe(world,"03-free-mining")
	await finish_mining(world,actor)
	check(source.stock==9 and Stacks.total(world.ground_resources,R.CLAY)==1 and worker.rock==null and actor.data.inventory.amount==0,"Completed FREE cycle depletes source and leaves one ground clay")
	await observe(world,"04-ground-yield")
	check(worker.request_work(),"Another normal work period available")
	await press(card.clear_work_button);await settle()
	check(actor.data.profession==P.CLAY_DIGGER and actor.data.work_area_id.is_empty() and worker.rock==null and source.reservation_owner_id.is_empty(),"Real clear-area button stops accepted mining and releases claim")
	await observe(world,"05-area-cleared")
	# Reuse the same UX4 confirmation for a fresh personal assignment.
	await press(card.area_button);await settle()
	await F.row_click(self,world.work_areas_window,str(area.id))
	await press(world.area_departure_dialog.confirm_button);await settle()
	check(worker.request_work(),"Reassigned area restores work")
	world.player_control.edit_work_area(area.id,C.to_sim(Vector3(-30,0,30)),C.length_to_sim(1))
	check(worker.rock==null and source.reservation_owner_id.is_empty(),"Changing personal geometry invalidates incompatible action")
	world.player_control.clear_work_assignment(actor.data.id)
	var hut=F.building(world,T.CLAY_HUT,Vector3(-10,0,16))
	world.player_control.assign_workplace(actor.data.id,hut.id)
	# In hut mode the ordinary existing priority first COLLECTs the FREE yield.
	var job=collect_hut(world,actor)
	check(job!=null and hut.resources.get_amount(R.CLAY)==1,"Hut physically collects FREE clay using normal unit delivery")
	check(worker.request_work() and worker.rock==source and worker.committed_context.workplace==hut,"Hut mode still accepts normal clay mining")
	F.walk(world,actor);check(worker.mining,"Hut digger physically reaches deposit")
	await observe(world,"06-hut-mining")
	await finish_mining(world,actor)
	check(source.stock==8 and Stacks.total(world.ground_resources,R.CLAY)==1,"Hut mining keeps original ground-yield-before-COLLECT lifecycle")
	await observe(world,"07-hut-yield")
	world.free();await process_frame
	print("FREE clay UI: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func collect_hut(world: Node,actor: Node) -> RefCounted:
	check(world._request_work(actor),"Hut ordinary work discovers ground clay")
	var job=world.logistics.get_job(actor.data.id)
	if job==null:return null
	for step in 18000:
		if world.logistics.get_job(actor.data.id)==null:break
		preload("res://tests/handling_test_step.gd").move_3d(actor,.05)
	check(job.state==job.State.COMPLETED and actor.data.inventory.amount==0,"Hut collection completes physical pickup/delivery")
	return job
