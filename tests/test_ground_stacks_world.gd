extends SceneTree
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const Drop=preload("res://scripts/cargo_drop_result.gd")
const Job=preload("res://scripts/haul_job.gd")
var world: Node
var checks:=0
var failures:=0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func _initialize() -> void: call_deferred("run")
func walk(actor: Node) -> void:
	for step in range(4000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func capture(label: String, focus: Vector3) -> void:
	if not "--render-qa" in OS.get_cmdline_user_args(): return
	var camera=world.get_viewport().get_camera_3d()
	var forward: Vector3=-camera.global_basis.z
	var center: Vector3=camera.global_position+forward*(-camera.global_position.y/forward.y)
	camera.global_position+=Vector3(focus.x-center.x,0,focus.z-center.z)
	camera.set_zoom_distance(10/(2*tan(deg_to_rad(camera.fov/2))))
	await process_frame
	await RenderingServer.frame_post_draw
	var folder="C:/Users/SW/Documents/Codex/outputs/resource-stacks-e1-2b/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	world.get_viewport().get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.debug_set_time_of_day(7,0)
	world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	await physics_frame
	check(world.ground_resources.is_stack_mode(),"Canonical world enables the empty cell registry")
	var nav_revision: int=world.navigation.revision
	var point=C.to_sim(Vector3(5,0,18))
	var placed: Dictionary=world.place_ground_resources(R.LOG,12,point)
	check(placed.placed==12 and placed.discarded==0 and placed.stack_ids.size()==2,"LOG batch fills ten then spills two nearby")
	var log_stack=world.ground_resources.get_by_id(placed.stack_ids[0])
	var partial=world.ground_resources.get_by_id(placed.stack_ids[1])
	check(log_stack.amount==10 and partial.amount==2 and log_stack.cell!=partial.cell,"One type per cell and 10-unit capacity")
	var id: StringName=partial.id
	var same_point: Vector2=partial.world_position
	check(world.place_ground_resources(R.LOG,3,same_point).placed==3 and partial.amount==5 and partial.id==id,"Replenishment preserves stable identity")
	var stone_result: Dictionary=world.place_ground_resources(R.STONE,9,point)
	check(stone_result.placed==9 and stone_result.stack_ids.size()==3,"STONE spills as 4+4+1")
	for stone_id in stone_result.stack_ids:
		var stone=world.ground_resources.get_by_id(stone_id)
		check(stone.resource_type==R.STONE and stone.amount<=4 and stone.cell!=log_stack.cell,"STONE does not mix with LOG")
	check(world.navigation.revision==nav_revision,"Stacks never occupy navigation")
	var view: Node=world._ground_views[partial]
	check(view.quantity_label.visible and view.quantity_label.text=="×5","Replenishment updates one Label3D")
	await capture("stacks-before",Vector3(5,0,18))
	check(partial.reserve(&"one",4) and partial.reserve(&"two",1),"Two owners reserve different units")
	check(world.ground_resources.take_reserved(partial,&"one",4) and partial.amount==1 and partial.id==id and partial.reserved_amount(&"two")==1,"Partial pickup keeps other owner and ID")
	check(not view.quantity_label.visible,"One remaining unit hides the label")
	await capture("stacks-after",Vector3(5,0,18))
	var cell: Vector2i=partial.cell
	check(world.ground_resources.take_reserved(partial,&"two") and world.ground_resources.get_by_id(id)==null and world.ground_resources.get_at(cell)==null and not world._ground_views.has(partial),"Last pickup removes ID/cell/view")
	await process_frame
	check(not is_instance_valid(view),"Removed view and label are freed")
	# Two real HaulExecutors pick from the same stack into ordinary container deliveries.
	var food_result: Dictionary=world.place_ground_resources(R.FOOD,3,C.to_sim(Vector3(8,0,-12)))
	var food=world.ground_resources.get_by_id(food_result.stack_ids[0])
	var spawned: Dictionary=world.debug_spawn.spawn_building(Vector3(20,0,-20),D.for_type(T.FOOD))
	check(spawned.ok,"Ordinary food destination exists")
	var dest=spawned.objects[0]
	var ref=Source.new(Source.Kind.GROUND,food.id)
	var jobs: Array=[]
	var actors: Array=[world.resident_runtimes[0],world.resident_runtimes[1]]
	for actor in actors:
		check(world.logistics.use_executor(actor.data,world.game_time,world.world_locations,actor.intents,actor.schedule),"Real executor available")
		var job=world.logistics.claim_transport(actor.data.id,ref,dest,R.FOOD,func():return true)
		check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Shared-stack haul starts")
		jobs.append(job)
	check(food.reserved_total()==2 and food.available_amount()==1 and jobs[0].id!=jobs[1].id,"Two jobs own independent units from one SourceRef")
	await process_frame
	await process_frame
	check(world.food_availability._count_ground()==1,"Shared food hint counts free units despite another reservation")
	for actor in actors:walk(actor)
	world.game_time.debug_skip_minutes(10)
	check(food.amount==1 and food.reserved_total()==0 and actors.all(func(actor):return actor.data.inventory.amount==1),"Two physical pickups remove exactly two units")
	if "--render-qa" in OS.get_cmdline_user_args():
		for step in range(20): actors[0].view._physics_process(0.05) # Separate real carriers along their committed route for the screenshot.
	await capture("two-carriers",Vector3(8,0,-12))
	for step in range(8):
		for actor in actors:walk(actor)
		world.game_time.debug_skip_minutes(10)
		await process_frame
		if jobs.all(func(job):return job.state==Job.State.COMPLETED):break
	check(jobs.all(func(job):return job.state==Job.State.COMPLETED) and dest.resources.get_amount(R.FOOD)==2 and dest.resources.get_reserved_in(R.FOOD)==0 and actors.all(func(actor):return actor.data.inventory.amount==0),"Both shared-stack hauls complete once with no orphan promises")
	# A genuine exhausted worker search differs from technical failure.
	var carrier=actors[0]
	carrier.view.global_position=Vector3(5,0,28)
	check(carrier.data.inventory.put(R.PLANK,1),"One real cargo before exhausted placement")
	world.runtime_placement_blockers.register_circle(&"test_no_space",func():return Vector3(5,0,28),20.0,true)
	check(carrier.data.inventory.drop_cargo(world._drop_cargo.bind(carrier))==Drop.Status.DISCARDED and carrier.data.inventory.amount==0,"All worker cells blocked: approved disposal clears inventory")
	world.runtime_placement_blockers.unregister(&"test_no_space")
	carrier.data.inventory.put(R.PLANK,1)
	world.ready_for_play=false
	check(carrier.data.inventory.drop_cargo(world._drop_cargo.bind(carrier))==Drop.Status.FAILED and carrier.data.inventory.amount==1,"Invalid world API preserves cargo instead of disposal")
	world.ready_for_play=true
	check(carrier.data.inventory.drop_cargo(world._drop_cargo.bind(carrier))==Drop.Status.PLACED and carrier.data.inventory.amount==0,"Valid retry uses canonical worker placement")
	var bad: Dictionary=world.place_ground_resources(R.LOG,1,Vector2(INF,0))
	check(bad.remaining==1 and bad.discarded==0,"Invalid position is not overflow destruction")
	world.runtime_placement_blockers.register_circle(&"test_no_space",func():return Vector3(12,0,28),20.0,true)
	var overflow: Dictionary=world.place_ground_resources(R.LOG,20,C.to_sim(Vector3(12,0,28)))
	check(overflow.placed==0 and overflow.discarded==20 and overflow.remaining==0,"Natural radius-two search can discard blocked new yield")
	world.runtime_placement_blockers.unregister(&"test_no_space")
	# Expiry and renewal operate on whole stacks, preserving reserved units.
	var life_result: Dictionary=world.place_ground_resources(R.LOG,3,C.to_sim(Vector3(16,0,28)))
	var life=world.ground_resources.get_by_id(life_result.stack_ids[0])
	var old_time: int=life.created_at
	world.game_time.total_minutes+=100
	world.place_ground_resources(R.LOG,1,life.world_position)
	check(life.created_at==world.game_time.total_minutes and life.created_at>old_time,"Top-up renews the whole stack")
	life.reserve(&"protected")
	world.game_time.total_minutes=life.created_at+life.lifetime
	world.ground_resources._on_minute(world.game_time.total_minutes)
	check(life.amount==1 and life.reserved_amount(&"protected")==1,"Only free expired units vanish")
	life.release(&"protected")
	check(world.ground_resources.get_by_id(life.id)==null,"Release expires the remaining unowned unit")
	var unbound=preload("res://scripts/ground_resources.gd").new()
	unbound.enable_stack_mode()
	var not_setup: Dictionary=unbound.place_near(R.LOG,1,Vector2i(128,80),unbound.PlacementMode.WORKER)
	check(not_setup.remaining==1 and not_setup.discarded==0,"Missing clock setup is FAILED, not approved overflow")
	unbound.free()
	world.free()
	print("Canonical stacks: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
