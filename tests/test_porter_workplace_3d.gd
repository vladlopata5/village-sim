extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const Definition = preload("res://scripts/building_definition.gd")
const CandidateValue = preload("res://scripts/delivery_candidate.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Purpose = preload("res://scripts/building_slot_purpose.gd").Type
const Job = preload("res://scripts/haul_job.gd")
var checks := 0
var failures := 0
var rendered := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func quiet(actor: Node) -> void:
	actor.decision._deciding=true
	actor.view.set_physics_process(false)
	actor.intents.abort_current(actor.intents.current_intent)
	for need in actor.data.needs.values():
		need.value=0
		need.base_weight=0
func fixture() -> Dictionary:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.decision_dispatcher.set_process(false)
	for actor in world.resident_runtimes: quiet(actor)
	var places: Dictionary = {BT.TOWN_CENTER:world.warehouse_data}
	for row in [[BT.LUMBERJACK_HUT,Vector3(0,0,-20)],[BT.SAWMILL,Vector3(12,0,-20)],[BT.STORAGE,Vector3(30,0,20)],[BT.QUARRY,Vector3(45,0,20)],[BT.GATHERER_HUT,Vector3(-15,0,20)],[BT.FOOD,Vector3(0,0,20)]]:
		var created: Dictionary = world.debug_spawn.spawn_building(row[1],Definition.for_type(row[0]))
		check(created.ok,"Real normal BUILT spawn")
		if created.ok: places[row[0]]=created.objects[0]
	world.game_time.debug_skip_minutes(60)
	world.decision_dispatcher.clear()
	return {"world":world,"places":places,"actor":world.resident_runtimes[0],"other":world.resident_runtimes[1]}
func walk(actor: Node) -> void:
	for step in 4000:
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func finish(f: Dictionary, actor: Node, job: RefCounted) -> void:
	for boundary in 6:
		if not job.is_active(): break
		walk(actor)
		await process_frame
		f.world.game_time.debug_skip_minutes(10)
func capture(f: Dictionary, name: String, selected: RefCounted = null) -> void:
	if not rendered: return
	if selected!=null: f.world.resident_selection.select_building(selected)
	var camera: Camera3D = f.world.get_node("World/Camera3D")
	var focus: Vector3 = preload("res://scripts/world_3d/world_coordinates.gd").to_world(selected.position) if selected!=null else f.actor.view.get_world_position()
	camera.position=focus+camera.basis.z*40
	camera.size=30
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/porter-workplace-implementation/rendered/"+name+".png")
func run() -> void:
	rendered="--rendered" in OS.get_cmdline_user_args()
	for stage in ["going_source","waiting","loading","carrying","going_destination","unloading"]:
		var stage_fixture := fixture()
		if stage_fixture.places.size()!=7:
			stage_fixture.world.free()
			continue
		await physics_frame
		var stage_base = stage_fixture.places[BT.TOWN_CENTER]
		var destination = stage_fixture.places[BT.SAWMILL]
		var next_place = stage_fixture.places[BT.QUARRY]
		stage_base.resources.add(R.LOG,2)
		var stage_candidate := CandidateValue.new()
		stage_candidate.source=stage_base
		stage_candidate.source_ref=Source.new(Source.Kind.CONTAINER,stage_base.id)
		stage_candidate.destination=destination
		stage_candidate.resource_type=R.LOG
		check(stage_fixture.world.player_control.assign_workplace(stage_fixture.actor.data.id,stage_base.id,P.PORTER),"Own starting Town staffing")
		var held_job: RefCounted
		if stage=="waiting":
			check(stage_fixture.world.player_control.assign_workplace(stage_fixture.other.data.id,stage_base.id,P.PORTER),"Second legal Town Porter")
			held_job=stage_fixture.world.logistics._claim_delivery(stage_fixture.other.data,stage_candidate)
			check(held_job!=null and stage_fixture.world.logistics.start_claimed_job(held_job,stage_fixture.other.data.id),"Real second visitor")
			walk(stage_fixture.other)
			check(stage_fixture.other.view._marker!=null,"Second visitor physically holds source COURIER")
		var stage_job = stage_fixture.world.logistics._claim_delivery(stage_fixture.actor.data,stage_candidate)
		check(stage_job!=null and stage_fixture.world.logistics.start_claimed_job(stage_job,stage_fixture.actor.data.id),"Actual first physical haul")
		if stage_job==null:
			stage_fixture.world.free()
			continue
		var reassigned: Array = []
		var carry_callback := func():
			if stage_job.state==Job.State.CARRYING:
				reassigned.append(stage_fixture.world.player_control.assign_workplace(stage_fixture.actor.data.id,next_place.id,P.PORTER))
		if stage=="carrying": stage_fixture.world.logistics.changed.connect(carry_callback)
		if stage!="going_source": walk(stage_fixture.actor)
		if stage=="waiting": check(stage_fixture.actor.view._waiting and stage_fixture.actor.view._marker==null,"Real COURIER waiting")
		if stage=="loading":
			stage_fixture.world.game_time.debug_skip_minutes(3)
			check(stage_fixture.world.logistics._executors[stage_fixture.actor.data.id].handling.operation==&"loading","Partial source handling")
		if stage in ["carrying","going_destination","unloading"]:
			stage_fixture.world.game_time.debug_skip_minutes(10)
			check(stage_fixture.actor.data.inventory.amount==1,"Physical pickup after loading")
		if stage=="unloading":
			walk(stage_fixture.actor)
			stage_fixture.world.game_time.debug_skip_minutes(3)
			check(stage_fixture.world.logistics._executors[stage_fixture.actor.data.id].handling.operation==&"unloading","Partial destination handling")
		if stage!="carrying": check(stage_fixture.world.player_control.assign_workplace(stage_fixture.actor.data.id,next_place.id,P.PORTER),"Management reassignment during "+stage)
		else:
			stage_fixture.world.logistics.changed.disconnect(carry_callback)
			check(reassigned==[true],"Reassignment at actual CARRYING publication boundary")
		check(stage_job.workplace_location_id==stage_base.id and stage_fixture.actor.data.work_location_id==next_place.id and stage_job.is_active(),"Old confirmed job and new relationship stay separate")
		check(stage_fixture.world.player_control.get_porters(next_place.id).size()==1,"New staffing place taken immediately")
		if stage=="waiting":
			await capture(stage_fixture,"town-courier-wait",stage_base)
			stage_fixture.world.logistics._executors[stage_fixture.other.data.id].cancel("release source visitor")
			await process_frame
		await finish(stage_fixture,stage_fixture.actor,stage_job)
		check(stage_job.state==Job.State.COMPLETED and stage_fixture.actor.data.inventory.amount==0 and destination.resources.get_amount(R.LOG)==1 and stage_base.resources.get_amount(R.LOG)==1,"Original delivery completes exactly once after "+stage)
		check(stage_fixture.world.logistics._inbound.is_empty() and stage_fixture.world.logistics.sources._claims.is_empty() and stage_fixture.actor.view._marker==null and not stage_fixture.actor.view._waiting,"Reservations and portal clean after completion")
		next_place.resources.add(R.STONE,1)
		stage_fixture.actor.decision._deciding=false
		stage_fixture.world.decision_dispatcher.clear()
		stage_fixture.actor.decision.request_decision("new_assignment_after_committed")
		await process_frame
		stage_fixture.world.decision_dispatcher._process(0)
		var next_job = stage_fixture.world.logistics.get_job(stage_fixture.actor.data.id)
		check(next_job!=null and next_job.source_location_id==next_place.id and next_job.workplace_location_id==next_place.id,"Next ordinary AI work uses new Quarry assignment")
		if next_job!=null:
			stage_fixture.actor.decision._deciding=true
			stage_fixture.world.logistics._executors[stage_fixture.actor.data.id].cancel("fixture cleanup")
		if stage=="unloading": await capture(stage_fixture,"sawmill-delivery",destination)
		stage_fixture.world.free()
	# Physical production-site exports and warehouse Ground import through ordinary AI.
	var flow := fixture()
	for row in [[BT.LUMBERJACK_HUT,R.LOG],[BT.SAWMILL,R.PLANK],[BT.STORAGE,R.FOOD]]:
		var base = flow.places[row[0]]
		check(flow.world.player_control.assign_workplace(flow.actor.data.id,base.id,P.PORTER),"Real production/storage explicit workplace")
		if row[0]==BT.STORAGE:
			flow.world.ground_resources.create_drop(R.FOOD,2,preload("res://scripts/world_3d/world_coordinates.gd").to_sim(Vector3(30,0,24)))
		else: base.resources.add(row[1],1)
		flow.actor.decision._deciding=false
		flow.world.decision_dispatcher.clear()
		flow.actor.decision.request_decision("rendered_site_work")
		await process_frame
		flow.world.decision_dispatcher._process(0)
		flow.actor.decision._deciding=true
		var delivery = flow.world.logistics.get_job(flow.actor.data.id)
		check(delivery!=null and delivery.workplace_location_id==base.id and delivery.resource_type==row[1],"Ordinary WORK creates physical own-endpoint delivery")
		if delivery==null: continue
		walk(flow.actor)
		await capture(flow,"workplace_%d_loading"%row[0],base)
		flow.world.game_time.debug_skip_minutes(10)
		walk(flow.actor)
		await capture(flow,"workplace_%d_unloading"%row[0],base)
		await finish(flow,flow.actor,delivery)
		check(delivery.state==Job.State.COMPLETED and flow.actor.data.inventory.amount==0,"Physical production/storage delivery finished")
	flow.world.free()
	# Canonical self-logistics remains independent from all Porter staffing.
	var self_flow := fixture()
	self_flow.world.player_control.assign_profession(self_flow.actor.data.id,P.NONE)
	var sawyer = self_flow.other
	var sawmill = self_flow.places[BT.SAWMILL]
	check(self_flow.world.player_control.assign_workplace(sawyer.data.id,sawmill.id),"Canonical Sawyer production assignment")
	self_flow.world.ground_resources.create_drop(R.LOG,1,preload("res://scripts/world_3d/world_coordinates.gd").to_sim(Vector3(8,0,-14)))
	check(self_flow.world._request_work(sawyer),"Sawyer supplies itself without Porter")
	var supply = self_flow.world.logistics.get_job(sawyer.data.id)
	await finish(self_flow,sawyer,supply)
	check(supply.state==Job.State.COMPLETED and sawmill.resources.get_amount(R.LOG)==1,"Canonical physical self-supply completes")
	check(self_flow.world._request_work(sawyer),"Unchanged recipe starts")
	walk(sawyer)
	self_flow.world.game_time.debug_skip_minutes(17)
	await capture(self_flow,"canonical-sawyer-production",sawmill)
	self_flow.world.game_time.debug_skip_minutes(13)
	check(sawmill.resources.get_amount(R.PLANK)==1 and sawmill.resources.get_amount(R.LOG)==0,"Thirty-minute LOG-to-PLANK recipe unchanged")
	check(self_flow.world._request_work(sawyer),"Sawyer self-exports without Porter")
	var exported = self_flow.world.logistics.get_job(sawyer.data.id)
	await finish(self_flow,sawyer,exported)
	check(exported.state==Job.State.COMPLETED and sawmill.resources.get_amount(R.PLANK)==0,"Self-export completes through same executor")
	var gatherer = self_flow.world.resident_runtimes[2]
	var gathering_place = self_flow.places[BT.GATHERER_HUT]
	check(self_flow.world.player_control.assign_workplace(gatherer.data.id,gathering_place.id),"Canonical Gatherer production assignment")
	gathering_place.resources.add(R.FOOD,5)
	check(self_flow.world._request_work(gatherer),"Full Gatherer buffer self-exports without Porter")
	var food_job = self_flow.world.logistics.get_job(gatherer.data.id)
	walk(gatherer)
	await capture(self_flow,"canonical-gatherer-self-export",gathering_place)
	await finish(self_flow,gatherer,food_job)
	check(food_job.state==Job.State.COMPLETED and gathering_place.resources.get_amount(R.FOOD)==4,"Canonical Gatherer physical self-export preserved")
	self_flow.world.free()
	# Existing interactions expose both roles, and refuse full staffing at click time.
	var f := fixture()
	var hut = f.places[BT.GATHERER_HUT]
	var options: Array = f.world.interactions.get_interactions([f.other.data.id],hut.id)
	check(options.any(func(option): return option.id==&"employment" and option.enabled) and options.any(func(option): return option.id==&"porter_employment" and option.enabled),"Minimal UI exposes distinct production and Porter management")
	var porter_option = options.filter(func(option): return option.id==&"porter_employment")[0]
	check(f.world.interactions.execute([f.other.data.id],porter_option) and f.other.data.profession==P.PORTER,"Real InteractionService explicit Porter action")
	check(not f.world.interactions.execute([f.actor.data.id],porter_option),"Click-time recheck rejects stale free-place option")
	f.world.resident_selection.select(f.other.data)
	check(f.world.get_node("HUD/ResidentCard").work_place_label.text.contains(hut.display_name),"ResidentCard current assignment")
	await capture(f,"gatherer-staff-categories",hut)
	f.world.resident_selection.select(f.other.data)
	f.world.player_control.clear_work_assignment(f.other.data.id)
	check(f.world.get_node("HUD/ResidentCard").work_place_label.text.contains("Носильщик без рабочего места"),"Visible unassigned Porter status")
	f.world.decision_dispatcher.clear()
	f.actor.decision._deciding=false
	f.actor.decision.request_decision("pending")
	check(f.world.decision_dispatcher.pending_count()==1,"Ordinary work queued")
	f.world.player_control.assign_workplace(f.actor.data.id,f.places[BT.STORAGE].id,P.PORTER)
	f.world.player_control.assign_workplace(f.actor.data.id,f.places[BT.TOWN_CENTER].id,P.PORTER)
	check(f.world.decision_dispatcher.pending_count()==0,"Same-frame ABA cancels old queued context")
	f.actor.decision._deciding=true
	f.places[BT.TOWN_CENTER].resources.add(R.LOG,1)
	var own = f.places[BT.TOWN_CENTER]
	var candidate := CandidateValue.new()
	candidate.source=own
	candidate.source_ref=Source.new(Source.Kind.CONTAINER,own.id)
	candidate.destination=f.places[BT.SAWMILL]
	candidate.resource_type=R.LOG
	var job = f.world.logistics._claim_delivery(f.actor.data,candidate)
	check(job!=null and f.world.logistics.start_claimed_job(job,f.actor.data.id),"Removal fixture claims real job")
	if job!=null:
		walk(f.actor)
		f.world.game_time.debug_skip_minutes(10)
		f.world.player_control.unregister_resident(f.actor.data.id)
		check(job.state==Job.State.CANCELLED and f.actor.data.inventory.amount==0 and not f.world.logistics._executors.has(f.actor.data.id) and f.world.decision_dispatcher.pending_count()==0,"Existing unregister unbinds haul and pending work locally")
		check(f.world.ground_resources.drops.any(func(drop): return drop.resource_type==R.LOG and drop.amount==1) and f.world.logistics._inbound.is_empty() and f.actor.view._marker==null,"Real carried cargo survives unregister cleanup")
	f.world.logistics.remove_building(hut.id)
	check(f.world.player_control.get_building(hut.id)==null and f.world.player_control.get_porters(hut.id).is_empty(),"Existing removal clears assignment metadata")
	f.world.free()
	print("Porter workplace 3D: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
