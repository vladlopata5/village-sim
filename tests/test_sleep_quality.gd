extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Data = preload("res://scripts/resident_data.gd")
const Clock = preload("res://scripts/game_time.gd")
const Activity = preload("res://scripts/resident_activity.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func night(scene: Node) -> void:
	scene.game_time.total_minutes = 1379
	scene.game_time.advance(1.0)
func recovery(minutes: int, quality: float) -> int:
	var base: float = -float(Dynamics.FATIGUE_RATES[Activity.SLEEPING]) / Dynamics.UNITS_PER_POINT
	return int(minutes * base * quality)
func _run() -> void:
	check(Balance.HOME_SLEEP_QUALITY == 1.0 and Balance.OUTDOOR_SLEEP_QUALITY == 0.6, "Quality balance is numeric 1.0/0.6")
	check(Dynamics.FATIGUE_RATES[Activity.SLEEPING] == -30, "Base sleep recovery remains unchanged")
	# Per-action snapshots, two simultaneous contexts and committed housing changes.
	var scene = Setup.make_scene(self)
	var actor = scene.resident_runtimes[0]
	var other = scene.resident_runtimes[1]
	var house = scene.player_control.get_home(actor.data.id)
	var other_house = scene.player_control.get_home(other.data.id)
	var lines: Array[String] = []
	scene.game_logger.debug_enabled = true
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	scene.player_control.clear_home(other.data.id)
	night(scene)
	var trip = actor.intents.current_intent
	check(actor.data.activity == Activity.MOVING and other.data.activity == Activity.SLEEPING, "Ordinary home sleep travels, outdoor sleeps locally")
	check(other.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY, "Homeless night action uses outdoor quality")
	scene.player_control.assign_home(actor.data.id, other_house.id)
	check(actor.intents.current_intent == trip and trip.target_position == house.position, "Reassign during trip preserves concrete sleep destination")
	actor.view._process(20)
	check(actor.data.current_sleep_quality == Balance.HOME_SLEEP_QUALITY and actor.view.global_position == house.position, "Arrival uses committed destination quality, not reassigned housing")
	scene.player_control.clear_home(actor.data.id)
	check(actor.data.current_sleep_quality == Balance.HOME_SLEEP_QUALITY and actor.data.activity == Activity.SLEEPING, "Eviction cannot change active home sleep quality")
	scene.player_control.assign_home(other.data.id, other_house.id)
	check(other.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY and other.data.activity == Activity.SLEEPING, "Assignment cannot improve active outdoor sleep quality")
	for runtime in [actor, other]:
		runtime.data.fatigue = 80
		scene.game_time.minute_changed.connect(runtime.need_dynamics._on_minute_changed)
	scene.game_time.advance(60)
	check(actor.data.fatigue == 80 - recovery(60, Balance.HOME_SLEEP_QUALITY), "Home sleep recovers exact base rate")
	check(other.data.fatigue == 80 - recovery(60, Balance.OUTDOOR_SLEEP_QUALITY), "Simultaneous outdoor sleep recovers base times quality independently")
	var logged_count := lines.filter(func(line): return line.contains("quality=")).size()
	for repeat in range(5):
		actor.schedule.resume_current_phase()
		other.schedule.resume_current_phase()
	check(lines.filter(func(line): return line.contains("quality=")).size() == logged_count, "Quality start logs do not spam on schedule resume")
	check(lines.any(func(line): return line.contains("начал спать дома, quality=1.00")) and lines.any(func(line): return line.contains("начал спать снаружи, quality=0.60")), "Both contexts have explicit start logs")
	scene.game_time.debug_next_phase()
	night(scene)
	other.view._process(20)
	check(actor.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY and other.data.current_sleep_quality == Balance.HOME_SLEEP_QUALITY, "Next sleep action resolves new housing state")
	scene.free()

	# Invalid IDs/buildings become outdoor-quality, including disappearance in transit.
	for missing_during_trip in [false, true]:
		scene = Setup.make_scene(self)
		actor = scene.resident_runtimes[0]
		house = scene.player_control.get_home(actor.data.id)
		if not missing_during_trip: actor.data.home_location_id = &"missing"
		night(scene)
		if missing_during_trip:
			scene.buildings.erase(house)
			actor.view._process(20)
		check(actor.data.activity == Activity.SLEEPING and actor.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY, "Invalid home or invalidated trip falls back to outdoor quality")
		check(not actor.view.has_movement_target, "Invalid home fallback does not strand resident")
		scene.free()

	# Critical daytime sleep is on-spot, even with a valid assigned HOME.
	scene = Setup.make_scene(self)
	actor = scene.resident_runtimes[0]
	var before: Vector2 = actor.view.global_position
	lines.clear()
	scene.game_logger.debug_enabled = true
	scene.game_logger.line_logged.connect(func(line, _level): lines.append(line))
	actor.data.fatigue = 100
	check(actor.data.activity == Activity.SLEEPING and actor.intents.current_intent.reason_id == &"critical_sleep" and actor.intents.forced_priority == 100, "Critical fatigue priority and sleep context unchanged")
	check(actor.data.current_sleep_quality == Balance.OUTDOOR_SLEEP_QUALITY and not actor.view.has_movement_target and actor.view.global_position == before, "Assigned home never improves on-spot critical sleep")
	scene.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
	scene.game_time.advance(60)
	check(actor.data.fatigue == 100 - recovery(60, Balance.OUTDOOR_SLEEP_QUALITY), "Critical sleep recovery uses outdoor multiplier")
	check(lines.any(func(line): return line.contains("[NEED][DEBUG]") and line.contains("quality=0.60")), "Critical context logs quality once")
	check(scene.player_control.move_to(actor.data.id, before + Vector2(80, 80)) and actor.commands.active_command != null and actor.data.activity == Activity.MOVING, "PlayerCommand still interrupts critical sleep immediately")
	scene.free()

	# Real scheduled sleep at every supported time scale and pause.
	for quality in [Balance.HOME_SLEEP_QUALITY, Balance.OUTDOOR_SLEEP_QUALITY]:
		for speed in Clock.SUPPORTED_SPEEDS:
			scene = Setup.make_scene(self)
			actor = scene.resident_runtimes[0]
			if quality == Balance.OUTDOOR_SLEEP_QUALITY: scene.player_control.clear_home(actor.data.id)
			night(scene)
			actor.view._process(20)
			actor.data.fatigue = 80
			scene.game_time.minute_changed.connect(actor.need_dynamics._on_minute_changed)
			scene.game_time.set_speed(speed)
			scene.game_time.advance(60.0 / speed)
			check(actor.data.fatigue == 80 - recovery(60, quality), "Same scheduled recovery at x%d, quality %.2f" % [speed, quality])
			var fatigue: int = actor.data.fatigue
			paused = true
			scene.game_time.advance(100)
			check(actor.data.fatigue == fatigue, "Pause freezes recovery at x%d" % speed)
			paused = false
			check(scene.player_control.move_to(actor.data.id, actor.view.global_position + Vector2(80, 80)), "PlayerCommand interrupts ordinary sleep at either quality")
			check(actor.data.activity != Activity.SLEEPING and actor.commands.active_command != null, "Command executes without sleep exception")
			scene.free()

	# Generic numeric multiplier and fractional accumulation, without future systems.
	for quality in [1.0, 0.6, 0.75]:
		var clock = Clock.new()
		root.add_child(clock)
		clock.set_process(false)
		var data = Data.new("numeric", "Numeric", 30)
		data.fatigue = 80
		data.start_sleep(quality)
		var dynamics = Dynamics.new()
		root.add_child(dynamics)
		dynamics.setup(clock, data)
		clock.advance(60)
		check(data.fatigue == 80 - recovery(60, quality), "Numeric quality preserves fractional recovery")
		clock.advance(60)
		check(data.fatigue == 80 - recovery(120, quality), "Fractional recovery carries across consecutive hours")
		data.fatigue = 1
		clock.advance(20)
		check(data.fatigue == 0, "Recovery clamps at minimum fatigue")
		data.activity = Activity.WORKING
		data.fatigue = 40
		clock.advance(60)
		check(data.fatigue == 44, "Awake fatigue growth ignores prior sleep quality")
		clock.free()
		dynamics.free()

	# A legally shared full house supplies normal quality, no bed occupancy checks.
	scene = Setup.make_scene(self)
	house = scene.player_control.get_home(scene.residents[0].id)
	for resident in scene.residents:
		if resident.home_location_id != house.id: scene.player_control.assign_home(resident.id, house.id)
	night(scene)
	for runtime in scene.resident_runtimes:
		runtime.view._process(20)
		check(runtime.data.activity == Activity.SLEEPING and runtime.data.current_sleep_quality == Balance.HOME_SLEEP_QUALITY, "Shared housing capacity does not reduce sleep quality")
	scene.free()
	print("Sleep quality: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
