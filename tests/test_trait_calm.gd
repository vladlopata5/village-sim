extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Social = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Generator = preload("res://scripts/resident_generator.gd")
class RoundingRng extends RefCounted:
	var value := 0.9
	var calls := 0
	func randf() -> float: calls += 1; return value
class ReactionRng extends RefCounted:
	var calls := 0
	var rolls: Array = [-100, 100]
	func randi_range(_low: int, _high: int) -> int:
		var result: int = rolls[calls % rolls.size()]; calls += 1; return result
var checks := 0
var failures := 0
var signals := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	_examples()
	_social()
	_generation()
	_statistics()
	print("CALM: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _examples() -> void:
	var person := Data.new("calm", "Calm", 25); person.add_trait(Trait.Type.CALM)
	var rng := RoundingRng.new(); person.opinion_rng = rng
	person.relationship_changed.connect(func(_id): signals += 1)
	# Input, lower-magnitude result, upper-magnitude result, probability of upper.
	for example in [[1, 0, 1, 0.75], [-1, 0, -1, 0.75], [2, 1, 2, 0.5], [-2, -1, -2, 0.5], [-4, -3, -3, 0.0], [4, 3, 3, 0.0], [10, 7, 8, 0.5], [-10, -7, -8, 0.5]]:
		for draw in [0.0, 0.499999, 0.5, 0.7, 0.749999, 0.75, 1.0]:
			person.set_opinion("other", 0); rng.value = draw
			var calls := rng.calls; var notices := signals
			var expected: int = example[2] if draw < example[3] else example[1]
			var result := person.apply_opinion_change("other", example[0])
			check(result.before == 0 and result.after == expected and person.get_opinion("other") == expected, "Agreed signed example and exact probability boundary")
			check(rng.calls == calls + (1 if example[3] > 0 else 0), "One fractional draw, none for exact result")
			check(signals == notices + (1 if expected != 0 else 0), "Rounded zero emits no relationship notification")
	var empty := Data.new("empty", "Empty", 25); empty.add_trait(Trait.Type.CALM); empty.opinion_rng = rng
	rng.value = 0.9; var start_calls := rng.calls
	check(not empty.change_opinion("other", 1) and empty.relationships.is_empty() and rng.calls == start_calls + 1, "Rounded zero consumes one draw, returns false and preserves sparse storage")
	check(empty.apply_opinion_change("other", -1) == {"before":0,"after":0} and empty.relationships.is_empty() and rng.calls == start_calls + 2, "Negative rounded zero has correct before/after")
	var calls_without_change := rng.calls
	check(not empty.change_opinion("other", 0) and not empty.change_opinion("", 1) and not empty.change_opinion("empty", -1) and rng.calls == calls_without_change, "Original zero and invalid targets never draw")
	for bound in [-100, 100]:
		person.set_opinion("other", bound); var old_calls := rng.calls; var old_signals := signals
		check(not person.change_opinion("other", signi(bound)) and rng.calls == old_calls and signals == old_signals, "Outward bound no-op preserves RNG and signals")
		rng.value = 0.9
		check(person.apply_opinion_change("other", -signi(bound)).after == bound and rng.calls == old_calls + 1, "Inward fractional change can legitimately round to zero")
		rng.value = 0.0
		check(person.apply_opinion_change("other", -signi(bound)).after == bound - signi(bound) and rng.calls == old_calls + 2, "Inward nonzero outcome is applied exactly once")
	for direction in [-1, 1]:
		person.set_opinion("other", 99 * direction); rng.value = 0.0
		var old_calls := rng.calls
		check(person.change_opinion("other", 2 * direction) and person.get_opinion("other") == 100 * direction and rng.calls == old_calls + 1, "Rounding precedes final clamp")
	for type in [-1, Trait.Type.HOTHEADED, Trait.Type.CALM, Trait.Type.SOCIABLE, Trait.Type.INTROVERTED]:
		var actor := Data.new("comparison", "Comparison", 25)
		if type >= 0: actor.add_trait(type)
		actor.opinion_rng = rng; var old_calls := rng.calls
		var expected := 6 if type == Trait.Type.HOTHEADED else (3 if type == Trait.Type.CALM else 4)
		check(actor.change_opinion("other", -4) and actor.get_opinion("other") == -expected and rng.calls == old_calls, "Normal, HOTHEADED and other traits preserve exact multipliers")
	for action in Modifiers.Action.values(): check(Modifiers.action_utility(person, action, 5000) == 5000, "No new action utility")
	check(Modifiers.social_need_rate(person, -180) == -180 and Modifiers.social_need_rate(person, 60) == 60 and Modifiers.selector_candidate_ratio(person) == 0.75, "Needs and selector unchanged")
func _social() -> void:
	for context in Event.Context.values():
		for draw in [0.0, 0.9]:
			var a := Data.new("a", "A", 25); var b := Data.new("b", "B", 25); a.add_trait(Trait.Type.CALM)
			var rounding := RoundingRng.new(); rounding.value = draw; a.opinion_rng = rounding
			var service := Social.new(); root.add_child(service); service.entries = []
			var reactions := ReactionRng.new(); service.rng = reactions
			var result = service.resolve(a, b, context); var payload: Dictionary = result.confirmed_context().payload
			var applied := -1 if draw < 0.75 else 0
			check(payload.opinion_delta_1 == -1 and payload.opinion_before_1 == 0 and payload.opinion_after_1 == applied and payload.applied_delta_1 == applied, "Social payload preserves raw reaction and actual zero/nonzero outcome")
			check(a.get_opinion("b") == applied and b.get_opinion("a") == 1 and rounding.calls == 1 and reactions.calls == 2, "Only CALM direction reduced; old reaction RNG unchanged")
			service.present(result, a, b, [], []); service.present(result, a, b, [], [])
			check(rounding.calls == 1 and a.get_opinion("b") == applied, "Repeated presentation cannot reroll or apply twice")
			service.free()
	var nested_person := Data.new("nested", "Nested", 25); nested_person.add_trait(Trait.Type.CALM)
	var rng := RoundingRng.new(); rng.value = 0.0; nested_person.opinion_rng = rng
	var callback := func(_id):
		if nested_person.get_opinion("b") == 1: nested_person.set_opinion("b", 20)
	nested_person.relationship_changed.connect(callback)
	var snapshot := nested_person.apply_opinion_change("b", 1)
	check(snapshot.after == 1 and nested_person.get_opinion("b") == 20 and rng.calls == 1, "Operation snapshot survives callback without another random draw")
	nested_person.relationship_changed.disconnect(callback)
func _generation() -> void:
	var generator := Generator.new(318); var repeat := Generator.new(318); var found := 0
	for index in 1000:
		var a = generator.generate(); var b = repeat.generate()
		check(a.traits.size() == 2 and Trait.compatible(a.traits) and a.traits == b.traits and a.trait_description() == b.trait_description(), "Ten-trait generation and descriptions remain compatible and reproducible")
		for type in a.traits + a.liked_traits + a.disliked_traits: check(type not in [Trait.Type.CARING, Trait.Type.HASTY, Trait.Type.DELIBERATE], "Three unfinished traits excluded")
		if a.has_trait(Trait.Type.CALM): found += 1; check(not a.add_trait(Trait.Type.HOTHEADED), "Generated CALM rejects HOTHEADED")
	check(found > 0 and Trait.GENERATION_POOL.size() == 10, "CALM participates in normal generation")
	check(Trait.description([Trait.Type.CALM, Trait.Type.PRUDENT]) == "Невозмутимый прагматик" and Trait.description([Trait.Type.CARING, Trait.Type.CALM], Trait.GrammaticalGender.FEMININE) == "Заботливая флегматичка", "Both grammatical forms compose with CALM")
func _statistics() -> void:
	var a := Data.new("stat", "Stat", 25); a.add_trait(Trait.Type.CALM)
	var b := Data.new("stat", "Stat", 25); b.add_trait(Trait.Type.CALM)
	var zero := 0; var one := 0
	for index in 20000:
		a.set_opinion("other", 0); b.set_opinion("other", 0)
		var delta := 1 if index % 2 == 0 else -1
		a.change_opinion("other", delta); b.change_opinion("other", delta)
		check(a.get_opinion("other") == b.get_opinion("other"), "Personal RNG is reproducible even after zero outcomes")
		if a.get_opinion("other") == 0: zero += 1
		else: one += 1
	check(one > 14500 and one < 15500 and zero == 20000 - one, "Stochastic rounding averages 0.75 with no fractional remainder")
	print("CALM rounding distribution: zero=", zero, " one=", one, " mean magnitude=", float(one) / 20000)
