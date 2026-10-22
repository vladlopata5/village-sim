extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Fixture = preload("res://tests/settlement_3d_fixture.gd")
const Step = preload("res://tests/handling_test_step.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const D = preload("res://scripts/building_definition.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Builder = preload("res://scripts/resident_builder_controller.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fixture() -> Node:
	var world = Fixture.instantiate(); root.add_child(world)
	world.game_time.set_process(false); world.game_time.total_minutes=420
	world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true; actor.view.set_physics_process(false)
		actor.intents.abort_current(actor.intents.current_intent)
		actor.schedule._phase="День"
		for need in actor.data.needs.values(): need.value=0
	for building in world.buildings:
		for resource in R.values(): building.resources.try_take(resource,building.resources.get_available_amount(resource))
	return world
func place(world: Node, type: int, position: Vector3, built: bool = true) -> RefCounted:
	var definition = D.for_type(type)
	if not built: definition.construction_requirements={R.PLANK:1}
	preload("res://tests/construction_recipe_expectations.gd").single_stage(definition)
	world.placement.select(definition); world.placement.update_world_position(position)
	var result = world.placement.confirm()
	check(result!=null,"Real placement succeeds")
	if result!=null and built:
		for resource in definition.construction_requirements: result.add_delivered_material(resource,result.get_required_amount(resource))
		result.add_construction_work(definition.construction_work_required)
		check(result.complete_construction(),"Real construction completion")
	return result
func walk_builder(actor: Node, phase: int) -> void:
	for step in range(5000):
		if actor.builder.phase!=phase: break
		Step.move_3d(actor,0.05)
	check(actor.builder.phase!=phase,"Committed builder leg really completes")
func walk_haul(actor: Node, reason: StringName) -> void:
	for step in range(5000):
		if actor.intents.current_intent.reason_id!=reason: break
		Step.move_3d(actor,0.05)
	check(actor.intents.current_intent.reason_id!=reason,"Committed haul leg really completes")
func run() -> void:
	var world = fixture()
	var site = place(world,T.HOME,Vector3(15,0,25),false)
	var actor = world.resident_runtimes[1]
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	actor.view.global_position=Vector3(-30,0,25)
	var loose = Stacks.create(world.ground_resources,R.PLANK,1,C.to_sim(Vector3(-10,0,25)))
	check(not actor.builder.has_work(),"Builder excludes ground beyond both radii")
	var searches: int = actor.builder.source_search_count
	for repeat in range(10): check(not actor.builder.has_work(),"Unchanged negative remains negative")
	check(actor.builder.source_search_count==searches,"No repeated material planning for unchanged negative")
	site.definition.ground_search_radius=700
	check(actor.builder.has_work(),"Increasing site radius invalidates negative at decision probe")
	site.definition.ground_search_radius=0
	check(not actor.builder.has_work(),"Shrinking site radius invalidates unaccepted positive")
	actor.view.global_position=Vector3(-12,0,25)
	check(actor.builder.has_work(),"Resident movement discovers previously distant resource")
	actor.view.global_position=Vector3(-30,0,25)
	check(not actor.builder.has_work(),"Moving away excludes resource from new search")
	world.ground_resources.remove_drop(loose)
	loose=Stacks.create(world.ground_resources,R.PLANK,1,C.to_sim(Vector3(-28,0,25)))
	check(actor.builder.has_work(),"Moved resource invalidates negative without stock change")
	world.ground_resources.remove_drop(loose)
	loose=Stacks.create(world.ground_resources,R.PLANK,1,C.to_sim(Vector3(-10,0,25)))
	actor.view.global_position=Vector3(-12,0,25)
	check(actor.builder.request_work(),"Local ground becomes a real Builder claim")
	actor.view.global_position=Vector3(-30,0,25)
	actor.builder._on_world_changed()
	check(not world.logistics.sources.ground_allowed(actor.builder.source_ref,actor.view.get_sim_position(),site),"Committed source is now outside union")
	check(actor.builder.phase==Builder.Phase.GOING_TO_SOURCE and not loose.reservation_owner_id.is_empty() and site.get_construction_reserved_in(R.PLANK)==1,"Range departure does not cancel accepted reservations")
	walk_builder(actor,Builder.Phase.GOING_TO_SOURCE)
	check(actor.data.inventory.amount==1 and loose not in world.ground_resources.drops,"Accepted distant pickup transfers exactly one")
	walk_builder(actor,Builder.Phase.CARRYING_TO_SITE)
	check(site.get_delivered_amount(R.PLANK)==1 and site.get_construction_reserved_in(R.PLANK)==0 and actor.data.inventory.amount==0,"Accepted delivery preserves material balance")
	world.free()
	# A callback can change the search union before the reservation becomes a task.
	world=fixture(); site=place(world,T.HOME,Vector3(15,0,25),false); actor=world.resident_runtimes[1]
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	site.definition.ground_search_radius=0
	actor.view.global_position=Vector3(-12,0,25)
	loose=Stacks.create(world.ground_resources,R.PLANK,1,C.to_sim(Vector3(-10,0,25)))
	var move_during_claim := func():
		if not loose.reservation_owner_id.is_empty(): actor.view.global_position=Vector3(-30,0,25)
	loose.availability_changed.connect(move_during_claim)
	check(not actor.builder.request_work(),"Stale unaccepted Builder offer is rejected after callback movement")
	check(loose.reservation_owner_id.is_empty() and site.get_construction_reserved_in(R.PLANK)==0 and site.active_builder_ids.is_empty(),"Stale Builder claim rolls back exactly its owned reservations")
	loose.availability_changed.disconnect(move_during_claim)
	world.free()
	# Container sources remain global, including source plans with no local ground.
	world=fixture(); site=place(world,T.HOME,Vector3(15,0,25),false); actor=world.resident_runtimes[1]
	actor.view.global_position=Vector3(15,0,16)
	world.player_control.assign_profession(actor.data.id,P.BUILDER)
	world.warehouse_data.resources.add(R.PLANK,1)
	check(actor.builder.has_work() and actor.builder.request_work() and actor.builder.source_ref.kind==Source.Kind.CONTAINER,"Builder keeps distant storage material access")
	actor.builder.abort("fixture cleanup",false)
	check(world.warehouse_data.resources.get_reserved_out(R.PLANK)==0 and site.get_construction_reserved_in(R.PLANK)==0,"Interrupted global container claim rolls back owned reservations")
	world.free()
	# Porter own workplace only, fresh admission during claim and unchanged committed haul.
	world=fixture(); actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,world.warehouse_data.id,P.PORTER)
	actor.view.global_position=Vector3(35,0,25)
	loose=Stacks.create(world.ground_resources,R.LOG,1,C.to_sim(Vector3(20,0,32)))
	check(not world.logistics.collect_candidates(actor.data.id).any(func(row): return row.source_ref.id==loose.id),"Porter excludes distant ground even with a global own container")
	actor.view.global_position=Vector3(19,0,25)
	check(world.logistics.collect_candidates(actor.data.id).any(func(row): return row.source_ref.id==loose.id),"Porter resident circle adds new cleanup candidate")
	var job = world.logistics.claim_best_job(actor.data.id)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"Porter reserves and starts real ground haul")
	actor.view.global_position=Vector3(35,0,25)
	world.warehouse_data.definition.ground_search_radius=0
	check(world.logistics._executors[actor.data.id].validate_job(),"Committed Porter validation ignores new-search radius")
	walk_haul(actor,&"haul_source"); walk_haul(actor,&"haul_destination")
	check(job.state==Job.State.COMPLETED and world.warehouse_data.resources.get_amount(R.LOG)==1 and world.warehouse_data.resources.get_reserved_in(R.LOG)==0,"Porter completes haul after leaving original radius")
	world.free()
	# Food admission follows the actual resident, not their far workplace or home.
	world=fixture(); actor=world.resident_runtimes[1]
	actor.data.hunger=80; actor.view.global_position=Vector3(25,0,25)
	loose=Stacks.create(world.ground_resources,R.FOOD,1,C.to_sim(Vector3(12,0,25)))
	check(not actor.needs.has_food_action(),"Food on ground beyond resident circle is excluded")
	searches=actor.needs.food_probe_count
	check(not actor.needs.has_food_action() and actor.needs.food_probe_count==searches,"Unchanged negative food query is cached")
	actor.view.global_position=Vector3(14,0,25)
	check(actor.needs.has_food_action(),"Food negative cache follows movement into radius")
	check(actor.needs.try_eat(8000),"Local ground meal is reserved")
	actor.view.global_position=Vector3(25,0,25)
	check(actor.needs._food_target_valid() and actor.needs.try_eat(10000,200),"Critical merge retains accepted ground meal outside radius")
	world.free()
	# Natural workers collect loose output near themselves even outside extraction area.
	# CHOP/MINE target selection still uses the unchanged activity WorkArea.
	for row in [[T.LUMBERJACK_HUT,"Lumberjack",R.LOG,Vector3(-40,0,20)],[T.QUARRY,"Miner",R.STONE,Vector3(35,0,20)]]:
		world=fixture(); actor=world.resident_runtimes[3]
		var workplace = place(world,row[0],row[3])
		check(world.player_control.assign_workplace(actor.data.id,workplace.id),"Natural worker gets real workplace")
		actor.view.global_position=Vector3(0,0,25)
		loose=Stacks.create(world.ground_resources,row[2],1,C.to_sim(Vector3(1,0,25)))
		var controller = actor.get_node(row[1])
		check(not controller._context().area.contains(loose.world_position),"Fixture source outside unchanged extraction area")
		check(controller.best_task().get("kind")==&"COLLECT" and controller.has_work(),"Resident circle OR extraction WorkArea allows loose collection")
		check(controller.request_work(),"Collect admission is rechecked by real internal claim")
		var collected = world.logistics.get_job(actor.data.id)
		check(collected!=null and collected.admission==Job.Admission.INTERNAL,"Collection uses existing internal logistics")
		world.player_control.assign_profession(actor.data.id,P.NONE)
		check(world.logistics._executors[actor.data.id].validate_job(),"Reassignment does not cancel committed internal delivery")
		walk_haul(actor,&"haul_source");walk_haul(actor,&"haul_destination")
		check(workplace.resources.get_amount(row[2])==1 and workplace.resources.get_reserved_in(row[2])==0 and collected.state==Job.State.COMPLETED,"Natural loose output physically delivered once")
		world.free()
	await process_frame
	print("Ground search jobs: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
