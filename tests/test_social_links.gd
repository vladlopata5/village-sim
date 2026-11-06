extends SceneTree
const Store = preload("res://scripts/social_link_store.gd")
const Data = preload("res://scripts/resident_data.gd")
const PlayerRegistry = preload("res://scripts/player_control.gd")
const Social = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Facts = preload("res://scripts/resident_event_facts.gd")
const Mood = preload("res://tests/mood_test_setup.gd")

class Rolls extends RefCounted:
	var values: Array[float] = [100.0, 0.0]
	var draws := 0
	func randf_range(_minimum: float, _maximum: float) -> float:
		var value := values[draws]
		draws += 1
		return value

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	transitions()
	opinions()
	lifecycle_and_facts()
	reactions()
	print("Social links: %d checks, %d failures" % [checks, failures])
	quit(int(failures != 0))

func transitions() -> void:
	var links := Store.new()
	var a := Data.new("a:b", "A", 25)
	var b := Data.new("c", "B", 25)
	check(links.register_resident(a) and links.register_resident(b), "Registers distinct identities")
	check(not links.register_resident(Data.new(" ", "Invalid", 25)), "Whitespace-only IDs rejected")
	check(links.get_link(a, a).is_empty() and links.get_link(a, Data.new("c", "Impostor", 25)).is_empty(), "Self and unregistered identities rejected")
	check(links.get_level(a, b) == 0 and links.get_link(b, a).revision == 0 and links._pairs.is_empty(), "Default level read allocates no pair")
	check(links.prepare_transition(a, b, 2, 0).is_empty() and links.prepare_transition(a, b, 4, 0, true).is_empty(), "Normal transition adjacent, all levels valid")
	check(links.prepare_transition(a, b, 1.5, 0, true).is_empty(), "Fractional levels rejected")
	var first := links.prepare_transition(a, b, 1, 7)
	var stale := links.prepare_transition(b, a, -1, 7)
	check(links.commit_transition(first, 12), "First transition commits at a later minute")
	check(links.get_level(b, a) == 1 and links.get_link(a, b).normal_transition_available_at == 10092, "Symmetric deadline uses commit time")
	check(not links.commit_transition(first, 13) and not links.commit_transition(stale, 10092), "Replay and competing stale preparation rejected")
	check(links.prepare_transition(b, a, 0, 10091).is_empty(), "Blocked at 10079 minutes")
	var normal := links.prepare_transition(b, a, 0, 10092)
	check(not normal.is_empty() and not links.commit_transition(normal, 10091), "Commit rechecks time")
	check(links.commit_transition(normal, 10092) and not links.normal_transition_ready(a, b, 10092), "Return to zero retains cooldown")
	check(links.prepare_transition(b, a, 0, 10093, true).is_empty() and links.get_link(a, b).normal_transition_available_at == 20172, "Same level does not extend cooldown")
	check(links.commit_transition(links.prepare_transition(a, b, -3, 10093, true), 10093), "Special transition bypasses time and adjacency")
	check(links.get_link(b, a).normal_transition_available_at == 20173, "Special transition starts a fresh cooldown")
	var projected := links.counts_after_transition(a, b, -2)
	check(projected.negative_1 == 1 and projected.negative_2 == 1 and projected.negative_3 == 0, "Projection replaces old contribution once")
	var neighbors: Array = []
	for index in 7:
		var person := Data.new("neighbor-%d" % index, "Neighbor", 25)
		neighbors.append(person)
		links.register_resident(person)
		var level := 3 if index < 6 else -2
		check(links.commit_transition(links.prepare_transition(a, person, level, 15, true), 15), "Domain counts without imposing event caps")
	check(links.counts_for(a) == {"positive_1": 6, "positive_2": 6, "positive_3": 6, "negative_1": 2, "negative_2": 2, "negative_3": 1}, "Nested counts cover all six categories")

