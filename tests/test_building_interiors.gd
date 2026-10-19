extends SceneTree
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const ResidentView = preload("res://scripts/world_3d/resident_view_3d.gd")
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Building = preload("res://scripts/building_instance.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
const Geometry = preload("res://scripts/world_3d/world_geometry.gd")
const Resident = preload("res://scripts/resident_data.gd")
const Runtime = preload("res://scripts/resident_runtime.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
const Source = preload("res://scripts/resource_source_ref.gd")
var checks := 0
var failures := 0
var world: Node
var population: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(2000):
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving(): break
func reset(actor: Node) -> void:
	# Interior fixture drives the schedule directly, with ordinary AI disabled.
	actor.schedule.work_decision = Callable()
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.activity=Activity.IDLE
	actor.data.home_location_id=&""
	actor.schedule._phase="День"
	for need in actor.data.needs.values(): need.value=0
func building(type: int, point: Vector3, turns: int = 0, built: bool = true):
	var data = Building.new(StringName("interior_%d"%world.buildings.size()),Def.for_type(type),Coordinates.to_sim(point),Building.State.BUILT if built else Building.State.UNDER_CONSTRUCTION)
	data.quarter_turns=turns
	world.buildings.append(data)
	world._show_building(data)
	return data
func spawn(index: int) -> Node:
	var data = Resident.new("slot_actor_%d"%index,"Slot Actor %d"%index,25)
	world.residents.append(data)
	var presentation = world._create_resident_presentation(data,Vector2(0,0))
	var actor = Runtime.new()
	world.get_node("Residents").add_child(actor)
	world.resident_runtimes.append(actor)
	actor.setup(data,presentation,world.game_time,world.world_locations,world.buildings,world.fallback_housing)
	world.social_world.register(actor)
	world.player_control.register_resident(data)
	world.player_control.register_intents(data.id,actor.intents)
	world.player_control.register_commands(data.id,actor.commands)
	world.player_control.register_assignments(data.id,actor.assignments)
	actor.decision._deciding=true
	presentation.set_physics_process(false)
	return actor
func run() -> void:
	for type in Types.values():
		var definition = Def.for_type(type)
		var layout = Layouts.create(definition)
		check(Layouts.validate(layout,definition),"Every authored layout matches domain capacities")
		var slots: Array = Layouts.markers(layout,Slot)
		if definition.worker_capacity>0:
			slots.filter(func(m): return m.purpose==Slot.Purpose.WORKER)[0].purpose=Slot.Purpose.VISITOR
			check(not Layouts.validate(layout,definition),"Mismatched authored capacities rejected")
		layout.free()
	world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	world.game_time.total_minutes=420
	population=world.resident_runtimes.duplicate()
	for actor in population:
		actor.decision._deciding=true
		actor.view.set_physics_process(false)
		reset(actor)
	for index in range(7): population.append(spawn(index))
	await physics_frame
	var center=world.buildings[0]
	var home=building(Types.HOME,Vector3(22,0,18))
	var kitchen=building(Types.FOOD,Vector3(22,0,-5))
	var gather=building(Types.GATHERER_HUT,Vector3(-8,0,8))
	var saw=building(Types.SAWMILL,Vector3(35,0,8))
	check(gather.definition.worker_capacity==4,"Agreed Gatherer capacity is four")
	# Authored hierarchy rotates all entrances and slots without per-turn coordinates.
	for turn in range(4):
		var rotated=building(Types.HOME,Vector3(-45+turn*10,0,26),turn)
		var view=world.world_locations.get_view(rotated.id)
		var entry: Vector3=world.building_uses.entrance(rotated.id)
		check(not Geometry.footprint(rotated).has_point(Coordinates.world_plane(entry)),"Rotated entrance is outside footprint")
		var marker=Layouts.markers(view.layout,Slot)[0]
		check(marker.global_position.is_equal_approx(view.global_position+Basis(Vector3.UP,turn*PI/2)*marker.position),"Authored slot transforms rotate through hierarchy")
	# Four real Gatherers enter, occupy distinct places, contribute, release at cycle end.
	var worker_points: Array = []
	for index in range(4):
		var actor=population[index]
		check(world.player_control.assign_workplace(actor.data.id,gather.id),"Gatherer assignment respects four-capacity")
		check(actor.schedule.request_work(),"Worker starts entrance trip")
		check(not world.building_uses.occupied_by(gather.id,actor.data.id,0),"No advance slot reservation")
		walk(actor)
		check(world.building_uses.occupied_by(gather.id,actor.data.id,0) and actor.data.activity==Activity.WORKING,"Worker physically enters authored slot")
		worker_points.append(actor.view.global_position)
	check(worker_points.size()==4 and worker_points.all(func(p): return worker_points.count(p)==1),"Simultaneous workers never stack")
	check(not world.player_control.assign_workplace(population[4].data.id,gather.id),"Fifth worker assignment rejected by gameplay capacity")
	check(world.world_locations.get_view(gather.id).inside_count==4,"Occupied interior is transparent")
	# Actual physics picking keeps interior residents selectable through the mesh.
	var camera: Camera3D=world.get_node("World/Camera3D")
	var camera_position:=camera.position
	var camera_distance: float=camera.get_zoom_distance()
	camera.position=Coordinates.to_world(gather.position)+Vector3(30,50.56,30)
	camera.set_zoom_distance(12 / (2 * tan(deg_to_rad(camera.fov / 2))))
	await physics_frame
	var hit: Dictionary=world.pick(camera.unproject_position(population[0].view.global_position+Vector3.UP))
	check(hit.get("collider") is ResidentView,"Raycast selects interior resident through transparent building")
	world.handle_world_click(MOUSE_BUTTON_LEFT,hit)
	check(world.resident_selection.selected_resident!=null and world.resident_selection.selected_building==null,"Interior selection remains unified")
	camera.position=camera_position
	camera.set_zoom_distance(camera_distance)
	world.resident_selection.clear()
	var old_progress: int=gather.production_progress
	world.game_time.minute_changed.emit(world.game_time.total_minutes+1)
	check(gather.production_progress==old_progress and gather.resources.get_amount(Resources.MUSHROOM)==0,"Interior WORKER occupancy cannot create virtual mushrooms")
	for actor in population.slice(0,4): reset(actor)
	check(world.world_locations.get_view(gather.id).inside_count==0,"Final exit returns opaque material")
	# Event-driven WORKER wait: a transient physical occupant may outlive assignment.
	var worker=population[0]
	world.player_control.assign_workplace(worker.data.id,saw.id)
	saw.resources.add(Resources.LOG,1)
	var held=world.building_uses.acquire(saw.id,0,"transient_worker",Vector3.ZERO)
	check(world._request_work(worker),"Sawyer committed work starts despite occupied physical slot")
	walk(worker)
	check(worker.view._waiting and worker.recipe_work.phase==1,"Worker waits at entrance without starting production")
	world.building_uses.release(saw.id,held,"transient_worker")
	await process_frame
	check(world.building_uses.occupied_by(saw.id,worker.data.id,0) and worker.data.activity==Activity.WORKING,"Slot release wakes Worker event-driven")
	reset(worker)
	# Synchronous acquire listeners may force interruption before interior entry.
	var interrupt_on_acquire=func(id: StringName, purpose: int):
		if id==saw.id and purpose==0 and world.building_uses.occupied_by(saw.id,worker.data.id,0):
			worker.intents.abort_current(worker.intents.current_intent)
	world.building_uses.slots_changed.connect(interrupt_on_acquire)
	check(world._request_work(worker),"Interrupted acquisition begins regular work trip")
	walk(worker)
	check(not world.building_uses.occupied_by(saw.id,worker.data.id,0) and worker.view._marker==null,"Acquire-time interrupt cannot leak occupancy or enter")
	world.building_uses.slots_changed.disconnect(interrupt_on_acquire)
	reset(worker)
	# One Courier; delivery reservations survive a second arrival, then resume.
	var courier=population[1]
	world.player_control.assign_profession(courier.data.id,Profession.PORTER)
	var held_courier=world.building_uses.acquire(center.id,1,"transient_courier",Vector3.ZERO)
	var job=world.logistics.claim_transport(courier.data.id,Source.new(Source.Kind.CONTAINER,center.id),kitchen,Resources.FOOD,func(): return true)
	check(job!=null and world.logistics.start_claimed_job(job,courier.data.id),"Courier commits real reservations before movement")
	walk(courier)
	check(courier.view._waiting and center.resources.get_reserved_out(Resources.FOOD)==1 and kitchen.resources.get_reserved_in(Resources.FOOD)==1,"Waiting Courier retains both resource reservations")
	world.building_uses.release(center.id,held_courier,"transient_courier")
	await process_frame
	walk(courier)
	check(kitchen.resources.get_amount(Resources.FOOD)==1 and job.state==preload("res://scripts/haul_job.gd").State.COMPLETED,"Released Courier resumes real pickup/delivery")
	check(world.world_locations.get_view(center.id).inside_count==0 and world.world_locations.get_view(kitchen.id).inside_count==0,"Courier completion releases both buildings")
	reset(courier)
	# Both before-pickup and after-pickup Courier waits use existing cleanup.
	held_courier=world.building_uses.acquire(center.id,1,"transient_courier",Vector3.ZERO)
	job=world.logistics.claim_transport(courier.data.id,Source.new(Source.Kind.CONTAINER,center.id),kitchen,Resources.FOOD,func(): return true)
	world.logistics.start_claimed_job(job,courier.data.id)
	walk(courier)
	check(courier.view._waiting,"Before-pickup courier wait is active")
	reset(courier)
	check(center.resources.get_reserved_out(Resources.FOOD)==0 and kitchen.resources.get_reserved_in(Resources.FOOD)==0,"Before-pickup waiting interrupt releases both reservations")
	world.building_uses.release(center.id,held_courier,"transient_courier")
	held_courier=world.building_uses.acquire(kitchen.id,1,"transient_courier",Vector3.ZERO)
	var stock_before: int=center.resources.get_amount(Resources.FOOD)
	var drops_before: int=Stacks.total(world.ground_resources)
	job=world.logistics.claim_transport(courier.data.id,Source.new(Source.Kind.CONTAINER,center.id),kitchen,Resources.FOOD,func(): return true)
	world.logistics.start_claimed_job(job,courier.data.id)
	walk(courier)
	check(courier.view._waiting and courier.data.inventory.amount==1,"After-pickup courier waits while physically carrying resource")
	reset(courier)
	check(Stacks.total(world.ground_resources)==drops_before+1 and courier.data.inventory.amount==0 and center.resources.get_amount(Resources.FOOD)==stock_before-1 and kitchen.resources.get_reserved_in(Resources.FOOD)==0,"After-pickup waiting interrupt drops resource without restoring source")
	world.building_uses.release(kitchen.id,held_courier,"transient_courier")
	# Visitors acquire on arrival; fifth meal cancels without consuming FOOD.
	kitchen.resources.add(Resources.FOOD,10)
	for index in range(5):
		var visitor=population[index]
		reset(visitor)
		visitor.data.hunger=70
		check(visitor.needs.try_eat_at(kitchen.id,5000),"Meal reserves FOOD and travels without slot reservation")
		walk(visitor)
		check(visitor.data.activity==Activity.EATING if index<4 else visitor.data.activity==Activity.IDLE,"Four visitors enter; fifth unavailable without stacking")
	check(kitchen.resources.get_amount(Resources.FOOD)==7 and kitchen.resources.get_reserved_out(Resources.FOOD)==0,"Only four arrivals consume FOOD; fifth releases reservation")
	for actor in population.slice(0,4): reset(actor)
	var retry=population[4]
	check(retry.needs.try_eat_at(kitchen.id,5000),"Visitor can try later after free places")
	walk(retry)
	check(world.building_uses.occupied_by(kitchen.id,retry.data.id,2),"Visitor retry enters")
	reset(retry)
	# HOME priority, actual distinct Sleep positions and outdoor eleventh arrival.
	var sleeper=population[0]
	check(world.player_control.assign_home(sleeper.data.id,home.id),"Ordinary HOME assignment unchanged")
	sleeper.schedule._on_phase_changed("Ночь")
	walk(sleeper)
	check(world.building_uses.occupied_by(home.id,sleeper.data.id,3) and sleeper.data.current_sleep_quality==1.0,"HOME sleeper enters real Sleep slot with home quality")
	var home_entry: Vector3=world.building_uses.entrance(home.id)
	sleeper.data.activity=Activity.IDLE
	check(sleeper.view.global_position.is_equal_approx(home_entry) and world.world_locations.get_view(home.id).inside_count==0,"Wake releases slot and exits through entrance")
	reset(sleeper)
	# Clearing a committed sleeper frees assignment capacity, not physical occupancy.
	for index in range(4):
		var guest=population[index]
		check(world.player_control.assign_home(guest.data.id,home.id),"Four lawful HOME assignments")
		guest.schedule._on_phase_changed("Ночь")
		walk(guest)
		check(world.building_uses.occupied_by(home.id,guest.data.id,3),"Four committed HOME sleepers occupy distinct slots")
	world.player_control.clear_home(population[0].data.id)
	check(world.building_uses.occupied_by(home.id,population[0].data.id,3) and population[0].data.current_sleep_quality==1.0,"Clear HOME preserves committed physical sleep")
	check(world.player_control.assign_home(population[4].data.id,home.id),"Freed assignment capacity allows next resident")
	population[4].schedule._on_phase_changed("Ночь")
	walk(population[4])
	check(world.building_uses.occupied_by(center.id,population[4].data.id,3) and population[4].data.home_location_id==home.id,"Full physical HOME falls back to Town Center without rewriting home")
	for actor in population:
		reset(actor)
		actor.schedule._on_phase_changed("Ночь")
	check(world.fallback_housing.count(center.id)==0,"All eleven sleep trips have no advance allocation")
	var sleep_points: Array=[]
	for index in range(11):
		var guest=population[index]
		walk(guest)
		check(guest.data.activity==Activity.SLEEPING,"Every sleep arrival completes without hanging")
		check(guest.data.current_sleep_quality==1.0 if index<10 else guest.data.current_sleep_quality==0.6,"Ten interior sleepers; eleventh outdoor")
		if index<10: sleep_points.append(guest.view.global_position)
		check(guest.data.home_location_id.is_empty(),"Fallback never rewrites HOME relationship")
	check(sleep_points.all(func(p): return sleep_points.count(p)==1),"Town Center ten authored positions are distinct")
	check(world.fallback_housing.count(center.id)==10,"Fallback count reflects actual occupied Sleep slots")
	for actor in population: reset(actor)
	# Construction places are exterior, do not pass through entrance/interior.
	var site=building(Types.HOME,Vector3(35,0,25),0,false)
	for resource in site.definition.construction_requirements:
		site.reserve_construction_material(resource,site.get_required_amount(resource))
		site.deliver_reserved_construction_material(resource,site.get_required_amount(resource))
	for actor in population.slice(0,2):
		world.player_control.assign_profession(actor.data.id,Profession.BUILDER)
		check(actor.builder.request_work(),"Builder claims existing gameplay builder capacity")
		walk(actor)
		check(actor.builder.phase==preload("res://scripts/resident_builder_controller.gd").Phase.BUILDING and world.building_uses.occupied_by(site.id,actor.data.id,4),"Builder physically reaches exterior Construction place")
	check(population[0].view.global_position!=population[1].view.global_position,"Two builders use distinct perimeter positions")
	check(world.world_locations.get_view(site.id).inside_count==0,"Exterior builders never make building transparent")
	world.game_time.total_minutes+=10
	for actor in population.slice(0,2): actor.builder._on_minute(world.game_time.total_minutes)
	check(site.construction_progress==20,"Incremental work still stacks 10+10")
	for actor in population.slice(0,2): reset(actor)
	check(site.construction_progress==20,"Interrupt preserves applied construction work")
	# Spatial entrance placement index: exact rectangles, not global reachability.
	var entry_zone: Rect2=Layouts.entrance_zone(home.definition,Coordinates.to_world(home.position),0)
	check(not world.entrance_zones.validation_reason(entry_zone,Rect2(-5,-5,1,1)).is_empty(),"New footprint cannot cover existing entrance")
	check(not world.entrance_zones.validation_reason(Rect2(-5,-5,1,1),Geometry.footprint(home)).is_empty(),"New entrance cannot enter existing footprint")
	check(not world.entrance_zones.validation_reason(Rect2(-5,-5,1,1),entry_zone).is_empty(),"Entrances cannot overlap")
	var con_zone: Rect2=Layouts.entrance_zone(site.definition,Coordinates.to_world(site.position),0)
	check(not world.entrance_zones.validation_reason(con_zone,Rect2(-5,-5,1,1)).is_empty(),"UNDER_CONSTRUCTION protects entrance identically")
	world.placement.select(Def.for_type(Types.HOME))
	world.placement.update_world_position(Vector3(0,0,25))
	var proposed_zone: Rect2=world.placement.proposed_entrance_zone()
	var blocker_position:=Coordinates.from_plane(proposed_zone.get_center())
	world.runtime_placement_blockers.register_circle(&"entrance_tree",func(): return blocker_position,0.3,true)
	check(not world.placement.can_place(),"Tree/runtime blocker in entrance rejects placement")
	world.runtime_placement_blockers.unregister(&"entrance_tree")
	check(world.placement.can_place(),"No connectivity validation is imposed")
	var road_cell: Vector2i=world.roads.geometry.world_to_cell(blocker_position)
	world.roads.edit([road_cell],false)
	check(world.placement.can_place(),"Road never blocks entrance")
	var placed=world.placement.confirm()
	check(placed!=null and world.roads.contains(road_cell),"Placement retains road underneath entrance")
	check(world.cancel_construction(placed.id),"Existing cancellation releases entrance index")
	check(world.entrance_zones.validation_reason(Geometry.footprint(placed),proposed_zone).is_empty(),"Removed entrance frees placement immediately")
	world.free()
	print("Building interiors: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
