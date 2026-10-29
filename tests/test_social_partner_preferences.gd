extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const World = preload("res://scripts/social_world.gd")
const Choice = preload("res://scripts/weighted_choice.gd")
const Trait = preload("res://scripts/trait_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Assignment = preload("res://scripts/resident_assignment.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
class Partner extends Node:
	var data: RefCounted
	var intents = preload("res://scripts/resident_intent_controller.gd").new()
	var social := Node.new()
	func _init(id: String) -> void:
		data = preload("res://scripts/resident_data.gd").new(id, id, 25)
		intents.setup(data); add_child(intents); add_child(social)
var failures := 0
var checks := 0
var simulations: Array = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), message)
func configure(data: RefCounted, trait_type: int) -> void:
	for old in data.traits.duplicate(): data.remove_trait(old)
	if trait_type >= 0: data.add_trait(trait_type)
func fixture(count: int) -> Node:
	var container := Node.new(); root.add_child(container)
	var world := World.new(); container.add_child(world)
	world.position_provider = func(id): return Vector2.ZERO if id == "chooser" else Vector2(100, 0)
	for index in count + 1:
		var actor := Partner.new("chooser" if index == 0 else "target_%d" % index)
		container.add_child(actor); world.register(actor)
	return container
func sample(world: Node, actor: Node, label: String, expected: Array[float]) -> void:
	var options: Array = world.options_for(actor.data.id)
	check(options.size() == expected.size(), "Simulation retains all eligible options")
	var rng := RandomNumberGenerator.new(); rng.seed = 20261029
	var counts: Array[int] = []; counts.resize(options.size()); counts.fill(0)
	for draw in 60000:
		var picked = Choice.pick(options, rng)
		counts[options.find(picked)] += 1
	var total := 0.0
	for weight in expected: total += weight
	var result: Array = []
	for index in options.size():
		near(options[index].option_weight / (500.0 / 1.1), expected[index], "Combined distance, opinion and size weight")
		var probability: float = float(counts[index]) / 60000.0
		check(counts[index] > 0 and absf(probability - expected[index] / total) < 0.008, "Weighted frequencies retain positive chances and match expected probabilities")
		result.append({"target": options[index].target_id, "group": options[index].group_id, "count": counts[index], "expected": expected[index] / total, "observed": probability})
	simulations.append({"scenario": label, "draws": 60000, "options": result})
