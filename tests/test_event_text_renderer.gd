extends SceneTree
const TextRenderer = preload("res://scripts/event_text_renderer.gd")
const Facts = preload("res://scripts/event_facts.gd")
const Setup = preload("res://tests/event_test_setup.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var values := {"actor": {"name": "Анна"}, "other": {"name": "Борис"}, "payload": {"amount": 0, "flag": false}, "facet": {"label": "новому жилью"}}
	check(TextRenderer.render("{actor.name}: {payload.amount}, {payload.flag} — {facet.label}", values).text == "Анна: 0, false — новому жилью", "Allowed names, scalar context and bound record fields")
	check(TextRenderer.render("{other.name} / {actor.name}", values).text == "Борис / Анна", "Participant-specific template")
	check(TextRenderer.render("", values).ok and TextRenderer.render("", values).text == "", "Empty optional channel remains empty")
	for template in ["{missing.name}", "{actor.unknown}", "{actor}"]:
		var result := TextRenderer.render(template, values)
		check(not result.ok and result.text.is_empty() and not result.errors.is_empty(), "Unknown or composite value rejected: " + template)
	values.payload.absent = null
	check(not TextRenderer.render("{payload.absent}", values).ok, "Known null is not an invented display name/zero")
	values.actor.name = "{other.name} %B%"
	check(TextRenderer.render("{actor.name}", values).text == "{other.name} %B%", "Inserted name is literal, never another template")
	check(TextRenderer.render("{actor.get_tree()} %A%", values).text == "{actor.get_tree()} %A%", "Text outside the permitted placeholder grammar is literal, not code")
	var node := Node.new()
	check(not TextRenderer.render("{actor.name}", {"actor": node}).ok, "Live Godot objects are not read")
	node.free()
	var data := Setup.enabled_data()
	var labels := {}
	for id in ["a", "b", "c"]: labels[Facts.ref_key(Setup.person(id))] = {"name": {"a": "Анна", "b": "Борис", "c": "Степан"}[id]}
	labels[Facts.ref_key({"kind": "building", "id": "kitchen"})] = {"name": "Кухня"}
	for definition in data.definitions:
		var facts := Setup.registry()
		facts.set_value(Setup.person("b"), "equipment.clothing.appearance_rank", 3)
		facts.set_value(Setup.person("a"), "memories.active", [{"id": "memory-1", "target": Setup.person("c"), "tags": ["negative"]}])
		var runner := Setup.engine({"catalogs": data.catalogs, "definitions": [definition]}, facts)
		var context := Setup.context(definition.trigger)
		var selection: Dictionary = runner.run(context)
		check(selection.status == "selected", "R2-B1 selects example: " + definition.id)
		var before := JSON.stringify([selection, context, labels])
		var rng_state: int = runner.rng.state
		var rendered := TextRenderer.render_event(selection, context, labels)
		check(rendered.ok and not rendered.texts.feed.is_empty(), "Selected R2-B1 definition renders: " + definition.id)
		check(not "{" in rendered.texts.feed, "All valid feed placeholders resolved")
		check(JSON.stringify([selection, context, labels]) == before and runner.rng.state == rng_state, "Renderer changes neither inputs nor RNG")
		check(TextRenderer.render_event(selection, context, labels) == rendered, "Rendering can repeat without event application")
		if definition.id == "social.kitchen_encounter":
			check(rendered.texts.diary_main == "Борис работает на кухне, пока Анна ест.", "Diary text follows resolved worker, not initiating actor")
		if definition.id == "social.complaint":
			check(rendered.texts.feed == "Анна пожаловался Борис на Степан.", "Third-party reference uses explicit projection")
			check(not TextRenderer.render_event(selection, context).ok, "Missing label is a diagnostic, not a guessed resident")
		# Large diagnostic outputs must not be scanned or rejected as world data.
		selection.eligible = range(1000)
		check(TextRenderer.render_event(selection, context, labels).ok, "Only selected text inputs are evaluated, not the whole eligibility list")
	check(not TextRenderer.render_event({"status": "no_match"}, {}).ok, "No selection means no text event")
	var invalid_projection := {Facts.ref_key(Setup.person("a")): {"id": "spoofed"}}
	var sample := {"status": "selected", "roles": {"actor": Setup.person("a")}, "bindings": {}, "selected": {"text": {"feed": "{actor.name}"}}}
	check(not TextRenderer.render_event(sample, {}, invalid_projection).ok, "Projection cannot replace stable identity")
	sample.selected.text = {"feed": "{actor.name}", "diary_main": "Main: {actor.name}", "diary_secondary": "Other: {payload.name}"}
	var channels := TextRenderer.render_event(sample, {"payload": {"name": "Борис"}}, labels)
	check(channels.ok and channels.texts.diary_main == "Main: Анна" and channels.texts.diary_secondary == "Other: Борис", "Feed and independent participant text channels are preserved")
	print("Event text renderer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
