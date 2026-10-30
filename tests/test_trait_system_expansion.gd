extends SceneTree
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Generator = preload("res://scripts/resident_generator.gd")
const Factory = preload("res://scripts/resident_factory.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Gender = Trait.GrammaticalGender
var checks := 0
var failures := 0
var signals := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var data := Data.new("character", "Тест", 30)
	data.traits_changed.connect(func(): signals += 1)
	var conflicts := [[Trait.Type.INDUSTRIOUS, Trait.Type.LAZY], [Trait.Type.SOCIABLE, Trait.Type.INTROVERTED], [Trait.Type.FOOLISH, Trait.Type.PRUDENT], [Trait.Type.HOTHEADED, Trait.Type.CALM], [Trait.Type.HASTY, Trait.Type.DELIBERATE]]
	for pair in conflicts:
		for direction in 2:
			data.set_traits([])
			var first: int = pair[direction]; var second: int = pair[1 - direction]
			check(data.add_trait(first), "Both directions admit first trait")
			var before_rejection := signals
			check(not data.add_trait(second) and data.traits == [first] and signals == before_rejection, "Conflict rejects only incoming trait, without signals/removal")
			check(not data.set_traits([first, second]) and data.traits == [first] and signals == before_rejection, "Bulk assignment is atomic")
			check(Trait.conflict(first) == second, "Conflict table is symmetric")
	data.set_traits([Trait.Type.CARING, Trait.Type.FOOLISH])
	var initial := data.traits; var before := signals
	for invalid in [[Trait.Type.LAZY, Trait.Type.LAZY], [-1], [999], ["lazy"], [0.0], [true]]:
		check(not data.set_traits(invalid) and data.traits == initial and signals == before, "Invalid replacement preserves complete old state")
	var copy := data.traits; copy.clear()
	check(data.traits == initial and signals == before, "Snapshot mutation cannot bypass checks or signals")
	var assigned: Array[Trait.Type] = [Trait.Type.HASTY, Trait.Type.DELIBERATE]
	data.traits = assigned
	check(data.traits == initial and signals == before, "Property assignment also rejects conflicts")
	check(data.set_traits(initial) and signals == before, "Repeated assignment is a no-op")
	check(data.trait_description() == "Заботливый балбес", "Two traits use adjective then noun")
	data.grammatical_gender = Gender.FEMININE
	check(data.trait_description() == "Заботливая балбеска" and signals == before + 1, "Gender is stored and notifies presentation once")
	data.grammatical_gender = Gender.FEMININE
	check(signals == before + 1, "Repeated gender does not notify")
	data.set_traits([Trait.Type.INTROVERTED, Trait.Type.PRUDENT])
	check(data.trait_description() == "Замкнутая прагматичка", "Feminine compound")
	data.grammatical_gender = Gender.MASCULINE
	check(data.trait_description() == "Замкнутый прагматик", "Approved masculine example")
	data.set_traits([Trait.Type.PRUDENT, Trait.Type.INTROVERTED])
	check(data.trait_description() == "Рассудительный одиночка", "Explicit order determines wording")
	check(Trait.description([]) == "" and Trait.description([Trait.Type.FOOLISH]) == "Чудаковатый", "Empty and single-trait descriptions")
	check(Trait.description([Trait.Type.CARING, Trait.Type.SOCIABLE, Trait.Type.GLUTTON]) == "Заботливый общительный обжора", "Explicit lists longer than two retain every trait")
	var expected := [["Трудолюбивый", "Трудяга"], ["Ленивый", "Лентяй"], ["Общительный", "Болтун"], ["Замкнутый", "Одиночка"], ["Прожорливый", "Обжора"], ["Непоседливый", "Непоседа"], ["Чудаковатый", "Балбес"], ["Рассудительный", "Прагматик"], ["Заботливый", "Добряк"], ["Вспыльчивый", "Задира"], ["Невозмутимый", "Флегматик"], ["Торопливый", "Торопыга"], ["Неторопливый", "Копуша"]]
	var ordered := [Trait.Type.INDUSTRIOUS, Trait.Type.LAZY, Trait.Type.SOCIABLE, Trait.Type.INTROVERTED, Trait.Type.GLUTTON, Trait.Type.RESTLESS, Trait.Type.FOOLISH, Trait.Type.PRUDENT, Trait.Type.CARING, Trait.Type.HOTHEADED, Trait.Type.CALM, Trait.Type.HASTY, Trait.Type.DELIBERATE]
	for index in ordered.size():
		var type: int = ordered[index]
		check(Trait.adjective(type) == expected[index][0] and Trait.noun(type) == expected[index][1], "Every approved masculine form")
		check(not Trait.adjective(type, Gender.FEMININE).is_empty() and not Trait.noun(type, Gender.FEMININE).is_empty() and not Trait.display_name(type).is_empty(), "All catalog entries have feminine forms and names")
		if type not in Trait.GENERATION_POOL:
			data.set_traits([type])
			for action in Modifiers.Action.values(): check(Modifiers.action_utility(data, action, 1000) == 1000, "Prepared traits introduce no action effects")
			check(Modifiers.movement_speed(data, 100) == 100 and Modifiers.social_need_rate(data, -180) == -180 and Modifiers.leisure_need_rate(data, 12, true) == 12 and Modifiers.leisure_need_rate(data, -180, false) == -180 and Modifiers.eat_threshold(data) == 30 and Modifiers.selector_candidate_ratio(data) == 0.75 and Modifiers.selector_random_exponent(data) == 2, "Prepared traits have no need/speed/randomness effects")
	var a := Generator.new(4321); var b := Generator.new(4321)
	var seen: Array = []
	for index in 1000:
		var person = a.generate(); var repeat = b.generate()
		check(person.traits.size() == 2 and Trait.compatible(person.traits), "Generation retains exactly two compatible traits")
		for type in person.traits + person.liked_traits + person.disliked_traits:
			check(type in Trait.GENERATION_POOL, "Pending traits excluded from both random traits and preferences")
			if not seen.has(type): seen.append(type)
		check(person.traits == repeat.traits and person.grammatical_gender == repeat.grammatical_gender and person.trait_description() == repeat.trait_description(), "Seed reproduces stored order and description")
		var description: String = person.trait_description(); var snapshot: Array = person.traits
		for read in 3: check(person.trait_description() == description and person.traits == snapshot, "Reading description never shuffles")
	check(seen.size() == 12 and Trait.Type.SOCIABLE == 0 and Trait.Type.FOOLISH == 6, "Twelve implemented traits are generated, IDs stable")
	for name in Generator.NAMES:
		var person = Generator.new(42).generate(name)
		check(person.grammatical_gender == Generator.NAME_GENDERS[Generator.NAMES.find(name)], "Built-in names carry explicit grammatical metadata")
	check(Generator.new(42).generate("Произвольное имя", Gender.FEMININE).grammatical_gender == Gender.FEMININE, "Custom names accept explicit gender")
	check(Generator.new(42).generate("Произвольное имя").grammatical_gender == Gender.MASCULINE, "Unknown names have documented fallback without guessing")
	check(Factory.create("invalid", "Invalid", 20, Profession.Type.NONE, [Trait.Type.FOOLISH, Trait.Type.PRUDENT], 0, 0, 50, &"", &"") == null, "Factory rejects conflicting list instead of silently truncating")
	_rng_sequence()
	_ui()
	print("Trait expansion: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
func _rng_sequence() -> void:
	# Same draw order, with the approved twelve-trait pool (stable, non-contiguous IDs).
	var rng := RandomNumberGenerator.new(); rng.seed = 123
	var preference_rng := RandomNumberGenerator.new(); preference_rng.seed = 123 ^ 0x50524546
	var generator := Generator.new(123)
	for index in 100:
		var name: String = Generator.NAMES[rng.randi_range(0, 4)]
		var pool: Array = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12]
		var first: int = pool[rng.randi_range(0, 11)]
		pool.erase(first)
		var conflicts := {0: 1, 1: 0, 2: 3, 3: 2, 6: 7, 7: 6, 9: 10, 10: 9, 11: 12, 12: 11}
		pool.erase(conflicts.get(first, -1))
		var pair: Array = [first, pool[rng.randi_range(0, pool.size() - 1)]]
		var preference_pool: Array = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12]
		var liked: Array = []; var disliked: Array = []
		for count in 2: liked.append(preference_pool.pop_at(preference_rng.randi_range(0, preference_pool.size() - 1)))
		disliked.append(preference_pool.pop_at(preference_rng.randi_range(0, preference_pool.size() - 1)))
		var expected := [name, rng.randi_range(18, 65), rng.randi_range(10, 30), rng.randi_range(5, 35), rng.randi_range(45, 80)]
		var person = generator.generate()
		check([person.resident_name, person.age, person.hunger, person.fatigue, person.mood] == expected and person.traits == pair and person.liked_traits == liked and person.disliked_traits == disliked, "Approved pool changes preserve reproducible draw order without extra draws")
