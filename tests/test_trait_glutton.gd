extends SceneTree
const Setup = preload("res://tests/need_test_setup.gd")
const Store = preload("res://scripts/moodlet_store.gd")
const Trait = preload("res://scripts/trait_type.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
class MealRng extends RefCounted:
	var values: Array = []
	var draws := 0
	func randf() -> float:
		var index := draws
		draws += 1
		return values[index] if index < values.size() else 0.0
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fixture(glutton: bool = true) -> Node:
	var world: Node = Setup.make_scene(self, 420, 6)
	world.social_events.enabled = false; world.game_logger.console_enabled = false
	# These lifecycle checks select the successful 80% branch explicitly.
	world.game_events.executor.rng = MealRng.new()
	var actor: Node = world.resident_runtimes[0]
	actor.decision._deciding = true
	actor.intents.abort_current(actor.intents.current_intent)
	if glutton: actor.data.add_trait(Trait.GLUTTON)
	return world
func begin(world: Node, hunger: int) -> RefCounted:
	var actor: Node = world.resident_runtimes[0]
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.hunger = hunger
	actor.need_dynamics._fractions[0] = 0 # Controlled exact starting value for these boundary cases.
	check(actor.needs.try_eat(8000), "Real meal is available")
	var intent: RefCounted = actor.intents.current_intent
	actor.view._process(100)
	check(actor.needs._meal_active and actor.needs._food_received and actor.needs._minutes_left == 30, "Paid kitchen meal starts with unchanged duration")
	return intent
func record(source: String, minute: int) -> Dictionary:
	return {"id": "well_fed", "type": "well_fed", "source_occurrence_id": source, "created_minute": minute, "expires_at_minute": minute + 120, "modifiers": []}
func run() -> void:
	_store_cases()
	for glutton in [false, true]:
		for initial_hunger in [60, 80, 81]:
			var world := fixture(glutton); var actor: Node = world.resident_runtimes[0]
			var mood: int = actor.data.mood
			begin(world, initial_hunger)
			world.game_time.advance(29)
			check(actor.data.moodlets.size() == 0 and actor.needs._minutes_left == 1, "No moodlet before full meal completion")
			world.game_time.advance(1)
			check(actor.data.hunger == initial_hunger - 60, "Existing satiety gives exact final HUNGER 0/20/21")
			var entry: Dictionary = actor.data.moodlets.get_entry("well_fed")
			var expected: bool = glutton and initial_hunger <= 80
			check(not entry.is_empty() == expected, "Only GLUTTON with final hunger at most twenty gets the moodlet")
			if expected:
				check(entry.created_minute == world.game_time.total_minutes and entry.expires_at_minute == entry.created_minute + 120, "Deadline uses actual completion minute")
				check(entry.type == "well_fed" and entry.context.display_name == "Вкусно поел" and entry.tags == ["positive"] and entry.modifiers == [{"channel":"need_growth_rate","need":"hunger","multiplier":0.5}], "Positive named state has exactly the agreed hunger-growth modifier")
			check(actor.data.mood == mood, "Base mood is unchanged")
			world.free()
	_repeat_and_expire()
	var fractional_world := fixture(); var fractional_actor: Node = fractional_world.resident_runtimes[0]
	begin(fractional_world, 80); fractional_actor.need_dynamics._fractions[0] = 30
	fractional_world.game_time.advance(30)
	check(fractional_actor.data.hunger == 21 and fractional_actor.data.moodlets.size() == 0, "Eligibility uses actual final hunger, preserving existing fractional rounding")
	fractional_world.free()
	_interruptions()
	_reentrant_completion()
	_outdoor_meal()
	print("Glutton well fed: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _store_cases() -> void:
	var store := Store.new("owner")
	var notifications: Array = []
	var callback := func(id: String):
		var committed: Dictionary = store.get_entry(id)
		notifications.append(committed)
		check(store.size() == 1 and not store.add_or_refresh(committed), "Nested duplicate sees committed singleton and cannot refresh it")
	store.changed.connect(callback)
	check(store.add_or_refresh(record("meal/1", 500)), "Explicit singleton addition")
	var repeated := record("meal/1", 550)
	check(not store.add_or_refresh(repeated) and store.get_entry("well_fed").expires_at_minute == 620 and notifications.size() == 1, "Same source with later time is a no-op")
	check(store.add_or_refresh(record("meal/2", 560)) and store.size() == 1 and store.get_entry("well_fed").expires_at_minute == 680, "New meal replaces deadline, without adding to old deadline")
	check(not store.add(record("meal/3", 570)), "Ordinary add still rejects an existing ID")
	check(not store.add_or_refresh(record("stale", 540)) and notifications.size() == 2, "Stale refresh cannot overwrite a newer completion")
	var invalid := record("invalid", 570); invalid.expires_at_minute = 1
	check(not store.add_or_refresh(invalid) and store.get_entry("well_fed").source_occurrence_id == "meal/2", "Invalid refresh preserves the record")
	var wrong_type := record("different", 570); wrong_type.type = "pride"
	check(not store.add_or_refresh(wrong_type), "Refresh cannot replace a different type occupying this ID")
	check(store.is_active("well_fed", 679) and not store.is_active("well_fed", 680), "Existing half-open expiry applies")
	store.changed.disconnect(callback)
	check(store.expire(680) == 1 and store.size() == 0, "Explicit cleanup keeps existing semantics")
	var other := Store.new("other")
	check(other.size() == 0 and other.add_or_refresh(record("meal/2", 560)), "Residents have independent singleton records")
func _repeat_and_expire() -> void:
	var world := fixture(); var actor: Node = world.resident_runtimes[0]
	var first := begin(world, 80); world.game_time.advance(30)
	var original: Dictionary = actor.data.moodlets.get_entry("well_fed")
	world.game_time.advance(10)
	actor.needs.eat_outcome.emit(first, &"completed", world.kitchen_data.id)
	actor.needs._finish()
	check(actor.data.moodlets.get_entry("well_fed") == original, "Repeated outcome and repeated finish cannot extend the same meal")
	var second := begin(world, 80); world.game_time.advance(30)
	var refreshed: Dictionary = actor.data.moodlets.get_entry("well_fed")
	check(actor.data.moodlets.size() == 1 and refreshed.source_occurrence_id != original.source_occurrence_id and refreshed.expires_at_minute == world.game_time.total_minutes + 120, "Second actual meal refreshes one record with a new source token")
	paused = true; world.game_time.advance(1000); paused = false
	check(actor.data.moodlets.get_entry("well_fed") == refreshed and actor.data.moodlets.is_active("well_fed", world.game_time.total_minutes), "Pause does not advance the moodlet clock")
	world.game_time.advance(119)
	check(actor.data.moodlets.is_active("well_fed", world.game_time.total_minutes), "Active after 119 minutes")
	world.game_time.advance(1)
	check(not actor.data.moodlets.is_active("well_fed", world.game_time.total_minutes) and actor.data.moodlets.size() == 0, "Inactive and automatically removed at120 game minutes")
	check(actor.data.moodlets.expire(world.game_time.total_minutes) == 0, "Explicit cleanup after automatic expiry is idempotent")
	actor.needs.eat_outcome.emit(second, &"completed", world.kitchen_data.id); actor.needs._finish()
	check(actor.data.moodlets.size() == 0, "Duplicate completed notification cannot recreate an explicitly expired record")
	world.free()
func _interruptions() -> void:
	for during_eating in [false, true]:
		var world := fixture(); var actor: Node = world.resident_runtimes[0]
		actor.data.hunger = 60
		check(actor.needs.try_eat(8000), "Interruptible trip reserves real food")
		var intent: RefCounted = actor.intents.current_intent
		if during_eating:
			actor.view._process(100); world.game_time.advance(20)
			check(actor.data.hunger == 20 and actor.needs._minutes_left == 10, "Interrupted meal already reached satiety threshold")
		actor.intents.abort_current(intent)
		world.game_time.advance(30)
		check(actor.data.moodlets.size() == 0 and world.kitchen_data.resources.get_reserved_out(FOOD) == 0, "Interrupted trip/paid meal gives no moodlet and releases reservations")
		world.free()
func _reentrant_completion() -> void:
	var world := fixture(); var actor: Node = world.resident_runtimes[0]
	var intent := begin(world, 80)
	var observed: Array = []
	var callback := func(id: String):
		observed.append(id)
		check(actor.needs._active_intent == null and not actor.needs._meal_active and not actor.needs._food_received and actor.data.hunger == 20, "Store callback sees finished meal ownership and final hunger")
		actor.needs._finish()
		actor.needs.eat_outcome.emit(intent, &"completed", world.kitchen_data.id)
	actor.data.moodlets.changed.connect(callback)
	world.game_time.advance(30)
	check(observed == ["well_fed"] and actor.data.moodlets.size() == 1, "Nested callbacks produce only one moodlet notification")
	world.free()
func _outdoor_meal() -> void:
	var world: Node = preload("res://tests/residents_ui_fixture.gd").create(self)
	world.game_events.executor.rng = MealRng.new()
	var actor: Node = world.resident_runtimes[1]
	actor.data.set_traits([]); actor.data.add_trait(Trait.GLUTTON)
	for place in world.buildings: place.resources.try_take(FOOD, place.resources.get_available_amount(FOOD))
	actor.data.hunger = 80; actor.need_dynamics._fractions[0] = 0
	var drop: RefCounted = preload("res://tests/ground_stack_fixture.gd").create(world.ground_resources, FOOD, 4, actor.view.get_drop_sim_position() + Vector2(25, 0))
	check(actor.needs.try_eat(8000), "Canonical ground meal starts")
	var intent: RefCounted = actor.intents.current_intent
	for step in 12000:
		if actor.intents.current_intent != intent or actor.needs._meal_active: break
		actor.view._physics_process(0.05)
	check(actor.needs._meal_active and actor.needs._minutes_left == 10 and drop.amount == 3, "Ground meal consumes one unit and retains its ten-minute duration")
	check(world.ground_resources.remove_drop(drop), "Paid meal source may be removed")
	world.game_time.advance(9)
	check(actor.data.moodlets.size() == 0, "Outdoor meal is not rewarded early")
	world.game_time.advance(1)
	check(actor.data.hunger == 20 and actor.data.moodlets.is_active("well_fed", world.game_time.total_minutes), "Actual outdoor completion grants well_fed even after source removal")
	world.free()
