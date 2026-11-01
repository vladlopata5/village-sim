extends "res://tests/test_event_effects.gd"
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
const Grammar = preload("res://scripts/event_russian_grammar.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Generator = preload("res://scripts/resident_generator.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const EventSetup = preload("res://tests/event_test_setup.gd")

func _run() -> void:
	name_cases()
	grammar_tokens()
	variant_choices()
	catalog_errors()
	live_choices()
	atomic_text_errors()
	seeded_choices()
	print("Event grammar: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func name_cases() -> void:
	var samples := [
		["Иван", "masculine", ["Иван", "Ивана", "Ивану", "Ивана", "Иваном", "Иване"]],
		["Анна", "feminine", ["Анна", "Анны", "Анне", "Анну", "Анной", "Анне"]],
		["Дарья", "feminine", ["Дарья", "Дарьи", "Дарье", "Дарью", "Дарьей", "Дарье"]],
		["Фёдор", "masculine", ["Фёдор", "Фёдора", "Фёдору", "Фёдора", "Фёдором", "Фёдоре"]],
		["Марина", "feminine", ["Марина", "Марины", "Марине", "Марину", "Мариной", "Марине"]],
		["Мария", "feminine", ["Мария", "Марии", "Марии", "Марию", "Марией", "Марии"]],
		["Лев", "masculine", ["Лев", "Льва", "Льву", "Льва", "Львом", "Льве"]]
	]
	for row in samples:
		var forms := Grammar.forms(row[0], row[1])
		for index in Grammar.CASES.size():
			var key: String = Grammar.CASES[index]
			check(forms[key] == row[2][index], "Checked name case: " + row[0] + "/" + key)
			for role in ["actor", "other"]:
				var result := TextRenderer.render("{" + role + ".name:" + key + "}", {role: {"name": row[0], "gender": row[1], "name_forms": forms}})
				check(result.ok and result.text == row[2][index], "Rendered name case for " + role + "/" + key)
	var person := Data.new("fictional", "Зарг", 20)
	var explicit_forms := {"nom": "Зарг", "gen": "Зарга", "dat": "Заргу", "acc": "Зарга", "ins": "Заргом", "prep": "Зарге"}
	check(person.set_name_forms(explicit_forms), "Explicit six-case fictional name")
	for key in Grammar.CASES:
		var projected := person.event_text_projection()
		check(TextRenderer.render("{actor.name:" + key + "}", {"actor": projected}).text == explicit_forms[key], "All explicit fictional forms use the common renderer")
	explicit_forms.gen = "mutated"
	check(person.event_text_projection().name_forms.gen == "Зарга", "Name forms are owned, not aliased")
	check(not person.set_name_forms({"nom": "Другой"}) and person.event_text_projection().name_forms.gen == "Зарга", "Bad explicit forms do not change existing data")
	person.name_indeclinable = true
	for key in Grammar.CASES: check(person.event_text_projection().name_forms[key] == "Зарг", "Indeclinable overrides explicit declension")
	person.resident_name = "Кай-Рин"
	person.name_indeclinable = false
	for key in Grammar.CASES: check(person.event_text_projection().name_forms[key] == "Кай-Рин", "Rename clears stale forms; unknown name remains literal")
	check(Grammar.forms("Иван", "masculine", {}, true).ins == "Иван", "Explicit indeclinability of a familiar name")
	check(Grammar.forms("Иван", "feminine").gen == "Иван" and Grammar.forms("Фёдор", "").gen == "Фёдор", "Do not infer missing or different resident gender from name")
	var generator := Generator.new(37)
	for index in 50:
		var generated: RefCounted = generator.generate()
		var projection: Dictionary = generated.event_text_projection()
		check(Grammar.valid_forms(projection.name_forms, generated.resident_name), "Generated residents project all six cases")
		check(projection.gender == ("feminine" if generated.grammatical_gender == Trait.GrammaticalGender.FEMININE else "masculine"), "Projection uses actual resident grammatical gender")

func grammar_tokens() -> void:
	var values := {"actor": {"name": "Анна", "gender": "feminine"}, "other": {"name": "Степан", "gender": "masculine"}}
	check(TextRenderer.render("Лучше бы я не {actor.gender:разговаривал|разговаривала} {other.with}!", values).text == "Лучше бы я не разговаривала со Степаном!", "Complete proposed example")
	for gender in ["masculine", "feminine"]:
		for role in ["actor", "other"]:
			values[role].gender = gender
			check(TextRenderer.render("{" + role + ".gender:он|она}", values).text == ("он" if gender == "masculine" else "она"), "Gender form for each participant")
			for key in Grammar.CASES:
				check(TextRenderer.render("{" + role + ".pronoun:" + key + "}", values).text == Grammar.PRONOUNS[gender][Grammar.CASES.find(key)], "All pronoun cases for " + role + "/" + gender)
	for row in [["Иван", "masculine", "с Иваном", "об Иване"], ["Степан", "masculine", "со Степаном", "о Степане"], ["Лев", "masculine", "со Львом", "о Льве"], ["Анна", "feminine", "с Анной", "об Анне"], ["Елена", "feminine", "с Еленой", "о Елене"], ["Юлия", "feminine", "с Юлией", "о Юлии"], ["Олег", "masculine", "с Олегом", "об Олеге"]]:
		values.other = {"name": row[0], "gender": row[1]}
		check(TextRenderer.render("{other.with} / {other.about}", values).text == row[2] + " / " + row[3], "Prepositions for " + row[0])
	values.actor = {"name": "{other.name}", "gender": "feminine"}
	check(TextRenderer.render("{actor.name:gen}", values).text == "{other.name}", "Inflected inserted name is never scanned as template")
	for invalid in ["{other.name:loc}", "{actor.gender:one}", "{other.with:ins}", "{actor.get_tree()}", "{actor.name", "actor.name}", "{{actor.name}}"]:
		check(not TextRenderer.render(invalid, values).ok, "Malformed template rejected: " + invalid)
	check(not TextRenderer.render("{actor.gender:он|она}", {"actor": {"name": "Анна"}}).ok, "Missing gender is diagnosed, not guessed from name")
	var examples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/event_text_grammar.json"))
	for example in examples:
		var result := TextRenderer.render(example.template, example.values)
		check(result.ok and result.text == example.expected, "Executable authoring example")

func variant_choices() -> void:
	for row in [[0.0, "A"], [0.4999, "A"], [0.5, "B"], [1.0, "B"]]:
		var rng := SequenceRng.new(); rng.values = [row[0]]
		check(TextRenderer.render_choice(["A", "B"], {}, rng).text == row[1] and rng.draws == 1, "Equal defaults, including inclusive upper draw")
	for row in [[0.0, "A"], [0.2499, "A"], [0.25, "B"], [1.0, "B"]]:
		var rng := SequenceRng.new(); rng.values = [row[0]]
		check(TextRenderer.render_choice([{"text": "A", "weight": 1}, {"text": "B", "weight": 3}, {"text": "never", "weight": 0}], {}, rng).text == row[1], "Explicit weights and zero-weight exclusion")
	var single_rng := SequenceRng.new()
	check(TextRenderer.render_choice("single", {}, single_rng).text == "single" and TextRenderer.render_choice(["single"], {}, single_rng).ok and single_rng.draws == 0, "Single text consumes no extra RNG")
	check(not TextRenderer.render_choice(["A", "B"], {}).ok, "No hidden global RNG")
	for invalid in [[], [""], [{"text": "A", "weight": -1}], [{"text": "A", "weight": 0}], [{"text": "A", "weight": INF}], [{"text": "A", "extra": 1}]]:
		check(not TextRenderer.render_choice(invalid, {}, single_rng).ok, "Invalid alternative refused")
	single_rng.values = [NAN]
	check(not TextRenderer.render_choice(["A", "B"], {}, single_rng).ok, "Invalid RNG is a preparation error")
	var stable := RandomNumberGenerator.new(); stable.seed = 9001
	var counts := [0, 0]
	for index in 10000:
		counts[int(TextRenderer.render_choice([{"text": "A", "weight": 1}, {"text": "B", "weight": 3}], {}, stable).text == "B")] += 1
	check(counts[0] > 2300 and counts[0] < 2700, "Fixed-seed weighted sampling near1:3")
	print("Text weight1:3 sample: ", counts)

func catalog_errors() -> void:
	for bad in ["{unknown.name}", "{actor.name:wrong}", "{actor.gender:a|b|c}", "{actor.name", ["ok", "{actor.name:bad}"], [{"text": "A", "weight": 0}]]:
		for channel in ["diary", "chat"]:
			var definition := EventSetup.definition()
			if channel == "diary": definition.text.diary_main = bad
			else: definition.effects = [{"op": "chat.say", "owner": {"role": "actor"}, "chance": 0, "text": bad}]
			var catalog := Catalog.new()
			check(not catalog.load_data({"definitions": [definition]}, EventSetup.registry()) and not catalog.errors.is_empty(), "Catalog rejects malformed text, even unchosen chance0 chat")

func live_content(f: Dictionary) -> Dictionary:
	var data := content(f.service)
	var definition: Dictionary = data.definitions[0]
	data.catalogs = {"partner": {"kind": "resident", "id": "b"}}
	definition.bind = [{"as": "other", "type": "resident_ref", "value": {"catalog": "partner"}}]
	definition.text.diary_main = ["{actor.name} {actor.gender:поговорил|поговорила} {other.with}.", "{actor.name} думает {other.about}."]
	definition.text.diary_secondary = ["Я {other.gender:согласился|согласилась}.", "Радость {other.name:gen}."]
	definition.secondary_diary = {"role": "other", "chance": 1}
	definition.effects = [{"op": "chat.say", "owner": {"role": "actor"}, "chance": 0.5, "text": ["Я {actor.gender:рад|рада}!", "Привет, {other.name}!"]}]
	f.a.grammatical_gender = Trait.GrammaticalGender.FEMININE
	return data

func live_choices() -> void:
	for first in [0.1, 0.9]:
		for second in [0.1, 0.9]:
			var f := fixture(); load_content(f, live_content(f))
			# All consequences are selected first: chat chance, secondary chance,
			# then independent main/secondary/chat text choices.
			f.service.executor.rng.values = [0.1, 0.1, first, 0.9, second]
			var messages: Array = []
			f.service.resident_message.connect(func(id, person_name, text): messages.append([id, person_name, text]))
			check(raise_rank(f).status == "completed", "Real skill trigger executes variant templates")
			check(f.a.diary_entries[0].text == ("Анна поговорила с Борисом." if first < 0.5 else "Анна думает о Борисе."), "Main diary independent choice")
			check(f.b.diary_entries[0].text == "Радость Бориса.", "Additional diary uses same grammar and its own choice")
			check(messages == [["a", "Анна", "Я рада!" if second < 0.5 else "Привет, Борис!"]], "Chat independent of diary, correct speaker")
			var occurrence: Dictionary = f.service.last_occurrence()
			var before: int = f.service.executor.rng.draws
			f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
			f.service.executor.execute({}, occurrence, 636, f.a)
			f.service.executor.publish(occurrence.occurrence_id)
			check(f.service.executor.rng.draws == before and messages.size() == 1 and f.a.diary_entries.size() == 1, "Repeat trigger/execute/publish cannot reroll texts or effects")
			check(raise_rank(f).status == "completed" and f.a.diary_entries.size() == 2, "New independent occurrence remains allowed")
			cleanup(f)
	var world := fixture(); load_content(world, live_content(world))
	world.service.executor.rng.values = [0.9, 0.1, 0.1, 0.1]
	check(raise_rank(world).status == "completed" and world.service.executor.rng.draws == 4, "Failed chat chance does not roll a formulation or affect secondary choice")
	cleanup(world)
	world = fixture(); var data := live_content(world)
	data.definitions[0].effects[0].text = {"ctx": "payload.skill_name"}
	load_content(world, data)
	var expression_messages: Array = []
	world.service.resident_message.connect(func(_id, _name, text): expression_messages.append(text))
	check(raise_rank(world).status == "completed" and expression_messages == ["Собирательство"], "Existing expression-valued chat text remains supported")
	cleanup(world)

func atomic_text_errors() -> void:
	for scenario in ["diary", "secondary", "chat", "rng", "stale_recipient"]:
		var f := fixture(); var data := live_content(f); var definition: Dictionary = data.definitions[0]
		# Validly shaped syntax with a missing scalar fails at prepare, including
		# alternatives not selected by the roll or carrying zero weight.
		if scenario == "diary": definition.text.diary_main = ["OK", {"text": "{payload.missing}", "weight": 0}]
		if scenario == "secondary": definition.text.diary_secondary = ["OK", "{other.missing}"]
		if scenario == "chat": definition.effects[0].text = ["OK", "{payload.missing}"]
		definition.effects.insert(0, {"op": "moodlet.add", "owner": {"role": "actor"}, "definition": "pride", "duration_minutes": 120})
		load_content(f, data)
		f.service.executor.rng.values = [0.0, 0.0, 0.0, NAN] if scenario == "rng" else [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		if scenario == "stale_recipient":
			f.service.executor.rng.on_draw = func(n):
				if n == 6: f.control.unregister_resident("b")
		var notices: Array = []
		f.a.diary_changed.connect(func(): notices.append("diary"))
		f.a.moodlets.changed.connect(func(_id): notices.append("moodlet"))
		f.service.resident_message.connect(func(_id, _name, _text): notices.append("chat"))
		check(raise_rank(f).status != "completed", "Atomic refusal: " + scenario)
		check(f.a.diary_entries.is_empty() and f.b.diary_entries.is_empty() and f.a.moodlets.size() == 0 and notices.is_empty() and f.service.cooldown_history().is_empty(), "No partial writes/notices: " + scenario)
		var draws: int = f.service.executor.rng.draws
		f.a.skill_raised.emit(1, Skill.Type.GATHERING, 0, 1)
		check(f.service.executor.rng.draws == draws, "Failed text cannot be rerolled by duplicate notification")
		cleanup(f)

func seeded_choices() -> void:
	var traces: Array = []
	for repeat in 2:
		var f := fixture(); load_content(f, live_content(f))
		var rng := RandomNumberGenerator.new(); rng.seed = 9122; f.service.executor.rng = rng
		var messages: Array = []
		f.service.resident_message.connect(func(_id, _name, text): messages.append(text))
		for index in 4: raise_rank(f)
		traces.append([f.a.diary_entries.map(func(entry): return entry.text), f.b.diary_entries.map(func(entry): return entry.text), messages.duplicate(), rng.state])
		cleanup(f)
	check(traces[0] == traces[1], "Fixed seed reproduces texts, independent effects and final RNG state")
