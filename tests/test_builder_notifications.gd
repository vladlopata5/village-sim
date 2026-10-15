extends SceneTree
## Real domain sites/slots; counters observe only read-only availability work.
const Setup = preload("res://tests/behavior_test_setup.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const PLANK = preload("res://scripts/resource_type.gd").Type.PLANK
class CountingBuilder extends "res://scripts/resident_builder_controller.gd":
	var scans := 0
	func best_site() -> Instance:
		scans += 1
		return super.best_site()
class Requests extends Node:
	var count := 0
	func request_decision(_reason: String) -> void: count += 1
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func replace_builder(world: Node, actor: Node, requests: Node) -> CountingBuilder:
	var position: Callable = actor.builder.position_provider
	actor.builder.free()
	actor.builder = CountingBuilder.new()
	actor.add_child(actor.builder)
	actor.builder.position_provider = position
	actor.builder.setup(actor.data, world.game_time, world.world_locations, world.buildings, actor.intents, requests)
	actor.builder.bind_sources(world.logistics.sources)
	return actor.builder
func place(world: Node, point: Vector2):
	var definition = Definition.for_type(Types.HOME)
	definition.construction_requirements = {PLANK: 10}
	world.placement.select(definition)
	world.placement.update_position(point)
	return world.placement.confirm()
func run() -> void:
	var world = Setup.make_scene(self)
	world.game_time.total_minutes = 420
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.data.activity = Activity.IDLE
	var actor = world.resident_runtimes[1]
	world.player_control.assign_profession(actor.data.id, Profession.BUILDER)
	var requests = Requests.new()
	root.add_child(requests)
	var builder = replace_builder(world, actor, requests)
	var site = place(world, Vector2(-500,200))
	site.add_delivered_material(PLANK,10)
	check(builder.scans == 0, "Registration/material callbacks invalidate without synchronous site selection")
	await process_frame
	check(builder.scans == 1 and requests.count == 1, "One settled burst produces one scan and one existing availability request")
	builder.scans = 0
	for index in range(20): site.add_construction_work(1)
	check(builder.scans == 0, "Progress burst never scans inside construction mutation")
	await process_frame
	check(builder.scans == 1 and requests.count == 1, "Repeated available state is coalesced without repeated decision requests")
	check(site.claim_builder_slot("other_a") and site.claim_builder_slot("other_b"), "Two different builders own the two real slots")
	check(not builder.has_work() and not builder.request_work(), "Fresh direct request sees claimed slots before deferred refresh")
	await process_frame
	builder.scans = 0
	site.release_builder_slot("other_a")
	site.release_builder_slot("other_b")
	await process_frame
	check(builder.scans == 1 and requests.count == 2, "Slot release invalidates negative availability and wakes once")
	check(builder.request_work(), "Actual request revalidates and claims a free slot")
	builder.scans = 0
	for index in range(20): site.add_construction_work(1)
	await process_frame
	check(builder.scans == 0 and actor.data.id in site.active_builder_ids, "Active assignment is retained without idle availability scans")
	world.cancel_construction(site.id)
	check(builder.site == null and builder.phase == builder.Phase.NONE and site.active_builder_ids.is_empty(), "Cancellation cleans active assignment synchronously")
	check(world.warehouse_data.resources.get_reserved_out(PLANK) == 0, "Material-ready assignment creates no source reservations")
	await process_frame
	check(not builder.has_work(), "Cancelled site is absent from fresh availability")
	var next_site = place(world, Vector2(-400,200))
	next_site.add_delivered_material(PLANK,10)
	await process_frame
	check(builder.has_work() and requests.count >= 3, "New site restores availability after cancellation")
	# A command may arrive between invalidation and the deferred service.
	builder.scans = 0
	next_site.add_construction_work(1)
	actor.commands.move_to(Vector2.ZERO)
	await process_frame
	check(builder.scans == 0 and actor.intents.current_intent.reason_id == &"player_move", "Deferred availability rechecks current intent and preserves player command")
	world.free()
	requests.free()
	print("Builder notifications: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
