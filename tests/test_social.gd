extends SceneTree
const Activity = preload("res://scripts/resident_activity.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Choice = preload("res://scripts/weighted_choice.gd")
const Intent = preload("res://scripts/resident_intent.gd")
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func make_scene():
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.logistics.cancel_job(scene.logistics.current_job)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	for runtime in scene.resident_runtimes:
		runtime.view.set_process(false)
		runtime.wander.target_provider = Callable()
		runtime.data.work_location_id = &""
		runtime.decision.work_available = Callable()
		runtime.data.hunger = 0
		runtime.data.fatigue = 0
	return scene
func arrive(runtime):
	runtime.view.global_position = runtime.intents.current_intent.target_position
	runtime.intents.report_arrival(runtime.intents.current_intent)
func _run():
	var options = [{"option_weight": 500.0, "id": 0}, {"option_weight": 300.0, "id": 1}, {"option_weight": 200.0, "id": 2}]
	var a = RandomNumberGenerator.new()
	var b = RandomNumberGenerator.new()
	a.seed = 123
	b.seed = 123
	var counts = [0, 0, 0]
	for i in range(10000):
		var picked = Choice.pick(options, a)
		check(picked == Choice.pick(options, b), "Seed reproduces weighted choices")
		counts[picked.id] += 1
	check(abs(counts[0] - 5000) < 200 and abs(counts[1] - 3000) < 200 and abs(counts[2] - 2000) < 200, "Weighted frequencies approximate 50/30/20")
	check(Choice.pick([{ "option_weight": 0.0 }], a) == null, "No positive option means no action")
	var scene = make_scene()
	var r = scene.resident_runtimes
	var world = scene.social_world
	check(r[0].data.get_need(Type.SOCIAL).base_weight == 80 and r[0].data.get_need(Type.LEISURE).base_weight == 75, "New base weights")
	# Make one compatible target; every other activity is excluded.
	for incompatible in [Activity.Type.MOVING, Activity.Type.WORKING, Activity.Type.EATING, Activity.Type.RESTING, Activity.Type.RELAXING, Activity.Type.SLEEPING, Activity.Type.HAULING]:
		r[1].data.activity = incompatible
		r[2].data.activity = incompatible
		r[3].data.activity = incompatible
		check(world.options_for(r[0].data.id).is_empty(), "Exclude incompatible activities")
	r[1].data.activity = Activity.Type.IDLE
	r[2].data.activity = Activity.Type.WORKING
	r[3].data.activity = Activity.Type.WORKING
	for runtime in r: runtime.data.get_need(Type.SOCIAL).value = 80
	check(r[0].social.try_social(5600), "First resident chooses available social option")
	arrive(r[0])
	check(world.groups.size() == 1 and r[0].data.activity == Activity.Type.TALKING and r[1].data.activity == Activity.Type.TALKING, "Arrival creates two-member conversation")
	r[2].data.activity = Activity.Type.IDLE
	check(r[2].social.try_social(5600), "Third joins an existing group")
	arrive(r[2])
	r[3].data.activity = Activity.Type.IDLE
	check(r[3].social.try_social(5600), "Fourth joins an existing group")
	arrive(r[3])
	check(world.groups.values()[0].participants.size() == 4, "Conversation is not restricted to pairs")
	print("Conversation proof: 4 participants TALKING")
	scene.resident_selection.select(r[0].data)
	var card = scene.get_node("HUD/ResidentCard")
	card._refresh()
	check("80/100" in card.social_label.text and "Разговаривает" in card.activity_label.text, "Card reads selected social need and activity")
	var old_social: int = r[0].data.get_need(Type.SOCIAL).value
	paused = true
	scene.game_time.advance(1000)
	check(r[0].data.get_need(Type.SOCIAL).value == old_social and r[0].data.activity == Activity.Type.TALKING, "Pause freezes conversation timer and need")
	paused = false
	var choices = world.options_for("observer")
	check(choices.size() == 1, "One option per group, not per member")
	var decision_count = r[0].decision.decision_count
	scene.game_time.debug_skip_minutes(1)
	check(r[0].decision.decision_count == decision_count, "No ordinary redecision during conversation")
	r[0].data.get_need(Type.SOCIAL).value = 0
	for runtime in r: runtime.data.get_need(Type.LEISURE).value = 0
	scene.game_time.debug_skip_minutes(1)
	check(world.groups.values()[0].participants.size() == 4, "SOCIAL zero cannot end conversation before 15 minutes")
	r[0].data.get_need(Type.LEISURE).value = 80
	for runtime in r:
		runtime.social.rng.seed = continuing_seed()
	scene.game_time.debug_skip_minutes(13)
	check(world.groups.values()[0].participants.size() == 3 and r[1].data.activity == Activity.Type.TALKING, "One participant leaves independently; other three continue")
	print("Conversation proof: one leaves independently, 3 remain TALKING")
	# Forced fatigue leaves immediately, even though social action is locked.
	r[1].data.fatigue = 100
	check(r[1].data.activity == Activity.Type.SLEEPING and world.groups.values()[0].participants.size() == 2, "Critical fatigue interrupts talking and removes member")
	# Critical hunger also dissolves a group with a single remaining member.
	scene.kitchen_data.resources.add(preload("res://scripts/resource_type.gd").Type.FOOD, 1)
	r[2].data.hunger = 100
	check(r[2].intents.current_intent.reason_id == &"eat" and world.groups.is_empty(), "Critical hunger interrupts conversation and disbands singleton")
	print("Conversation proof: forced fatigue/hunger remove members and dissolve singleton")
	r[3].data.get_need(Type.SOCIAL).value = 0
	await process_frame
	check(r[3].data.activity != Activity.Type.TALKING, "Remaining member receives a new decision point")
	scene.free()
	scene = make_scene()
	r = scene.resident_runtimes
	world = scene.social_world
	r[2].data.activity = Activity.Type.WORKING
	r[3].data.activity = Activity.Type.WORKING
	r[0].data.get_need(Type.SOCIAL).value = 80
	check(r[0].social.try_social(5600), "Route starts to idle resident")
	r[1].data.activity = Activity.Type.WORKING
	decision_count = r[0].decision.decision_count
	scene.game_time.debug_skip_minutes(1)
	check(r[0].intents.current_intent.reason_id != &"social" and r[0].decision.decision_count > decision_count, "Unavailable target cancels route and redecides")
	r[0].data.get_need(Type.SOCIAL).value = 0
	r[0].data.get_need(Type.LEISURE).value = 90
	r[0].decision.request_decision()
	check(r[0].data.activity == Activity.Type.RELAXING, "Leisure starts on the spot")
	scene.game_time.debug_skip_minutes(10)
	check(r[0].data.get_need(Type.LEISURE).value in [60, 61], "Leisure decreases progressively, preserving fractional remainder")
	r[0].data.fatigue = 100
	check(r[0].data.activity == Activity.Type.SLEEPING, "Forced interrupt ends leisure")
	scene.free()
	await _extra_cases()
	print("Social and leisure checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _extra_cases():
	var scene = make_scene()
	var r = scene.resident_runtimes
	var world = scene.social_world
	# Nearby options receive more weight, without always winning.
	r[1].view.position = Vector2(10, 0)
	r[2].view.position = Vector2(1000, 0)
	r[0].view.position = Vector2.ZERO
	var options = world.options_for(r[0].data.id)
	check(options[0].option_weight > options[1].option_weight, "Distance penalizes social option weight")
	r[2].data.activity = Activity.Type.WORKING
	r[3].data.activity = Activity.Type.WORKING
	for runtime in r: runtime.data.get_need(Type.SOCIAL).value = 60
	r[0].social.try_social(4200)
	arrive(r[0])
	r[2].data.activity = Activity.Type.IDLE
	check(r[2].social.try_social(4200), "Join route to existing group")
	# Critical departure dissolves the group while the third is on its way.
	r[0].data.fatigue = 100
	r[1].data.get_need(Type.SOCIAL).value = 0
	await process_frame
	var count = r[2].decision.decision_count
	var old_route = r[2].intents.current_intent
	scene.game_time.debug_skip_minutes(1)
	check(world.groups.is_empty() and r[2].intents.current_intent != old_route and r[2].decision.decision_count > count, "Dissolved group invalidates the old join route")
	scene.free()
	# A normal nighttime obligation waits for the social action to finish.
	scene = make_scene()
	r = scene.resident_runtimes
	world = scene.social_world
	scene.game_time.total_minutes = 1379
	r[2].data.activity = Activity.Type.WORKING
	r[3].data.activity = Activity.Type.WORKING
	for runtime in r: runtime.data.get_need(Type.SOCIAL).value = 90
	r[0].social.try_social(6300)
	arrive(r[0])
	scene.game_time.debug_skip_minutes(1)
	check(r[0].data.activity == Activity.Type.TALKING and r[0].intents.pending_intent.reason_id == &"night_home", "Ordinary night waits in pending during talking")
	scene.game_time.debug_skip_minutes(29)
	await process_frame
	check(world.groups.is_empty() and r[0].intents.current_intent.reason_id == &"night_home", "Conversation completes before pending home goal runs")
	scene.free()
	# Leisure also finishes normally and triggers a new decision, with no travel.
	scene = make_scene()
	r = scene.resident_runtimes
	r[0].data.get_need(Type.LEISURE).value = 40
	r[0].decision.request_decision()
	check(r[0].data.activity == Activity.Type.RELAXING, "No work permits leisure below 7000")
	var original_position: Vector2 = r[0].view.position
	scene.game_time.debug_skip_minutes(10)
	check(r[0].data.activity == Activity.Type.RELAXING and r[0].view.position == original_position, "Satisfied leisure remains committed")
	scene.game_time.debug_skip_minutes(20)
	check(r[0].data.activity == Activity.Type.IDLE, "Leisure completes after 30 minutes")
	# Needs below 7000 still lose to an available job.
	r[0].data.work_location_id = scene.warehouse_data.id
	r[0].decision.work_available = func(): return true
	r[0].data.get_need(Type.SOCIAL).value = 87
	r[0].data.get_need(Type.LEISURE).value = 93
	scene.game_time.total_minutes = 420
	r[0].schedule._on_phase_changed("День")
	check(r[0].intents.current_intent.reason_id == &"day_work", "Work wins at priority 7000 and below")
	scene.free()

func continuing_seed() -> int:
	var random = RandomNumberGenerator.new()
	for seed_value in range(100):
		random.seed = seed_value
		if random.randf() >= 0.2: return seed_value
	return 0
