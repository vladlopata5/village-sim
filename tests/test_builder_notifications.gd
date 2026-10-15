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
	var notifications := 0
	func best_site() -> Instance:
		scans += 1
		return super.best_site()
	func _on_world_changed() -> void:
		notifications += 1
		super._on_world_changed()
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
	check(not builder.has_work() and builder.scans == 1, "Initial negative is computed once")
	var site = place(world, Vector2(-500,200))
	site.add_delivered_material(PLANK,10)
	await process_frame
	check(builder.scans == 1 and requests.count == 0 and builder.notifications == 0, "New site/materials never wake or notify a free Builder")
	check(builder.has_work() and builder.scans == 2, "Next ordinary availability probe discovers the new site")
	check(site.claim_builder_slot("other_a") and site.claim_builder_slot("other_b"), "Two builders claim exactly two real slots")
	check(not builder.has_work() and not builder.request_work(), "Full slots invalidate positive before deferred events")
	var scans: int = builder.scans
	for hour in range(72):
		world.game_time.debug_skip_minutes(60)
		check(not builder.has_work(), "Full site stays unavailable across three game days")
	check(builder.scans == scans and requests.count == 0, "Unchanged negative across phases/days does not repeat best_site")
	site.release_builder_slot("other_a")
	site.release_builder_slot("other_b")
	await process_frame
	check(builder.scans == scans and builder.notifications == 0, "Slot release does not notify free workers")
	check(builder.has_work() and builder.scans == scans+1, "Release invalidates negative at next ordinary probe")
	check(builder.request_work(), "Actual request atomically claims a live slot")
	check(site.construction_changed.is_connected(builder._on_world_changed), "Committed assignment observes its site")
	check(not builder.request_work() and site.active_builder_ids.size() == 1, "Repeated request neither duplicates claim nor assignment")
	var other = place(world, Vector2(-400,200))
	var notifications: int = builder.notifications
	for index in range(20): other.add_construction_work(1)
	other.add_delivered_material(PLANK,10)
	await process_frame
	check(builder.notifications == notifications, "Active builder never reacts to an unrelated site")
	scans = builder.scans
	for index in range(20): site.add_construction_work(1)
	await process_frame
	check(builder.scans == scans and actor.data.id in site.active_builder_ids, "Own progress preserves assignment without searching new work")
	world.cancel_construction(site.id)
	check(builder.site == null and builder.phase == builder.Phase.NONE and site.active_builder_ids.is_empty(), "Cancellation cleans active assignment synchronously")
	check(not site.construction_changed.is_connected(builder._on_world_changed) and not builder.sources.changed.is_connected(builder._on_sources_changed), "Cleanup removes both committed subscriptions")
	check(builder.has_work() and builder.request_work(), "Freed builder can choose the other live site normally")
	check(other.construction_changed.is_connected(builder._on_world_changed), "New assignment observes only the new site")
	notifications = builder.notifications
	site.add_construction_work(1)
	check(builder.notifications == notifications, "Previous site cannot notify a reassigned builder")
	actor.commands.move_to(Vector2.ZERO)
	check(builder.site == null and not other.construction_changed.is_connected(builder._on_world_changed), "Player interruption detaches current site immediately")
	check(world.warehouse_data.resources.get_reserved_out(PLANK) == 0, "Material-ready assignments create no source reserves")
	world.cancel_construction(other.id)
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.activity = Activity.IDLE
	var empty = place(world, Vector2(-500,200))
	check(empty != null, "Empty-material fixture occupies a valid released site")
	world.warehouse_data.resources.try_take(PLANK,35)
	check(not builder.has_work(), "Missing material caches unavailable")
	scans = builder.scans
	world.warehouse_data.resources.add(PLANK,1)
	await process_frame
	check(builder.scans == scans, "Container arrival does not trigger a Builder search")
	check(builder.has_work(), "Container availability signature invalidates cached false")
	world.warehouse_data.resources.reserve_out(PLANK,1)
	check(not builder.has_work(), "Last available container unit becoming reserved invalidates positive")
	world.warehouse_data.resources.release_out(PLANK,1)
	check(builder.has_work(), "Released source is found without a mass notification")
	world.warehouse_data.resources.try_take(PLANK,1)
	check(not builder.has_work(), "Exhausted source caches false again")
	scans = builder.scans
	actor.data.work_area_id = &"changed_assignment"
	check(not builder.has_work() and builder.scans == scans+1, "Assignment revision invalidates at probe without changing Builder area rules")
	scans = builder.scans
	builder.on_navigation_changed(1)
	check(builder.scans == scans and not builder.has_work() and builder.scans == scans+1, "Navigation invalidates lazily without starting work")
	world.cancel_construction(empty.id)
	check(not builder.has_work(), "Deleted site cannot survive in the availability cache")
	world.free()
	requests.free()
	print("Builder notifications: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
