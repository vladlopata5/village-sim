extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Trait = preload("res://scripts/trait_type.gd").Type
const Need = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Clock = preload("res://scripts/game_time.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func resident(trait_type: int = -1) -> Data:
	var data := Data.new("test", "Тест", 30)
	if trait_type >= 0: data.add_trait(trait_type)
	for need in data.needs.values(): need.value = 50
	return data
func run() -> void:
	for variant in [[-1, 1.0, 1.0], [Trait.SOCIABLE, 1.25, 0.75], [Trait.INTROVERTED, 0.75, 1.25]]:
		var data := resident(variant[0])
		check(is_equal_approx(Modifiers.social_need_rate(data, 60), 60 * variant[1]), "Depletion coefficient")
		check(is_equal_approx(Modifiers.social_need_rate(data, -180), -180 * variant[2]), "Recovery coefficient")
		check(Modifiers.social_need_rate(data, 0) == 0, "Zero rate stays zero")
		check(Modifiers.action_utility(data, Modifiers.Action.SOCIAL, 100) == 100 * variant[1], "Existing SOCIAL utility is unchanged")
		for activity in Dynamics.SOCIAL_RATES:
			data = resident(variant[0]); data.activity = activity
			var neutral := resident(); neutral.activity = activity
			var activity_dynamics := Dynamics.new(); var baseline := Dynamics.new()
			activity_dynamics._data = data; baseline._data = neutral
			for minute in 120:
				activity_dynamics._on_minute_changed(minute); baseline._on_minute_changed(minute)
			var base: float = Dynamics.SOCIAL_RATES[activity]
			var rate: float = base * (variant[2] if base < 0 else variant[1])
			if activity == Activity.SLEEPING: rate *= 0.2
			var units: float = 60 if base < 0 else 300
			var delta := int(rate * 120 / units)
			check(data.get_need(Need.SOCIAL).value == clampi(50 + delta, 0, 100), "Every activity applies the coefficient exactly once, including sleep")
			if 50 + delta > 0 and 50 + delta < 100:
				var denominator := 300000
				var scaled := roundi(rate * (5000 if base < 0 else 1000))
				check(activity_dynamics._fractions[Need.SOCIAL] == scaled * 120 - delta * denominator, "Small growth and recovery fractions remain exact")
			for other in [Need.HUNGER, Need.FATIGUE, Need.LEISURE]:
				check(data.get_need(other).value == neutral.get_need(other).value and activity_dynamics._fractions[other] == baseline._fractions[other], "Other needs and their fractional progress are unchanged")
			activity_dynamics.free(); baseline.free()
		# Four talking minutes are exactly 9 / 12 / 15 restored points.
		data = resident(variant[0]); data.activity = Activity.TALKING
		var dynamics := Dynamics.new(); dynamics._data = data
		for minute in 4: dynamics._on_minute_changed(minute)
		check(data.get_need(Need.SOCIAL).value == 50 - int(12 * variant[2]), "No integer truncation of fractional recovery")
		check(dynamics._fractions[Need.SOCIAL] == 0, "Exact recovery remainder")
		for minute in 100: dynamics._on_minute_changed(minute)
		check(data.get_need(Need.SOCIAL).value == 0 and dynamics._fractions[Need.SOCIAL] == 0, "Recovery clamps and clears boundary remainder")
		data.activity = Activity.WORKING
		for minute in 2000: dynamics._on_minute_changed(minute)
		check(data.get_need(Need.SOCIAL).value == 100 and dynamics._fractions[Need.SOCIAL] == 0, "Depletion clamps and clears boundary remainder")
		dynamics.free()
		for speed in [1, 20]:
			for frames in [1, 120]:
				data = resident(variant[0]); data.activity = Activity.WORKING
				var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.set_speed(speed)
				dynamics = Dynamics.new(); root.add_child(dynamics); dynamics.setup(clock, data)
				for frame in frames: clock.advance(120.0 / speed / frames)
				check(data.get_need(Need.SOCIAL).value == 50 + int(24 * variant[1]), "Social growth independent of FPS and simulation speed")
				dynamics.free(); clock.free()
	# A non-social trait must not affect either social rate.
	var unrelated := resident(Trait.INDUSTRIOUS)
	check(Modifiers.social_need_rate(unrelated, 60) == 60 and Modifiers.social_need_rate(unrelated, -180) == -180, "Unrelated traits preserve base rates")
	var changing := resident(Trait.SOCIABLE); changing.activity = Activity.WORKING
	var changing_dynamics := Dynamics.new(); changing_dynamics._data = changing
	for minute in 2: changing_dynamics._on_minute_changed(minute)
	check(changing.get_need(Need.SOCIAL).value == 50 and changing_dynamics._fractions[Need.SOCIAL] == 150000, "Half point retains fractional depletion")
	changing.remove_trait(Trait.SOCIABLE); changing.add_trait(Trait.INTROVERTED)
	for minute in 4: changing_dynamics._on_minute_changed(minute)
	check(changing.get_need(Need.SOCIAL).value == 51 and changing_dynamics._fractions[Need.SOCIAL] == 30000, "Trait changes affect subsequent ticks without resetting previous fractions")
	changing_dynamics.free()
	print("Social trait needs: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