func opinions() -> void:
	for level in range(-3, 4):
		check_level_bounds(level)
	var links := Store.new()
	var a := Data.new("a", "A", 25)
	var b := Data.new("b", "B", 25)
	links.register_resident(a)
	links.register_resident(b)
	check(links.commit_transition(links.prepare_transition(a, b, 2, 0, true), 0), "Raise pair")
	a.set_opinion("b", 65)
	check(links.commit_transition(links.prepare_transition(a, b, -2, 1, true), 1), "Change level across zero")
	b.set_opinion("a", -65)
	check(links.commit_transition(links.prepare_transition(a, b, 0, 2, true), 2), "Return to level zero")
	check(a.get_opinion("b") == 65 and b.get_opinion("a") == -65, "Level writes never change either opinion")
	check(not a.set_opinion("b", 75) and not b.change_opinion("a", -1), "Outward writes rejected from both sides")
	check(a.apply_opinion_change("b", -1) == {"before": 65, "after": 64} and b.set_opinion("a", -64), "Small steps move toward the range")
	check(a.set_opinion("b", -1000) and a.get_opinion("b") == -25 and b.change_opinion("a", 1000) and b.get_opinion("a") == 25, "Overshoot clamps at the opposite edge")
	check(not a.set_opinion("missing", 15), "Bound resident cannot create a stale opinion for an unknown ID")

func check_level_bounds(level: int) -> void:
	var links := Store.new()
	var a := Data.new("a", "A", 25)
	var b := Data.new("b", "B", 25)
	links.register_resident(a)
	links.register_resident(b)
	if level != 0: check(links.commit_transition(links.prepare_transition(a, b, level, 0, true), 0), "Fixture level")
	a.set_opinion("b", 25 * level)
	b.set_opinion("a", 25 * level)
	a.set_opinion("b", 1000)
	b.set_opinion("a", -1000)
	check(a.get_opinion("b") == 25 * level + 25 and b.get_opinion("a") == 25 * level - 25, "Level %d bounds both independent directions" % level)
	check(not a.change_opinion("b", 1) and not b.change_opinion("a", -1), "Reached edges block outward delta")
	check(a.change_opinion("b", -1000) and a.get_opinion("b") == 25 * level - 25, "Large delta ends at the far edge")
	check(b.change_opinion("a", 1000) and b.get_opinion("a") == 25 * level + 25, "Reverse direction can reach the opposite edge")

