extends SceneTree
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const Job = preload("res://scripts/haul_job.gd")
const Reference = preload("res://tests/porter_exhaustive_reference.gd")
class Counted extends "res://scripts/logistics_controller.gd":
	var probes := 0
	var claims := 0
	func has_available_job(id: String) -> bool:
		probes += 1
		return super.has_available_job(id)
	func claim_best_job(id: String) -> HaulJob:
		claims += 1
		return super.claim_best_job(id)
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func quiet(actor: Node) -> void:
	actor.decision._deciding = true
	actor.intents.abort_current(actor.intents.current_intent)
	actor.view.set_physics_process(false)
	for need in actor.data.needs.values():
		need.value = 0
		need.base_weight = 0
func fixture(count: int = 1) -> Dictionary:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	world.logistics = Counted.new()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	world.decision_dispatcher.set_process(false)
	for actor in world.resident_runtimes: quiet(actor)
	world.game_time.total_minutes = 419
	var actors: Array = []
	var spawned: Dictionary = world.debug_spawn.spawn_residents(Vector3(12,0,19),count,P.PORTER)
	check(spawned.created == count, "Real DebugPanel/PlayerControl Porter assignment")
	for data in spawned.objects:
		var actor = world.get_resident_runtime(data)
		quiet(actor)
		actors.append(actor)
	check(world.debug_spawn.spawn_resources(Vector3(10,0,22),60,R.LOG).created == 60, "Real Ground batch")
	world.decision_dispatcher.clear()
	return {"world":world, "actors":actors, "actor":actors[0], "queue":world.decision_dispatcher}
func begin(f: Dictionary, speed: int = 1) -> void:
	f.world.game_time.set_speed(speed)
	for actor in f.actors: actor.decision._deciding = false
	f.world.game_time.advance(1.0/speed)
func tick(f: Dictionary) -> void:
	await process_frame
	f.queue._process(0)
func walk(actor: Node) -> void:
	for step in 4000:
		actor.view._physics_process(0.05)
		if not actor.view.movement.is_moving(): break
func reference(f: Dictionary, actor: Node):
	var old = Reference.new()
	old.setup(f.world.warehouse_data,null,actor.data)
	for building in f.world.buildings: old.register_building(building)
	old.position_provider = f.world.logistics.position_provider
	old.sources.ground = f.world.ground_resources
	old.sources.route_available = f.world.logistics.sources.route_available
	old.bind_world(f.world.game_time,f.world.world_locations)
	return old._best(old.collect_candidates(actor.data.id))
