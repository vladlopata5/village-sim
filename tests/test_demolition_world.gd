extends SceneTree
const B=preload("res://scripts/building_instance.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Phase=preload("res://scripts/resident_builder_controller.gd").Phase
const Purpose=preload("res://scripts/building_slot_purpose.gd").Type
const Intent=preload("res://scripts/resident_intent.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
var world: Node
var checks:=0
var failures:=0
var observer: Callable # External rendered adapter; no permanent diagnostic hooks in production.
func _initialize() -> void:call_deferred("run")
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func capture(label: String, building: RefCounted) -> void:
	if observer.is_valid():await observer.call(world,label,building)
func start_world() -> void:
	world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_time.total_minutes=420;world.game_logger.console_enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true;actor.schedule._phase="День";actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
func site_at(point: Vector3, category: int = T.HOME) -> RefCounted:
	world.placement.select(D.for_type(category));world.placement.update_world_position(point)
	var site=world.placement.confirm();check(site!=null,"Ordinary site creation")
	return site
func built_at(point: Vector3, category: int) -> RefCounted:
	var result: Dictionary=world.debug_spawn.spawn_building(point,D.for_type(category));check(result.ok,"Ordinary built fixture")
	return result.objects[0] if result.ok else null
func fill_site(site: RefCounted) -> void:
	for resource in site.definition.construction_requirements:check(site.add_delivered_material(resource,site.get_required_amount(resource)),"Delivered fixture material")
func ground_amount(resource: int) -> int:
	var count:=0
	for drop in world.ground_resources.drops:
		if drop.resource_type==resource:count+=drop.amount
	return count
func walk(actor: Node) -> void:
	for step in range(16000):
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving():break
func begin_work(actor: Node) -> void:
	actor.intents.abort_current(actor.intents.current_intent)
	check(actor.builder.request_work(),"Builder accepts structural work normally")
	walk(actor)
	check(actor.builder.phase==Phase.BUILDING,"Builder reaches actual construction slot")
func finish_work(site: RefCounted, actor: Node) -> void:
	for cycle in range(10):
		if site.is_built() or site.state==B.State.REMOVED:return
		world.game_time.total_minutes=420
		begin_work(actor)
		world.game_time.debug_skip_minutes(60)
		world._poll_building_work()
	check(site.is_built() or site.state==B.State.REMOVED,"Structural operation terminates")
func run() -> void:
	start_world();await physics_frame
	# No refund from undelivered recipes; full delivered refund at zero progress.
	for quantity in [0,3,8]:
		var cancel_site=site_at(Vector3(5+quantity*2,0,22))
		if quantity>0:check(cancel_site.add_delivered_material(R.LOG,quantity),"Partial actual delivery")
		var before:=ground_amount(R.LOG)
		await capture("cancel_site_before_cancel_%d" % quantity,cancel_site)
		if quantity==0:
			world.resident_selection.select_building(cancel_site)
			check(world.building_card_view().get_node("%Demolish").text=="Отменить строительство","Actual card shows valid cancellation command")
			world.building_card_view().get_node("%Demolish").pressed.emit()
			check(cancel_site.state==B.State.REMOVED,"UI invokes immediate cancellation")
		else: check(world.cancel_construction(cancel_site.id) and cancel_site.state==B.State.REMOVED,"Zero work cancels instantly")
		check(ground_amount(R.LOG)-before==quantity,"Only actual delivered amount returns")
		check(world.build_grid.occupied_cells(cancel_site.id).is_empty() and world.world_locations.get_view(cancel_site.id)==null,"Footprint and location removed")
		check(not world.cancel_construction(cancel_site.id),"Repeat cancellation cannot issue second refund")
		await capture("cancel_site_after_cancel_%d" % quantity,cancel_site)
	world.free();await process_frame
	start_world();await physics_frame
	var actor=world.resident_runtimes[0]
	check(world.player_control.assign_profession(actor.data.id,P.BUILDER),"Builder profession")
	var site=site_at(Vector3(5,0,22));fill_site(site)
	begin_work(actor);world.game_time.debug_skip_minutes(35)
	check(site.construction_progress==35,"Actual resident minutes build partial structure")
	check(world.cancel_construction(site.id) and site.construction_progress==35 and not world.build_grid.occupied_cells(site.id).is_empty(),"Partial cancel reverses, retains structure")
	begin_work(actor);world.game_time.debug_skip_minutes(15)
	check(site.construction_progress==20,"Fifteen actual demolition minutes remove fifteen work")
	await capture("partial_demolition",site)
	var old_fraction: float=world.game_time._fractional_minutes
	check(world.change_construction_direction(site.id,false) and site.construction_progress==20 and world.game_time._fractional_minutes==old_fraction,"Reverse preserves exact progress and clock fraction")
	await capture("restoring_site",site)
	finish_work(site,actor)
	check(site.is_built() and site.construction_progress==180,"Restored original construction completes normally")
	# House assignment and portal occupant, followed by recoverable demolition.
	var tenant=world.resident_runtimes[1]
	check(world.player_control.assign_home(tenant.data.id,site.id),"House assigned")
	tenant.schedule.work_decision=Callable();tenant.schedule._on_phase_changed("Ночь");walk(tenant)
	check(tenant.view.is_inside_building(site.id),"Real sleep marker occupied")
	check(world.change_construction_direction(site.id,true),"Built house demolition begins")
	check(tenant.data.home_location_id.is_empty() and not tenant.view.is_inside_building(site.id) and world.building_uses.inside_count(site.id)==0,"Eviction plus existing portal exit")
	check(not world.building_uses.choices(site.id,Purpose.SLEEP,Vector3.ZERO).size(),"Offline house cannot admit ordinary use")
	begin_work(actor);world.game_time.debug_skip_minutes(30)
	check(site.construction_progress==150,"Built demolition starts from full work")
	await capture("built_demolition",site)
	check(world.change_construction_direction(site.id,false),"Undo built demolition")
	finish_work(site,actor)
	check(site.is_built() and tenant.data.home_location_id.is_empty(),"Restored home active without restoring residents")
	await capture("restored_house",site)
	check(world.change_construction_direction(site.id,true),"Demolish again")
	finish_work(site,actor)
	check(site.state==B.State.REMOVED and ground_amount(R.LOG)==4 and ground_amount(R.STONE)==1,"Ready house returns half recipe, no delivered double refund")
	check(world.demolition_results[site.id].planned_loss[R.LOG]==4,"Planned loss tracked separately")
	await capture("house_removed",site)
	world.free();await process_frame
	start_world();await physics_frame
	actor=world.resident_runtimes[0];world.player_control.assign_profession(actor.data.id,P.BUILDER)
	var warehouse=built_at(Vector3(5,0,22),T.STORAGE)
	var categories=preload("res://scripts/resource_category.gd").Type
	check(warehouse.resources.set_category_quotas({categories.LOG:10,categories.STONE:10,categories.PLANK:10,categories.SIMPLE_FOOD:10,categories.MUSHROOM:10,categories.WOOL:10,categories.WOOL_CLOTH:10,categories.SIMPLE_CLOTHING:10,categories.WHEAT:5,categories.SHEAF:5,categories.STRAW:5}),"Fixture quotas for all concrete contents including wool")
	for resource in R.values():check(warehouse.resources.add(resource,5),"All actual content types seeded")
	var porter=world.resident_runtimes[1]
	check(world.player_control.assign_workplace(porter.data.id,warehouse.id,P.PORTER),"Porter assigned")
	var profession: int=porter.data.profession
	var skills: Dictionary=porter.data._skill_xp.duplicate(true)
	var delivery=built_at(Vector3(14,0,22),T.FOOD)
	var job=world.logistics.claim_transport(porter.data.id,Source.new(Source.Kind.CONTAINER,warehouse.id),delivery,R.FOOD,func():return true)
	check(job!=null and world.logistics.start_claimed_job(job,porter.data.id),"Actual outgoing reservation/haul")
	check(world.change_construction_direction(warehouse.id,true),"Offline warehouse with active haul")
	check(porter.data.work_location_id.is_empty() and porter.data.profession==profession and porter.data._skill_xp==skills,"Only workplace removed, profession preserved")
	check(world.logistics.get_job(porter.data.id)==null and warehouse.resources.get_reserved_out(R.FOOD)==0 and delivery.resources.get_reserved_in(R.FOOD)==0,"Owned outbound and inbound reservations released")
	check(not world.logistics.sources.available(Source.new(Source.Kind.CONTAINER,warehouse.id),R.LOG),"Offline stock not exported")
	await capture("offline_warehouse",warehouse)
	# A future delayed exit must block the terminal operation even after work reaches zero.
	warehouse.construction_progress=0
	var marker=world.world_locations.get_view(warehouse.id).get_markers(preload("res://scripts/world_3d/building_slot_3d.gd"))[0]
	marker.occupant=porter.data.id
	world._poll_building_work()
	check(warehouse.state!=B.State.REMOVED,"Inside occupant bars final removal")
	marker.occupant=""
	world.ready_for_play=false;world._poll_building_work()
	check(warehouse.resources.get_total_amount()==R.size()*5 and not warehouse.removal_started,"Technical unready world leaves all concrete content types untouched")
	world.ready_for_play=true;world._poll_building_work()
	check(warehouse.state==B.State.REMOVED and warehouse.resources.get_total_amount()==0,"Drain and final removal")
	for resource in R.values():
		var refund: int=floori(warehouse.get_required_amount(resource)*0.5)
		check(ground_amount(resource)==5+refund,"Exact per-type content plus half material balance")
	await capture("warehouse_refund",warehouse)
	# Paid production inputs are spent; no promised product is refunded.
	var cook=world.resident_runtimes[2]
	check(world.player_control.assign_workplace(cook.data.id,delivery.id,P.COOK),"Cook workplace")
	check(delivery.resources.add(R.MUSHROOM,1),"One cooking input")
	var batch=delivery.claim_production_work(cook.data.id)
	check(batch!=null and batch.begin(cook.data.id),"Actual paid production batch")
	check(world.change_construction_direction(delivery.id,true) and batch.is_terminal(),"Demolition cancels paid batch")
	check(delivery.resources.get_amount(R.MUSHROOM)==0 and delivery.resources.get_amount(R.FRIED_MUSHROOM)==0 and delivery.resources.get_total_reserved_in()==0,"No paid ingredient refund or invented output")
	check(world.interactions.get_interactions([cook.data.id],delivery.id).is_empty(),"Offline building has no stale ordinary context actions")
	check(cook.data.profession==P.COOK and cook.data.work_location_id.is_empty(),"Cook retains profession")
	check(world.change_construction_direction(delivery.id,false) and delivery.is_built(),"Unworked demolition can immediately restore full structure")
	check(not delivery.production_removed and delivery.resources.get_amount(R.FOOD)==0,"Functionality restored without inventing stock")
	# Both shuffled regions preserve footprint priority, are stable and not row-major.
	var footprint: Array=world.build_grid.occupied_cells(delivery.id)
	var shuffled: Array=world._demolition_cells(footprint,123)
	check(shuffled==world._demolition_cells(footprint,123) and shuffled.slice(0,footprint.size())!=footprint,"Seeded local candidate order")
	for index in range(shuffled.size()):
		var cell: Vector2i=shuffled[index]
		if index<footprint.size():check(cell in footprint,"Footprint first")
		else:check(footprint.any(func(member):return (member-cell).length_squared()<=4),"Halo at most two cells from footprint")
	check(world.warehouse_data.definition.construction_work_required==240 and world.warehouse_data.definition.max_builders==2,"Approved Town Center work definition")
	world.free();await process_frame
	print("Demolition world: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
