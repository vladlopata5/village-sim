extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Locations = preload("res://scripts/world_3d/natural_source_locations_3d.gd")
class CountedLocations extends Locations:
	var queries := 0
	func resolve(source: RefCounted, origin: Vector2) -> Variant:
		queries += 1
		return super.resolve(source,origin)
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func walk(actor: Node) -> void:
	for step in range(4000):
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.view.set_physics_process(false)
		actor.intents.abort_current(actor.intents.current_intent)
		for need in actor.data.needs.values(): need.value=0
	await physics_frame
	var place := Building.new(&"quarry_test",Definition.for_type(BT.QUARRY),C.to_sim(Vector3(29,0,1)))
	world.buildings.append(place)
	world._show_building(place)
	var actor = world.resident_runtimes[3]
	var worker = actor.get_node("Miner")
	var counted := CountedLocations.new()
	counted.navigation=world.navigation
	worker.locations=counted
	world.player_control.assign_workplace(actor.data.id,place.id)
	place.resources.add(R.STONE,11)
	check(worker.has_work() and worker._available.kind==&"MINE","11/12 permits MINE")
	check(worker.request_work() and counted.queries==1,"has/request reuse region target once")
	check(place.resources.get_reserved_in(R.STONE)==0,"No MINE inbound promise")
	walk(actor)
	place.resources.add(R.STONE,1)
	world.game_time.debug_skip_minutes(60)
	check(world.ground_resources.drops.size()==1 and place.resources.get_amount(R.STONE)==12,"Buffer filled mid-MINE still creates Ground output")
	check(worker.best_task().kind==&"EXPORT","Full buffer exports even while unclaimed Ground exists")
	place.resources.try_take(R.STONE,1)
	check(worker.best_task().kind==&"COLLECT","11/12 Ground has priority")
	var drop = world.ground_resources.drops[0]
	var holder: StringName = &"competitor"
	check(drop.reserve(holder),"Public Ground claim available to competitor")
	check(worker.has_work() and worker._available.kind==&"MINE","Claimed Ground ignored")
	drop.release(holder)
	check(worker.request_work() and world.logistics.get_job(actor.data.id)!=null,"Same-frame claim release invalidates MINE cache and chooses COLLECT")
	var job = world.logistics.get_job(actor.data.id)
	world.logistics._executors[actor.data.id].cancel("policy test")
	check(place.resources.get_reserved_in(R.STONE)==0 and drop.reservation_owner_id.is_empty(),"Internal cancellation cleans normal ledgers")
	var source_ref := Source.new(Source.Kind.GROUND,drop.id)
	job = world.logistics.claim_internal(actor.data.id,source_ref,place,R.STONE,func(): return true)
	check(job!=null and place.resources.get_available_free_capacity(R.STONE)==0,"Last room reserved only at actual collection")
	var second = world.resident_runtimes[2]
	world.logistics.register_resident(second.data)
	second.data.profession=P.MINER
	second.data.work_location_id=place.id # Explicit invalid double assignment fixture; ledger still protects room.
	check(world.logistics.claim_internal(second.data.id,source_ref,place,R.STONE,func(): return true)==null,"Competing claim cannot overbook last room")
	second.data.work_location_id=&""
	world.logistics.start_claimed_job(job,actor.data.id)
	world.game_time.total_minutes=drop.created_at+drop.lifetime
	world.ground_resources._on_minute(world.game_time.total_minutes)
	world.logistics.recalculate()
	check(job.state==5 and place.resources.get_reserved_in(R.STONE)==0,"Ground expiry before pickup cancels and releases inbound")
	world.game_time.total_minutes=420
	place.resources.try_take(R.STONE,11)
	check(worker.request_work(),"Empty Quarry resumes mining")
	walk(actor)
	var partial = worker.rock
	world.game_time.debug_skip_minutes(17)
	var area = world.work_areas.create(C.to_sim(Vector3(-50,0,30)),C.length_to_sim(1))
	world.player_control.assign_work_area(actor.data.id,area.id)
	world.game_time.debug_skip_minutes(43)
	check(partial.stock==8 and worker.rock==null,"Captured BUILDING extraction finishes after FREE reassignment")
	check(not worker.has_work(),"Next FREE decision uses new empty area")
	world.player_control.assign_workplace(actor.data.id,place.id)
	check(worker.request_work(),"COLLECT before destination removal")
	job = world.logistics.get_job(actor.data.id)
	world.logistics.remove_building(place.id)
	check(job.state==5 and place.resources.get_reserved_in(R.STONE)==0 and actor.data.inventory.amount==0,"Captured destination removal cancels safely")
	world.player_control._buildings.erase(place)
	check(not worker.has_work() and actor.data.work_location_id==place.id and actor.data.work_area_id.is_empty(),"Lost Quarry never auto-switches FREE")
	world.free()
	print("Quarry policy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