func _ui() -> void:
	var world = preload("res://tests/behavior_test_setup.gd").make_scene(self)
	var person = world.residents[1]; var other = world.residents[3]
	person.set_traits([Trait.Type.CARING, Trait.Type.FOOLISH])
	person.grammatical_gender = Gender.MASCULINE
	world.resident_selection.select(person)
	var card = world.resident_card_view()
	var original: String = card.traits_label.text
	check(original.begins_with("Характер: Заботливый балбес") and original.contains("• Заботливый") and original.contains("• Балбес"), "Existing card shows compound and full trait list")
	for repeat in 5:
		world.resident_selection.select(other); world.resident_selection.select(person)
		check(card.traits_label.text == original, "Selection changes preserve description order")
	paused = true
	person.grammatical_gender = Gender.FEMININE
	check(card.traits_label.text.begins_with("Характер: Заботливая балбеска"), "Gender refreshes selected card even on pause")
	check(not person.set_traits([Trait.Type.CALM, Trait.Type.HOTHEADED]) and card.traits_label.text.begins_with("Характер: Заботливая балбеска"), "Rejected replacement does not change UI")
	world.resident_selection.select(other)
	var other_text: String = card.traits_label.text
	person.grammatical_gender = Gender.MASCULINE
	check(card.traits_label.text == other_text, "Previous resident has no stale card subscription")
	paused = false
	world.free()
