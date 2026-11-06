extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Generator = preload("res://scripts/resident_generator.gd")
const Social = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
class RoundingRng extends RefCounted:
	var draw := 0.25
	var calls := 0
	func randf() -> float:
		calls += 1
		return draw
class ReactionRng extends RefCounted:
	var calls := 0
	var probability_calls := 0
	var rolls: Array = [100, 0]
	func randf_range(_low: float, _high: float) -> float:
		var value: float = rolls[calls % rolls.size()]
		calls += 1
		return value
	func randf() -> float:
		probability_calls += 1
		return 0.0
var checks := 0
var failures := 0
var signals := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	_rates()
	_callbacks()
	_social()
	_generation()
	_statistics()
	print("HOTHEADED: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _rates() -> void:
	var a := Data.new("a", "A", 25); var b := Data.new("b", "B", 25)
	var rng := RoundingRng.new(); a.opinion_rng = rng
	a.add_trait(Trait.Type.HOTHEADED)
	a.relationship_changed.connect(func(_id): signals += 1)
	for draw in [0.0, 0.499999, 0.5, 1.0]:
		rng.draw = draw
		for delta in [1, -1, 3, -3]:
			a.set_opinion("b", 0)
			var before_calls := rng.calls
			var snapshot := a.apply_opinion_change("b", delta)
			var expected := (floori(abs(delta) * 1.5) + (1 if draw < 0.5 else 0)) * signi(delta)
			check(a.get_opinion("b") == expected and snapshot.before == 0 and snapshot.after == expected and rng.calls == before_calls + 1, "Fractional signed delta consumes one draw and rounds its magnitude once")
			check(b.get_opinion("a") == 0 and b.relationships.is_empty(), "No automatic reverse opinion")
	for delta in [10, -10, 2, -2, 0]:
		a.set_opinion("b", 0); var before_calls := rng.calls
		check(a.change_opinion("b", delta) == (delta != 0) and a.get_opinion("b") == int(delta * 1.5) and rng.calls == before_calls, "Integral scaled deltas are exact with no RNG")
	for bound in [-25, 25]:
		a.set_opinion("b", bound)
		var before_calls := rng.calls; var before_signals := signals
		check(not a.change_opinion("b", signi(bound)) and rng.calls == before_calls and signals == before_signals, "Outward clamped no-op consumes no RNG or notifications")
		check(a.change_opinion("b", -signi(bound)) and rng.calls == before_calls + 1, "Moving away from bound still rounds once")
	for delta in [1, -1]:
		a.set_opinion("b", 24 * delta); var before_calls := rng.calls
		check(a.change_opinion("b", delta) and a.get_opinion("b") == 25 * delta and rng.calls == before_calls + 1, "Round before final clamp even when both outcomes reach same bound")
	var skipped_calls := rng.calls
	check(not a.change_opinion("", 1) and not a.change_opinion("a", -1) and rng.calls == skipped_calls, "Invalid targets do not draw or create relationships")
	var empty := Data.new("empty", "Empty", 25); empty.add_trait(Trait.Type.HOTHEADED); empty.opinion_rng = rng
	check(not empty.change_opinion("b", 0) and empty.relationships.is_empty() and rng.calls == skipped_calls, "Zero keeps storage sparse")
	a.set_opinion("b", 25); a.set_opinion("b", 25)
	check(a.get_opinion("b") == 25 and rng.calls == skipped_calls, "Absolute set retains existing semantics and does not scale or draw")
	var state: int = Data.new("seeded", "Seeded", 25).opinion_rng.state
	var same := Data.new("seeded", "Seeded", 25)
	check(same.opinion_rng.state == state, "Same stable resident ID reproduces private RNG stream")
	for type in Trait.Type.values():
		if type in [Trait.Type.HOTHEADED, Trait.Type.CALM]: continue
		var normal := Data.new("normal", "Normal", 25); normal.add_trait(type); normal.opinion_rng = rng
		for delta in [1, -1, 10, -10]:
			normal.set_opinion("b", 0)
			check(normal.change_opinion("b", delta) and normal.get_opinion("b") == delta and rng.calls == skipped_calls, "Every other trait, including SOCIABLE/INTROVERTED, preserves baseline delta")
	for action in Modifiers.Action.values(): check(Modifiers.action_utility(a, action, 5000) == 5000, "No action utility effects")
	check(Modifiers.social_need_rate(a, 12) == 12 and Modifiers.social_need_rate(a, -180) == -180 and Modifiers.selector_candidate_ratio(a) == 0.75 and Modifiers.movement_speed(a, 100) == 100, "No need, selector or movement bonus")
func _callbacks() -> void:
	var a := Data.new("callback", "Callback", 25); a.add_trait(Trait.Type.HOTHEADED)
	var rng := RoundingRng.new(); a.opinion_rng = rng
	var rewrite := func(_id):
		if a.get_opinion("b") == 2: a.set_opinion("b", 20)
	a.relationship_changed.connect(rewrite)
	var snapshot := a.apply_opinion_change("b", 1)
	check(snapshot.before == 0 and snapshot.after == 2 and a.get_opinion("b") == 20 and rng.calls == 1, "Committed snapshot survives callback rewrite without second draw")
	a.relationship_changed.disconnect(rewrite)
	a.set_opinion("b", 0)
	var nested := func(_id):
		if a.get_opinion("b") == 2: a.change_opinion("b", 2)
	a.relationship_changed.connect(nested)
	snapshot = a.apply_opinion_change("b", 1)
	check(snapshot.after == 2 and a.get_opinion("b") == 5 and rng.calls == 2, "Nested distinct change commits once, integer inner operation consumes no draw")
	a.relationship_changed.disconnect(nested)
func _social() -> void:
	for context in Event.Context.values():
		for negative in [false, true]:
			var a := Data.new("a", "A", 25); var b := Data.new("b", "B", 25)
			a.add_trait(Trait.Type.HOTHEADED)
			var rounding := RoundingRng.new(); a.opinion_rng = rounding
			var social := Social.new(); root.add_child(social)
			var reaction := ReactionRng.new(); reaction.rolls = [0, 100] if negative else [100, 0]; social.rng = reaction
			var result = social.resolve(a, b, context)
			var payload: Dictionary = result.confirmed_context().payload
			var sign_value := -1 if negative else 1
			check(result.opinion_delta_1 == sign_value and a.get_opinion("b") == 2 * sign_value and b.get_opinion("a") == -sign_value and rounding.calls == 1, "Conversation/meal/work apply owner modifier once; raw reactions unchanged")
			check(payload.applied_delta_1 == 2 * sign_value and payload.opinion_after_1 == 2 * sign_value and payload.applied_delta_2 == -sign_value, "Social world trigger receives actual applied delta")
			check(reaction.calls == 2, "Rounding never consumes reaction RNG")
			result.confirmed_context(); social._publish_commits(); social._publish_commits()
			check(a.get_opinion("b") == 2 * sign_value and rounding.calls == 1, "Repeated reads/publication cannot reapply opinion or reroll")
			check(is_equal_approx(Modifiers.social_partner_multiplier(a, a.get_opinion("b")), 1.0 + 0.003 * 2 * sign_value), "Partner choice continues to use actual directed opinion")
			a.set_opinion("b", 0); b.set_opinion("a", 0); reaction.calls = 0; reaction.rolls = [50, 50]
			social.resolve(a, b, context)
			check(a.get_opinion("b") == 0 and b.get_opinion("a") == 0 and rounding.calls == 1, "Neutral social reaction never consumes rounding RNG")
			b.add_trait(Trait.Type.HOTHEADED)
			var reverse_rounding := RoundingRng.new(); reverse_rounding.draw = 0.75; b.opinion_rng = reverse_rounding
			reaction.calls = 50; reaction.rolls = [100, 0]
			result = social.resolve(a, b, context)
			check(a.get_opinion("b") == 2 and b.get_opinion("a") == -1 and rounding.calls == 2 and reverse_rounding.calls == 1, "Two HOTHEADED participants use independent once-only draws")
			social.free()
func _generation() -> void:
	var generator := Generator.new(318); var repeat := Generator.new(318); var found := 0
	for index in 1000:
		var person = generator.generate(); var same = repeat.generate()
		check(person.traits.size() == 2 and Trait.compatible(person.traits) and person.traits == same.traits and person.trait_description() == same.trait_description(), "Generation remains compatible, stable and reproducible")
		for type in person.traits + person.liked_traits + person.disliked_traits: check(type in Trait.GENERATION_POOL, "Every generated trait is implemented")
		if person.has_trait(Trait.Type.HOTHEADED):
			found += 1
			check(not person.add_trait(Trait.Type.CALM), "Generated HOTHEADED rejects CALM")
	check(found > 0 and Trait.GENERATION_POOL.size() == 13, "HOTHEADED remains in normal generation alongside CALM")
	var calm := Data.new("calm", "Calm", 25); calm.add_trait(Trait.Type.CALM)
	check(not calm.add_trait(Trait.Type.HOTHEADED), "Reverse conflict preserved")
	check(Trait.description([Trait.Type.HOTHEADED, Trait.Type.PRUDENT]) == "Вспыльчивый прагматик" and Trait.description([Trait.Type.CARING, Trait.Type.HOTHEADED], Trait.GrammaticalGender.FEMININE) == "Заботливая задира", "Both description forms compose with HOTHEADED")
func _statistics() -> void:
	var a := Data.new("stat", "Stat", 25); a.add_trait(Trait.Type.HOTHEADED)
	var repeat := Data.new("stat", "Stat", 25); repeat.add_trait(Trait.Type.HOTHEADED)
	var up := 0; var down := 0; var total := 0
	for index in 20000:
		a.set_opinion("b", 0); repeat.set_opinion("b", 0)
		var delta := 1 if index % 2 == 0 else -1
		a.change_opinion("b", delta); repeat.change_opinion("b", delta)
		var amount := absi(a.get_opinion("b")); total += amount
		check(a.get_opinion("b") == repeat.get_opinion("b"), "Real RNG replays exactly for identical interactions and resident identity")
		if amount == 2: up += 1
		else: down += 1
	check(up > 9500 and up < 10500 and down == 20000 - up, "Fractional rounding is statistically 50/50 with no saved remainder")
	print("Rounding distribution: down=", down, " up=", up, " mean magnitude=", float(total) / 20000)
