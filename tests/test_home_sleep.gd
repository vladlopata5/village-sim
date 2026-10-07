extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
const Intent = preload("res://scripts/resident_intent.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func night(scene: Node) -> void:
	scene.game_time.total_minutes = 1379
	scene.game_time.advance(1.0)
func house(scene: Node, id: StringName):
	return scene.player_control.get_building(id)
func _run() -> void:
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[0]
	var a = house(scene, actor.data.home_location_id)
	var b = house(scene, scene.residents[1].home_location_id)
	var b_point: Vector2 = scene.world_locations.get_position(b.id)
	check(scene.player_control.assign_home(actor.data.id, b.id), "Day reassign succeeds")
	var before: Vector2 = actor.view.global_position
	check(actor.data.activity != Activity.SLEEPING and actor.view.global_position == before, "Day home assignment does not sleep or teleport")
	night(scene)
	var trip = actor.intents.current_intent
	check(trip.reason_id == &"night_home" and trip.target_position == b_point, "Night resolves current BUILT house, not bootstrap house")
	check(actor.data.activity == Activity.MOVING and actor.view.has_movement_target, "Home sleep requires physical trip")
	actor.view._process(0.1)
	check(actor.view.global_position != before and actor.data.activity == Activity.MOVING, "Trip physically advances before sleep")
	check(scene.player_control.assign_home(actor.data.id, a.id), "Mid-trip reassign succeeds")
	actor.schedule.resume_current_phase()
	check(actor.intents.current_intent == trip and trip.target_position == b_point, "Reassign and schedule resume preserve committed trip")
	actor.view._process(20)
	check(actor.data.activity == Activity.SLEEPING and actor.view.global_position == b_point, "Arrival starts ordinary sleep at chosen house")
	check(scene.player_control.clear_home(actor.data.id) and actor.data.activity == Activity.SLEEPING, "Clear home does not wake active sleep")
	scene.game_time.debug_next_phase()
	check(actor.data.activity != Activity.SLEEPING, "Morning ends ordinary sleep")
	scene.player_control.assign_home(actor.data.id, a.id)
	night(scene)
	check(actor.intents.current_intent.target_position == scene.world_locations.get_position(a.id), "Next sleep uses reassigned house")
	scene.free()

	# Empty, missing, unfinished, non-house and zero-capacity targets all fall back locally.
	for kind in ["empty", "missing", "unfinished", "nonhouse", "zero_capacity"]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[0]
		match kind:
			"empty": actor.data.home_location_id = &""
			"missing": actor.data.home_location_id = &"missing_house"
			"nonhouse": actor.data.home_location_id = scene.warehouse_data.id
			"unfinished", "zero_capacity":
				var definition = Definition.for_type(Types.HOME)
				if kind == "zero_capacity": definition.housing_capacity = 0
				var target = Building.new(&"invalid_sleep_house", definition, Vector2(700, 700), Building.State.UNDER_CONSTRUCTION if kind == "unfinished" else Building.State.BUILT)
				scene.buildings.append(target)
				actor.data.home_location_id = target.id
		before = actor.view.global_position
		night(scene)
		check(actor.data.activity == Activity.SLEEPING and actor.intents.current_intent.reason_id == &"night_outdoor", "%s home starts outdoor sleep" % kind)
		check(not actor.view.has_movement_target and actor.view.global_position == before, "%s fallback sleeps at current point" % kind)
		actor.data.fatigue = 80
		for minute in range(20): actor.need_dynamics._on_minute_changed(minute)
		check(actor.data.fatigue == 74, "%s outdoor sleep uses 0.6 quality" % kind)
		actor.schedule.resume_current_phase()
		check(actor.data.activity == Activity.SLEEPING, "Outdoor action remains committed")
		scene.game_time.debug_next_phase()
		check(actor.intents.current_intent.reason_id != &"night_outdoor" and actor.data.activity != Activity.SLEEPING, "Morning clears stationary outdoor intent")
		scene.free()

	# Valid simulation housing does not require a visual marker to supply a target.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	var unmapped_house = Building.new(&"unmapped_house", Definition.for_type(Types.HOME), Vector2(700, 700))
	scene.buildings.append(unmapped_house)
	scene.player_control.assign_home(actor.data.id, unmapped_house.id)
	night(scene)
	check(actor.intents.current_intent.reason_id == &"night_home" and actor.view.target_position == unmapped_house.position, "House instance position works without visual location mapping")
	actor.view._process(20)
	check(actor.data.activity == Activity.SLEEPING and actor.view.global_position == unmapped_house.position, "Unmapped valid house still requires physical arrival")
	scene.free()

	# Capacity is assignment validation, not a bed/ongoing sleep reservation.
	scene = Setup.make_scene(self)
	a = house(scene, scene.residents[0].home_location_id)
	for resident in scene.residents:
		if resident.home_location_id != a.id: check(scene.player_control.assign_home(resident.id, a.id), "Residents share house")
	night(scene)
	for runtime in scene.resident_runtimes:
		check(runtime.intents.current_intent.target_position == scene.world_locations.get_position(a.id), "Shared full house remains valid sleep target")
		runtime.view._process(20)
		check(runtime.data.activity == Activity.SLEEPING, "All occupants sleep together without bed slots")
	actor = scene.resident_runtimes[0]
	actor.data.fatigue = 80
	for minute in range(20): actor.need_dynamics._on_minute_changed(minute)
	check(actor.data.fatigue == 70, "House recovery matches outdoor recovery")
	scene.free()

	# A pending night goal resolves housing on activation, not when it was queued.
	for initially_homeless in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[0]
		b = house(scene, scene.residents[1].home_location_id)
		if initially_homeless: scene.player_control.clear_home(actor.data.id)
		var personal = Intent.new(Intent.Type.MOVE_TO, &"committed_personal", Vector2(100, 100), 100, false)
		actor.intents.submit(personal)
		night(scene)
		check(actor.intents.current_intent == personal, "Night sleep waits behind committed action")
		scene.player_control.assign_home(actor.data.id, b.id)
		actor.intents.clear_completed(personal)
		check(actor.intents.current_intent.reason_id == &"night_home" and actor.intents.current_intent.target_position == scene.world_locations.get_position(b.id), "Pending sleep uses home current at activation")
		check(actor.data.activity == Activity.MOVING and actor.view.has_movement_target, "Pending outdoor-to-home change starts actual travel")
		scene.free()

	# Real meal completion also promotes a pending night goal with the latest home.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	b = house(scene, scene.residents[1].home_location_id)
	scene.kitchen_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 1)
	actor.data.hunger = 60
	check(actor.needs.try_eat(5000), "Ordinary meal starts before night")
	actor.view._process(20)
	check(actor.data.activity == Activity.EATING, "Real existing eating flow is committed")
	night(scene)
	check(actor.data.activity == Activity.EATING and actor.intents.pending_intent.reason_id == &"night_home", "Night queues behind real meal")
	scene.player_control.assign_home(actor.data.id, b.id)
	scene.game_time.advance(30)
	check(actor.data.activity == Activity.MOVING and actor.view.target_position == scene.world_locations.get_position(b.id), "Meal completion resolves newly assigned home")
	scene.free()

	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	var locked = Intent.new(Intent.Type.MOVE_TO, &"committed_personal", Vector2(100, 100), 100, false)
	actor.intents.submit(locked)
	night(scene)
	scene.player_control.clear_home(actor.data.id)
	actor.intents.clear_completed(locked)
	check(actor.data.activity == Activity.SLEEPING and not actor.view.has_movement_target and actor.intents.current_intent.reason_id == &"night_outdoor", "Clear home before pending activation selects outdoor sleep")
	scene.free()

	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	var lines: Array[String] = []
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	night(scene)
	var starts := lines.filter(func(line): return line.contains("идёт спать домой"))
	check(starts.size() == scene.residents.size(), "Home start is logged once per resident")
	for repeat in range(5): actor.schedule.resume_current_phase()
	check(lines.filter(func(line): return line.contains("идёт спать домой")).size() == starts.size(), "Schedule resume does not spam or restart home trips")
	scene.free()

	# Critical fatigue ignores both valid housing and homelessness.
	for homeless in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[0]
		if homeless: scene.player_control.clear_home(actor.data.id)
		before = actor.view.global_position
		actor.data.fatigue = 100
		check(actor.intents.current_intent.reason_id == &"critical_sleep" and actor.data.activity == Activity.SLEEPING, "Critical fatigue still forces on-spot sleep")
		check(actor.intents.forced_priority == 100 and not actor.view.has_movement_target and actor.view.global_position == before, "Critical priority and position unchanged")
		for minute in range(20): actor.need_dynamics._on_minute_changed(minute)
		check(actor.data.fatigue == 94, "Critical recovery uses outdoor quality regardless of housing")
		check(scene.player_control.move_to(actor.data.id, before + Vector2(50, 50)), "PlayerCommand interrupts critical sleep")
		check(actor.commands.active_command != null and actor.data.activity == Activity.MOVING, "Player command retains absolute priority")
		scene.free()

	for mode in ["home_trip", "home_sleep", "outdoor_sleep"]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[0]
		b = house(scene, scene.residents[1].home_location_id)
		if mode == "outdoor_sleep": scene.player_control.clear_home(actor.data.id)
		night(scene)
		if mode == "home_sleep": actor.view._process(20)
		check(scene.player_control.move_to(actor.data.id, Vector2(500, 300)), "PlayerCommand interrupts %s" % mode)
		check(actor.commands.active_command != null and actor.intents.current_intent.reason_id == &"player_move", "Sleep route is replaced by command")
		scene.player_control.assign_home(actor.data.id, b.id)
		actor.view._process(20)
		check(actor.commands.active_command == null and actor.intents.current_intent.reason_id == &"night_home" and actor.intents.current_intent.target_position == scene.world_locations.get_position(b.id), "After command AI chooses fresh current home")
		scene.free()

	# An execution whose destination disappears still arrives safely and sleeps locally.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	a = house(scene, actor.data.home_location_id)
	night(scene)
	scene.buildings.erase(a)
	actor.view._process(20)
	check(actor.data.activity == Activity.SLEEPING and not actor.view.has_movement_target, "Removed home does not strand committed sleep execution")
	scene.free()
	print("Home sleep: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
