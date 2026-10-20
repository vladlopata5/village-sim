extends SceneTree
const A=preload("res://scripts/animal_data.gd")
const E=preload("res://scripts/world_3d/animal_executor_3d.gd")
const D=preload("res://scripts/building_definition.gd")
const B=preload("res://scripts/building_instance.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const S=preload("res://scripts/building_slot_purpose.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
class Grid:
	extends "res://scripts/navigation_grid.gd"
	var queries:=0
	func find_raw_path(from: Vector3,to: Vector3) -> PackedVector3Array:
		queries+=1
		return super.find_raw_path(from,to)
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func fixture(number: int=3) -> Dictionary:
	var clock=preload("res://scripts/game_time.gd").new();root.add_child(clock);clock.set_process(false);clock.total_minutes=1200
	var nav=Grid.new(Rect2(-32,-24,64,48))
	var hut=B.new(&"shepherd_fixture",D.for_type(T.SHEPHERD_HUT))
	var view=preload("res://scripts/world_3d/building_view_3d.gd").new();root.add_child(view);view.setup(hut)
	nav.add_blocker(hut.id,Rect2(-3,-2,6,4))
	var uses=preload("res://scripts/world_3d/building_use_3d.gd").new();uses.navigation=nav;uses.register(hut,view)
	var areas=preload("res://scripts/work_areas.gd").new()
	var actors: Array=[]
	for index in number:
		var actor=E.new();root.add_child(actor);actor.navigation=nav
		actor.setup(A.new(StringName("same_%d" % index),Vector3.ZERO,Vector3(-6.25-index*.5,0,5.25)),clock)
		actor.set_physics_process(false);actor.behavior.cancel_behavior();actors.append(actor)
	return {"clock":clock,"nav":nav,"hut":hut,"view":view,"uses":uses,"areas":areas,"actors":actors}
func dispose(f: Dictionary) -> void:
	for actor in f.actors: actor.free()
	for connection in f.uses.slots_changed.get_connections(): f.uses.slots_changed.disconnect(connection.callable)
	for area in f.areas.all(): f.areas.remove(area.id)
	f.view.free();f.clock.free()
func step(f: Dictionary,delta: float=.05) -> void:
	f.clock.advance(delta)
	for actor in f.actors:actor._physics_process(delta)
func sleep_all(f: Dictionary) -> void:
	f.clock.total_minutes=1261
	for actor in f.actors:
		actor.behavior._choose(f.clock.total_minutes)
	for iteration in 3000:
		if f.actors.all(func(actor):return actor.home!=null and actor.home.is_inside()):return
		step(f)
func definition_and_capacity() -> void:
	var f=fixture(9);var hut=f.hut
	var resources=preload("res://scripts/resource_type.gd").Type
	check(hut.definition.construction_requirements=={resources.LOG:4,resources.PLANK:6},"Hut recipe exactly four logs and six planks")
	check(hut.definition.construction_work_required==D.for_type(T.GATHERER_HUT).construction_work_required,"Gatherer construction labor reused")
	check(hut.definition.worker_capacity==1 and hut.definition.porter_capacity==1 and hut.definition.worker_profession==P.SHEPHERD,"One real shepherd and optional porter")
	check(hut.definition.production_recipes.is_empty() and hut.definition.logistics_flow.is_empty() and hut.definition.planned_wool_capacity==20,"No fictitious production or wool hauling")
	var control=preload("res://scripts/player_control.gd").new();control.register_building(hut)
	for index in 3:
		var resident=preload("res://scripts/resident_data.gd").new("worker_%d" % index,"Работник",25);control.register_resident(resident)
	check(control.assign_workplace("worker_0",hut.id,P.SHEPHERD),"Shepherd role works through existing assignment API")
	check(not control.assign_workplace("worker_1",hut.id,P.SHEPHERD) and control.assign_workplace("worker_1",hut.id,P.PORTER),"Independent single worker and porter capacities")
	check(not control.assign_workplace("worker_2",hut.id,P.PORTER),"No second porter")
	check(hut.animal_housing.reserve(&"capture",f.actors[0].data.id) and hut.animal_housing.reserve(&"capture",f.actors[0].data.id) and hut.animal_housing.reserved_count()==1,"Future capacity hold idempotent")
	check(not hut.animal_housing.reserve(&"other",f.actors[0].data.id),"One reserved place per animal")
	f.actors[0].data.wool_growth=7
	check(f.actors[0].assign_home(hut,f.uses,f.areas,&"capture") and hut.animal_housing.reserved_count()==0,"Hold atomically converts into permanent membership")
	check(not hut.animal_housing.assign(A.new(&"same_0",Vector3.ZERO,Vector3.ZERO)),"Duplicate data cannot replace a stable animal identity")
	for index in range(1,8):check(f.actors[index].assign_home(hut,f.uses,f.areas),"Assign available animal place")
	check(not f.actors[8].assign_home(hut,f.uses,f.areas) and hut.animal_housing.count()==8,"Outside animals still fill capacity, ninth rejected")
	check(f.actors[0].data.id==&"same_0" and f.actors[0].data.wool_growth==7 and f.actors[0].data.status==A.Status.DOMESTIC,"Status change preserves identity and wool")
	check(f.uses.acquire(hut.id,S.ANIMAL_SLEEP,"same_0",Vector3.ZERO)==null,"Residents cannot acquire animal slots")
	var resident_slot=f.uses.acquire(hut.id,S.WORKER,"same_0",Vector3.ZERO)
	check(resident_slot!=null,"Same animal/resident ID does not collide")
	sleep_all(f) # Ninth is wild, so this deliberately uses bounded fixture steps.
	check(f.uses.inside_count(hut.id)==9 and hut.animal_housing.count()==8,"Eight animal sleep slots plus distinct worker occupancy")
	f.uses.release(hut.id,resident_slot,"same_0")
	var first=f.actors[0];var marker: Marker3D=first.home._slot
	f.uses.release(hut.id,marker,"same_0")
	check(marker.occupant=="animal:same_0","Resident release cannot steal animal ownership")
	first.release_home();first.release_home()
	check(first.data.status==A.Status.WILD and first.data.habitat_center==first.position and f.uses.inside_count(hut.id)==7,"Repeated release exits portal once and resets wild anchor to actual position")
	dispose(f)
func sleep_and_area() -> void:
	for speed in [1,2,4,10,20]:
		var f=fixture();f.clock.set_speed(speed)
		for actor in f.actors:check(actor.assign_home(f.hut,f.uses,f.areas),"Assign at x%d" % speed)
		var actor=f.actors[0];var before: Vector3=actor.position
		var area=f.areas.create(C.to_sim(Vector3(16,0,8)),C.length_to_sim(5));f.hut.work_area_override_id=area.id
		check(actor.position==before,"Area assignment never teleports")
		var offer: Dictionary=actor._wander_offer(actor.behavior.rng)
		check(not offer.is_empty() and area.contains(C.to_sim(offer.target)),"New walk uses actual custom area, not wild disk")
		check(f.areas.update_area(area.id,C.to_sim(Vector3(-10,0,8)),C.length_to_sim(4)),"Update custom boundaries")
		offer=actor._wander_offer(actor.behavior.rng)
		check(not offer.is_empty() and area.contains(C.to_sim(offer.target)) and actor.position==before,"Moved area offers physical return without relocating actor")
		f.hut.work_area_override_id=&""
		f.clock.total_minutes=1259;actor.behavior._begin_graze(1259)
		var ends: int=actor.data.behavior_ends_at;var generation: int=actor.behavior.token
		actor.behavior._on_minute(1260)
		check(actor.data.behavior==A.Behavior.GRAZE and actor.data.behavior_ends_at==ends and actor.behavior.token==generation,"21:00 does not interrupt grazing")
		sleep_all(f)
		check(f.actors.all(func(a):return a.home.is_inside() and a.data.behavior==A.Behavior.SLEEP and not a.view.visible),"All physically return before sleep at x%d" % speed)
		var wake_times: Array=f.actors.map(func(a):return a.data.wake_at)
		check(wake_times.all(func(t):return t>=1740 and t<=1860) and wake_times.min()<wake_times.max(),"Independent deterministic morning times")
		var slot: Marker3D=actor.home._slot;var token: int=actor.behavior.token
		check(not actor.claim_movement(f.view),"Sleeping animal cannot be advanced by an escort")
		var calls: int=f.nav.queries;var revision: int=f.nav.revision
		for frame in 100:actor._physics_process(.05)
		check(f.nav.queries==calls and f.nav.revision==revision and actor.home._slot==slot,"Inside animal never advances or replans outside on physics ticks")
		actor.home.arrive(token-1)
		check(actor.home._slot==slot and f.uses.inside_count(f.hut.id)==3,"Late arrival cannot enter twice")
		f.clock.total_minutes=wake_times.min();for a in f.actors:a.behavior._on_minute(f.clock.total_minutes)
		check(f.uses.inside_count(f.hut.id)<3 and f.uses.inside_count(f.hut.id)>0,"First wake releases only its own slot")
		f.clock.total_minutes=wake_times.max();for a in f.actors:a.behavior._on_minute(f.clock.total_minutes)
		check(f.uses.inside_count(f.hut.id)==0 and f.hut.animal_housing.count()==3,"Wake releases physical occupancy, retains permanent capacity")
		var choices: int=actor.behavior.choices;actor.behavior._on_minute(f.clock.total_minutes)
		check(actor.behavior.choices==choices,"Repeated minute cannot wake again")
		dispose(f)
func failure_and_demolition() -> void:
	var f=fixture(2)
	for actor in f.actors:actor.assign_home(f.hut,f.uses,f.areas)
	var actor=f.actors[0];f.clock.total_minutes=1261
	var before: Vector3=actor.position
	actor.behavior._choose(1261);actor.home.arrive(actor.behavior.token)
	check(actor.position==before and not actor.home.is_inside(),"Premature arrival never portals across map")
	f.nav.add_blocker(&"entry_block",Rect2(-.75,2.25,1.5,1));var calls: int=f.nav.queries
	actor.behavior._choose(1261)
	for i in 100:actor._physics_process(.01)
	check(f.nav.queries==calls and not actor.home.is_inside(),"Blocked entrance waits without per-frame A*")
	f.nav.remove_blocker(&"entry_block");sleep_all(f)
	check(actor.home.is_inside(),"Normal backoff/retry recovers after obstacle removal")
	check(f.hut.animal_housing.reserve(&"pending",&"future"),"Pending future capacity reservation")
	check(f.hut.set_work_direction(B.WorkDirection.DEMOLISH),"Existing D1 transition closes hut")
	check(f.hut.animal_housing.count()==0 and f.hut.animal_housing.reserved_count()==0 and f.uses.inside_count(f.hut.id)==0,"Demolition cleans slots, membership and capture holds synchronously")
	check(f.actors.all(func(a):return a.home==null and a.data.status==A.Status.WILD and a.data.home_id.is_empty() and a.data.habitat_center==a.position and a.data.habitat_radius==10),"Freed animals remain wild at physical portal exit")
	f.hut.work_paused=false;f.hut.add_construction_work(20);f.hut.set_work_direction(B.WorkDirection.BUILD);f.hut.work_paused=false;f.hut.add_construction_work(20);f.hut.complete_construction()
	check(f.hut.is_built() and f.hut.animal_housing.count()==0,"Restoration never re-domesticates released animals")
	dispose(f)
	f=fixture(1);actor=f.actors[0];actor.assign_home(f.hut,f.uses,f.areas)
	f.uses.slots_changed.connect(func(_id,purpose):
		if purpose==S.ANIMAL_SLEEP and f.hut.is_built():f.hut.set_work_direction(B.WorkDirection.DEMOLISH))
	sleep_all(f)
	check(actor.home==null and f.uses.inside_count(f.hut.id)==0,"Reentrant demolition during slot acquisition leaves no ghost occupancy")
	dispose(f)
	f=fixture(1);actor=f.actors[0];actor.assign_home(f.hut,f.uses,f.areas)
	f.clock.total_minutes=2040 # A night return delayed until 10:00 next day.
	actor.home.request_sleep(f.clock.total_minutes)
	for frame in 2000:
		if actor.home.is_inside():break
		step(f)
	check(actor.home.is_inside() and actor.data.wake_at>=3180 and actor.data.wake_at<=3300,"Late return sleeps until a future morning, never retroactively grazes past hours")
	dispose(f)
func canonical() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world)
	world.game_time.set_process(false);world.game_logger.console_enabled=false
	check(world.animals.size()==3 and world.animals.all(func(a):return a.status==A.Status.WILD),"Ordinary canonical startup keeps all three wild")
	var result: Dictionary=world.debug_spawn.spawn_building(Vector3(-10,0,16),D.for_type(T.SHEPHERD_HUT))
	check(result.ok,"Existing placement validation accepts new hut")
	var hut=result.objects[0]
	check(hut.animal_housing.count()==0,"Actual new building starts empty")
	var runtime=world.resident_runtimes[0]
	check(world.player_control.assign_workplace(runtime.data.id,hut.id,P.SHEPHERD),"Canonical shepherd assignment")
	check(not world._work_available(runtime) and not world._request_work(runtime) and hut.production_batches.is_empty() and world.player_control.get_porters(hut.id).is_empty(),"No fake work, production or required porter in canonical world")
	var actor=world.animal_executors[0]
	check(actor.assign_home(hut,world.building_uses,world.work_areas),"Real world animal uses same domestic contract")
	world.resident_selection.select_building(hut);world.game_ui.info_panel.set_expanded(true)
	await process_frame;await process_frame
	var card=world.building_card_view();card._refresh()
	check(card.animal_summary.visible and "1 / 8" in card.animal_summary.text and "0 / 20" in card.animal_summary.text,"Existing selected-building card shows animals and planned wool capacity")
	var marker=world.building_uses.acquire_animal(hut.id,actor.data.id,actor.position)
	check(marker!=null and world.change_construction_direction(hut.id,true),"Canonical demolition starts with an owned inside marker")
	check(hut.work_paused and world._building_cleanup_pending(hut),"D1 barrier prevents work until every inside marker is released")
	world.building_uses.release_animal(hut.id,marker,actor.data.id);world._poll_building_work()
	check(not hut.work_paused and actor.home==null and actor.data.status==A.Status.WILD,"Actual D1 cleanup resumes after final physical ownership release")
	check(world.change_construction_direction(hut.id,false),"Actual reverse demolition command accepted")
	world._poll_building_work();hut.complete_construction()
	check(hut.is_built() and hut.animal_housing.count()==0 and actor.data.status==A.Status.WILD,"Canonical restoration reactivates empty hut, not former animals")
	world.free();await process_frame
func run() -> void:
	definition_and_capacity();sleep_and_area();failure_and_demolition();await canonical()
	print("Domestic animals: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