func lifecycle_and_facts() -> void:
	var control := PlayerRegistry.new()
	var a := Data.new("a", "A", 25)
	var b := Data.new("b", "B", 25)
	control.setup([a, b], [])
	var links := control.social_links
	var a_ref := {"kind": "resident", "id": "a"}
	var b_ref := {"kind": "resident", "id": "b"}
	var defaults = Facts.snapshot(a, b, 0, links)
	check(defaults.read(a_ref, "link.level", b_ref).value == 0 and defaults.read(b_ref, "link.normal_transition_ready", a_ref).value, "Default pair facts available without creating state")
	check(links.commit_transition(links.prepare_transition(a, b, 1, 0), 0), "Live registry connects pair")
	a.set_opinion("b", 22)
	b.set_opinion("a", 11)
	var frozen = Facts.snapshot(a, b, 10079, links)
	var ready = Facts.snapshot(a, b, 10080, links)
	check(frozen.read(a_ref, "link.level", b_ref).value == 1 and not frozen.read(a_ref, "link.normal_transition_ready", b_ref).value, "Pair snapshot contains level and lock")
	check(ready.read(b_ref, "link.normal_transition_ready", a_ref).value and ready.read(b_ref, "link.counts").value.positive_1 == 1, "Reverse pair readiness and nested count")
	var pending := links.prepare_transition(a, b, 2, 10080)
	control.unregister_resident("b")
	control.register_resident(b)
	check(links.get_level(b, a) == 1 and a.get_opinion("b") == 22 and b.get_opinion("a") == 11, "Same object after temporary absence keeps state")
	var replacement := Data.new("b", "Replacement", 25)
	control.setup([replacement], [])
	check(links.get_level(a, replacement) == 0 and a.get_opinion("b") == 0 and b.get_opinion("a") == 0, "Setup replacement clears both old directions and shared link")
	check(not links.commit_transition(pending, 10080) and not b.set_opinion("a", 9), "Old generation cannot commit or write opinion")
	var service := Social.new()
	check(service.resolve(a, b, Event.Context.WORK) == null and a.get_opinion("b") == 0, "Late interaction with replaced object cannot write opinion on its successor")
	service.free()
	check(frozen.read(a_ref, "link.level", b_ref).value == 1, "Previous snapshot is detached")
	check(links.commit_transition(links.prepare_transition(a, replacement, -1, 10081), 10081), "New identity can form its own link")
	a.set_opinion("b", -17)
	control.unregister_resident("b")
	control.unregister_resident("b", true)
	check(a.get_opinion("b") == 0 and links.counts_for(a).negative_1 == 0, "Permanent removal also works after temporary absence")
	control.register_resident(replacement)
	check(links.get_level(a, replacement) == 0 and links.normal_transition_ready(a, replacement, 10082), "Re-registration after deletion starts clean")
	control.unregister_resident("b")
	a.set_opinion("b", 18)
	control.register_resident(Data.new("b", "Third identity", 25))
	check(a.get_opinion("b") == 0, "Registration of different object after absence clears opinion")

func reactions() -> void:
	for example in [[-100, 50.0, 40.0, 10.0], [-50, 37.5, 50.0, 12.5], [0, 25.0, 50.0, 25.0], [50, 12.5, 50.0, 37.5], [100, 10.0, 40.0, 50.0]]:
		var probabilities := Social.reaction_probabilities(example[0])
		check(probabilities == example.slice(1), "Control distribution %d" % example[0])
		check(Social.reaction(example[0], probabilities[0] - 0.001) == Event.Reaction.NEGATIVE and Social.reaction(example[0], probabilities[0]) == Event.Reaction.NEUTRAL, "Exact negative cutoff")
		check(Social.reaction(example[0], 100.0 - probabilities[2]) == Event.Reaction.POSITIVE and Social.reaction(example[0], 0.0) == Event.Reaction.NEGATIVE, "Exact positive cutoff and opposite reaction")
	var a := Data.new("a", "A", 25)
	var b := Data.new("b", "B", 25)
	for example in [[0, -25], [25, -25], [50, 0], [75, 25], [100, 25]]:
		Mood.set_value(a, example[0])
		check(Social.attitude(a, b) == example[1], "Mood saturation at %d" % example[0])
	Mood.set_value(a, 50.125)
	b.set_traits([Trait.Type.FOOLISH, Trait.Type.CARING, Trait.Type.RESTLESS])
	for type in b.traits: a.add_liked_trait(type)
	check(Social.attitude(a, b) == 30.125 and Social.reaction_probabilities(30.125)[2] == 32.53125, "Existing tastes have no new cap and fractional mood reaches probability")
	var service := Social.new()
	var rng := Rolls.new()
	service.rng = rng
	var mutate := func(_target): b.set_opinion("a", 20)
	a.relationship_changed.connect(mutate)
	var result := service.resolve(a, b, Event.Context.MEAL)
	a.relationship_changed.disconnect(mutate)
	var payload: Dictionary = result.confirmed_context().payload
	check(rng.draws == 2 and payload.reaction_1 == "POSITIVE" and payload.reaction_2 == "NEGATIVE", "Independent rolls preserve confirmed payload")
	check(payload.attitude_2_to_1 == 0 and payload.opinion_before_2 == 20 and payload.opinion_after_2 == 19, "Reaction uses pre-mutation snapshot and delta uses current opinion")
	service.free()