func run() -> void:
	var data := Data.new("pure", "Pure", 25)
	var opinions: Array[int] = [-100, -50, 0, 50, 100]
	for variant in [[-1, [0.7, 0.85, 1.0, 1.15, 1.3], [1.0, 1.0, 1.0, 1.0]], [Trait.SOCIABLE, [1.0, 1.15, 1.3, 1.15, 1.0], [1.0, 1.1, 1.21, 1.331]], [Trait.INTROVERTED, [0.4, 0.7, 1.0, 1.3, 1.6], [1.0, 0.9, 0.81, 0.729]]]:
		configure(data, variant[0])
		for index in opinions.size(): near(Modifiers.social_partner_multiplier(data, opinions[index]), variant[1][index], "Approved opinion anchors")
		for count in range(1, 5): near(Modifiers.social_company_multiplier(data, count), variant[2][count - 1], "Approved company sizes")
		for opinion in range(-100, 101):
			var expected: float = 1.0 + 0.003 * opinion
			if variant[0] == Trait.SOCIABLE: expected = 1.3 - 0.003 * abs(opinion)
			elif variant[0] == Trait.INTROVERTED: expected = 1.0 + 0.006 * opinion
			near(Modifiers.social_partner_multiplier(data, opinion), expected, "Smooth formula between anchors")
			check(expected > 0, "Every valid opinion retains a positive multiplier")
		var container := fixture(5); var world: Node = container.get_child(0)
		var actor: Node = world.get_runtime("chooser"); configure(actor.data, variant[0])
		for index in opinions.size():
			var target_id := StringName("target_%d" % (index + 1))
			actor.data.set_opinion(target_id, opinions[index])
			world.get_runtime(String(target_id)).data.set_opinion(&"chooser", 100)
		check(not actor.data.has_relationship(&"target_3"), "Neutral missing opinion does not allocate relationship state")
		var expected_weights: Array[float] = []; expected_weights.assign(variant[1])
		sample(world, actor, "individual_%s" % variant[0], expected_weights)
		var original: Array = world.options_for(actor.data.id)
		var explicit: Dictionary = world.target_option(actor.data.id, "target_1")
		world.get_runtime("target_1").data.set_opinion(&"chooser", -100)
		check(world.options_for(actor.data.id) == original, "Reverse opinion never affects chooser weights")
		var chooser_position := Vector2.ZERO
		world.position_provider = func(id): return chooser_position if id == "chooser" else Vector2(1000 if id == "target_1" else 100, 0)
		near(world.options_for(actor.data.id)[0].option_weight, 250.0 * variant[1][0], "Original distance penalty is multiplied, not replaced")
		world.get_runtime("target_1").data.activity = Activity.WORKING
		check(world.options_for(actor.data.id).size() == 4, "Busy candidate stays unavailable even with positive weight")
		world.get_runtime("target_1").data.activity = Activity.IDLE
		check(world.target_option(actor.data.id, "target_1") == explicit, "Direct target metadata is independent of preference weights")
		container.free()
		_group_cases(variant[0])
	_direct_commands()
	print("PARTNER_SIMULATION ", JSON.stringify(simulations))
	print("Social partner preferences: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _group_cases(trait_type: int) -> void:
	var container := fixture(10); var world: Node = container.get_child(0)
	var actor: Node = world.get_runtime("chooser"); configure(actor.data, trait_type)
	var groups: Array = []; var next := 1
	var weights: Array[float] = []
	for values in [[0], [100, -100], [100, 0, -100], [100, -100, 50, -50]]:
		var group = world.create_group(Vector2(100, 0)) if values.size() > 1 else null
		groups.append(group)
		var directed: Array[int] = []
		for opinion in values:
			var id := "target_%d" % next; next += 1
			var member: Node = world.get_runtime(id)
			if group != null: member.data.activity = Activity.TALKING; group.add_participant(id)
			actor.data.set_opinion(StringName(id), opinion); directed.append(opinion)
		var mean := 0.0
		for opinion in values:
			mean += (1.3 - 0.003 * abs(opinion)) if trait_type == Trait.SOCIABLE else (1.0 + (0.006 if trait_type == Trait.INTROVERTED else 0.003) * opinion)
		weights.append(mean / values.size() * pow(1.1 if trait_type == Trait.SOCIABLE else (0.9 if trait_type == Trait.INTROVERTED else 1.0), values.size() - 1))
		near(Modifiers.social_partner_weight(actor.data, directed), weights.back(), "Mean individual opinions precedes company size")
	sample(world, actor, "groups_%s" % trait_type, weights)
	var original: Array = world.options_for(actor.data.id)
	groups[1].participants.reverse()
	check(world.options_for(actor.data.id) == original, "Averaging is independent of participant order")
	groups[1].participants.append("deleted_resident")
	groups[1].participants.append(actor.data.id)
	groups[1].pending["target_10"] = {"arrived": false}
	check(world.options_for(actor.data.id) == original, "Self, stale links and pending approaches do not inflate company size")
	groups[1].participants.erase(actor.data.id)
	world.get_runtime("target_3").data.activity = Activity.MOVING
	var updated: Array = world.options_for(actor.data.id)
	near(updated[1].option_weight / (500.0 / 1.1), Modifiers.social_partner_multiplier(actor.data, 100), "Inactive group participant is excluded from mean and size")
	container.free()
func _direct_commands() -> void:
	for trait_type in [-1, Trait.SOCIABLE, Trait.INTROVERTED]:
		var scene := Setup.make_scene(self)
		var actor: Node = scene.resident_runtimes[1]; var target: Node = scene.resident_runtimes[3]
		configure(actor.data, trait_type)
		actor.data.set_opinion(StringName(target.data.id), -100); target.data.set_opinion(StringName(actor.data.id), 100)
		actor.data.get_need(2).value = 100; target.data.get_need(2).value = 100
		var task := Assignment.new(&"direct_preference", actor.data.id, Assignment.TALK_TO, StringName(target.data.id))
		check(scene.player_control.add_assignment(actor.data.id, task) and actor.assignments.start(task.id), "Player command starts despite negative opinion for every trait")
		actor.view._process(100)
		check(scene.social_world.group_of(actor.data.id) == scene.social_world.group_of(target.data.id), "Player command keeps exact target")
		scene.game_time.debug_skip_minutes(15)
		check(task.state == Assignment.State.COMPLETED, "Original shared conversation duration completes TALK_TO")
		check(actor.data.get_opinion(StringName(target.data.id)) == -100 and target.data.get_opinion(StringName(actor.data.id)) == 100, "Command and conversation do not add relation changes")
		scene.free()