func run() -> void:
	# Real WORK wave, queue enters before probes, unchanged per-decision exact winner.
	for speed in [1,4,20]:
		var f = fixture(30)
		begin(f,speed)
		check(f.queue.pending_count() == 30 and f.world.logistics.probes == 0 and f.world.logistics.claims == 0, "WORK queues before expensive has_work/claim at x%d" % speed)
		for repeat in 100: f.world._refresh_porter_availability()
		check(f.queue.pending_count() == 30 and f.queue.duplicates >= 3000 and f.world.logistics.probes == 0, "Availability coalesces without prequeue probes")
		var chosen: Dictionary = {}
		for index in 30:
			var actor = f.actors[index]
			var expected = reference(f,actor)
			await tick(f)
			var job = f.world.logistics.get_job(actor.data.id)
			check(job != null, "FIFO worker obtains actual haul")
			if job != null:
				check(job.source_ref.stable_key() == expected.source_ref.stable_key() and job.destination_location_id == expected.destination.id and job.priority == expected.porter_score, "Fresh exact exhaustive winner")
				check(not chosen.has(job.source_ref.stable_key()) or f.world.logistics.sources.resolve(job.source_ref).amount > 1, "No duplicate exclusive Ground claims")
				chosen[job.source_ref.stable_key()] = true
			check(f.queue.executed == index + 1, "One decision per real frame independent of time scale")
			f.queue._process(0)
			check(f.queue.executed == index + 1, "No second budget in same frame")
		f.world.free()
	# Pending state is revalidated; player/critical actions remain immediate.
	for change in ["command","fatigue","hunger","rest","source","destination","profession","workplace","runtime","pause"]:
		var f = fixture()
		begin(f)
		var before: int = f.world.logistics.claims
		match change:
			"command":
				check(f.world.player_control.move_to(f.actor.data.id,C.to_sim(Vector3(15,0,22))), "MOVE_TO immediate while queued")
				check(f.actor.intents.player_controlled and f.queue.pending_count() == 0, "Command invalidates pending work")
			"fatigue":
				f.actor.data.fatigue = 100
				check(f.actor.intents.forced_priority > 0 and f.queue.pending_count() == 0, "Critical sleep immediate, no queue delay")
			"hunger":
				var kitchen: Dictionary = f.world.debug_spawn.spawn_building(Vector3(30,0,10),preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.FOOD))
				check(kitchen.ok, "Real Kitchen for critical food test")
				kitchen.objects[0].resources.add(R.FOOD,10)
				f.actor.data.hunger = 100
				check(f.actor.intents.forced_priority > 0 and f.queue.pending_count() == 0, "Critical EAT immediate, no queue delay")
			"rest": f.world.game_time.advance(600.0)
			"source":
				for ground in f.world.ground_resources.drops.duplicate(): f.world.ground_resources.remove_drop(ground)
			"destination": f.world.logistics.remove_building(f.world.warehouse_data.id)
			"profession": f.world.player_control.assign_profession(f.actor.data.id,P.NONE)
			"workplace": f.world.player_control.clear_work_assignment(f.actor.data.id)
			"runtime": f.actor.free()
			"pause":
				paused = true
				await tick(f)
				check(f.world.logistics.claims == before and f.queue.pending_count() == 1,"Pause retains queue without claims")
				paused = false
		await tick(f)
		if change == "source":
			check(f.world.logistics.jobs.all(func(job): return job.source_ref.kind != 1), "Expired Ground is not chosen from a cached candidate")
		elif change == "pause": check(f.world.logistics.claims == before + 1,"Resume starts fresh decision")
		else: check(f.world.logistics.claims == before, "Stale request cannot create haul: " + change)
		check(f.world.logistics._inbound.size() == f.world.logistics.jobs.size(), "No orphan inbound after " + change)
		f.world.free()
	# Completion requests the next ordinary decision; transport and cleanup stay synchronous.
	var completion_fixture = fixture()
	begin(completion_fixture)
	await tick(completion_fixture)
	var completed_job = completion_fixture.world.logistics.get_job(completion_fixture.actor.data.id)
	await physics_frame
	walk(completion_fixture.actor)
	completion_fixture.world.game_time.advance(10.0)
	check(completion_fixture.actor.data.inventory.amount == 1, "Normal pickup/loading")
	walk(completion_fixture.actor)
	completion_fixture.world.game_time.advance(10.0)
	check(completed_job.state == Job.State.COMPLETED and completion_fixture.actor.data.inventory.amount == 0, "Physical delivery/handling unchanged")
	check(completion_fixture.queue.pending_count() == 1 and completion_fixture.world.logistics.get_job(completion_fixture.actor.data.id) == null, "Completion queues next decision without recursive claim")
	await tick(completion_fixture)
	check(completion_fixture.world.logistics.get_job(completion_fixture.actor.data.id) != null,"Later fresh work starts normally")
	var live_job = completion_fixture.world.logistics.get_job(completion_fixture.actor.data.id)
	completion_fixture.world.logistics.sources.ground.remove_drop(completion_fixture.world.logistics.sources.resolve(live_job.source_ref))
	completion_fixture.world.logistics.recalculate()
	check(live_job.state == Job.State.CANCELLED and completion_fixture.world.logistics._inbound.is_empty(), "Safety cancellation synchronous, not frame queued")
	completion_fixture.world.free()
	# Only Porter: a real Gatherer still decides synchronously.
	completion_fixture = fixture()
	completion_fixture.actor.decision._deciding = true
	var gatherer = completion_fixture.world.resident_runtimes[1]
	check(completion_fixture.world.debug_spawn.spawn_building(Vector3(30,0,10),preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.GATHERER_HUT)).ok,"Real Gatherer Hut")
	check(completion_fixture.world.player_control.assign_profession(gatherer.data.id,P.GATHERER),"Normal Gatherer assignment")
	gatherer.decision._deciding = false
	completion_fixture.world.game_time.advance(1.0)
	check(gatherer.decision.decision_count > 0 and completion_fixture.queue.pending_count() == 0, "Other professions preserve synchronous decisions")
	completion_fixture.world.free()
	print("Porter dispatcher: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
