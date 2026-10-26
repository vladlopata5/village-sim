extends SceneTree
const Setup = preload("res://tests/event_test_setup.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const DryRunner = preload("res://scripts/event_dry_run.gd")
const Facts = preload("res://scripts/event_facts.gd")
class FixedRng extends RefCounted:
	var values: Array = [0.0, 0.0]
	var draws := 0
	func randf() -> float:
		var value: float = values[draws % values.size()]
		draws += 1
		return value
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var facts := Setup.registry()
	var catalog := Catalog.new()
	check(catalog.load_file("res://tests/fixtures/event_examples.json", facts), "Load JSON fixture: " + str(catalog.errors))
	check(catalog.definition_count == 6, "Five B0 rules plus separate construction example")
	var disabled := DryRunner.new(catalog, facts)
	disabled.set_chance("interaction.started", 1)
	check(disabled.run(Setup.context("interaction.started")).status == "no_match", "Disabled examples do not select")
	var data := Setup.enabled_data()
	check(catalog.load_data(data, facts), "Validated active copies of test-only definitions")
	check(not catalog.load_json("{ broken", facts) and catalog.definition_count == 6, "Bad JSON preserves last valid catalog")
	var bad: Dictionary
	for field in ["id", "schema_version", "revision", "enabled", "weight", "main_role"]:
		bad = data.duplicate(true)
		bad.definitions[0].erase(field)
		check(not catalog.load_data(bad, facts), "Missing required field rejected: " + field)
	for condition in [{"execute": "evil"}, {"role": "ghost"}, {"binding": "later"}, {"lt": [true, 4]}, {"not": "text"}, {"fact": [{"role": "actor"}, "unregistered"]}]:
		bad = data.duplicate(true)
		bad.definitions[0].when = condition
		check(not catalog.load_data(bad, facts), "Invalid AST rejected: " + JSON.stringify(condition))
	bad = data.duplicate(true)
	bad.definitions[0].bind[0].select.where = {"eq": [{"binding": "facet"}, 2]}
	check(not catalog.load_data(bad, facts), "Forward/self binding rejected at load")
	bad = data.duplicate(true)
	bad.definitions[0].weight = -1
	check(not catalog.load_data(bad, facts), "Negative weight rejected")
	bad = data.duplicate(true)
	bad.definitions[0].effects[0].chance = 1.1
	check(not catalog.load_data(bad, facts), "Invalid future effect probability rejected")
	bad = data.duplicate(true)
	bad.definitions[0].text.feed = "{unknown.name}"
	check(not catalog.load_data(bad, facts), "Unknown narrative reference rejected")
	bad = data.duplicate(true)
	bad.definitions[0].text.erase("diary_main")
	check(not catalog.load_data(bad, facts), "Future mandatory resident diary cannot be omitted")
	bad = data.duplicate(true)
	bad.definitions[0].limits = {"max_per_root": 1}
	check(not catalog.load_data(bad, facts), "Old event-count limits not silently enforced")
	bad = data.duplicate(true)
	bad.definitions[0].id = bad.definitions[1].id
	check(not catalog.load_data(bad, facts), "Duplicate IDs rejected")
	for malformed in [{"catalogs": [], "definitions": []}, {"definitions": [null]}, {"definitions": "wrong"}]:
		check(not catalog.load_data(malformed, facts), "Malformed root fails without a runtime exception")
	bad = {"definitions": [Setup.definition()]}
	bad.definitions[0].roles.actor = "wrong"
	check(not catalog.load_data(bad, facts), "Malformed main-role declaration rejected safely")
	bad = {"definitions": [Setup.definition()]}
	bad.definitions[0].effects = [{"op": "opinion.add", "owner": {"invoke": "evil"}, "target": {"role": "actor"}, "amount": 1}]
	check(not catalog.load_data(bad, facts), "Unknown expression in effect owner rejected even though effects are inert")
	var a := Setup.person("a")
	var b := Setup.person("b")
	facts.set_value(b, "equipment.clothing.appearance_rank", 3)
	var engine := Setup.engine(data, facts)
	var random := FixedRng.new()
	engine.rng = random
	var result: Dictionary = engine.run(Setup.context("interaction.started", "clothing"), {}, true)
	check(result.status == "selected" and result.selected.id == "social.envy_advantage", "Clothing envy selected")
	check(result.bindings.facet.id == "clothing" and result.main == a, "Frozen clothing facet/main participant")
	check(random.draws == 2, "One chance draw and one weighted draw, not one per definition")
	var repeat: Dictionary = engine.run(Setup.context("interaction.started", "clothing"), {}, true)
	check(repeat.duplicate and repeat.selected.id == result.selected.id and random.draws == 2, "Same occurrence returns cached result without another chance")
	result.bindings.facet.id = "tampered"
	check(engine.run(Setup.context("interaction.started", "clothing")).bindings.facet.id == "clothing", "Caller cannot mutate cached result")
	facts.set_value(b, "equipment.clothing.appearance_rank", 0)
	facts.set_value(b, "housing.status_rank", 1)
	facts.set_value(b, "housing.assigned_minute", 990)
	result = engine.run(Setup.context("interaction.started", "housing"))
	check(result.selected.id == "social.envy_advantage" and result.bindings.facet.id == "housing", "Same envy rule selects new-home advantage")
	var history := {result.cooldown_key: 999}
	var history_before := history.duplicate(true)
	check(engine.run(Setup.context("interaction.started", "cooldown"), history, true).status == "no_match", "Read-only history excludes cooling definition")
	check(history == history_before, "Dry-run does not record selected events in history")
	var changed_revision := data.duplicate(true)
	changed_revision.definitions[0].revision = 2
	var revised := Setup.engine(changed_revision, facts)
	check(revised.run(Setup.context("interaction.started", "revision"), history).status == "no_match", "Revision does not reset cooldown")
	var boundary := Setup.context("interaction.started", "boundary")
	boundary.minute = 1239
	facts.set_value(b, "housing.assigned_minute", 1230)
	check(engine.run(boundary, history).status == "selected", "Cooldown exact expiry is allowed")
	facts.set_value(b, "housing.assigned_minute", 990)
	result = engine.run(Setup.context("interaction.ended", "mentor"))
	check(result.selected.id == "social.mentoring" and result.bindings.skill == "construction", "Mentoring binds actual profession skill")
	check(facts.read(a, "skill.level", "construction").value == 1, "XP effect is never executed")
	var cancelled := Setup.context("interaction.ended", "cancelled")
	cancelled.payload.reason = "cancelled"
	check(engine.run(cancelled).status == "no_match", "Cancelled conversation cannot teach in example")
	var grievance := {"id": "m1", "kind": "broken_promise", "target": Setup.person("c"), "tags": ["negative"]}
	facts.set_value(a, "memories.active", [grievance])
	result = engine.run(Setup.context("interaction.started", "complaint"), history)
	check(result.selected.id == "social.complaint" and result.bindings.subject.id == "c", "Complaint binds third-party target from memory")
	check(not result.roles.has("c") and result.main == a, "Third party is a reference, not another participant")
	grievance.tags.append("hearsay")
	facts.set_value(a, "memories.active", [grievance])
	check(engine.run(Setup.context("interaction.started", "hearsay"), history).status == "no_match", "Example excludes gossip of gossip")
	result = engine.run(Setup.context("skill.raised", "skill"))
	check(result.selected.id == "personal.skill_milestone" and result.roles.size() == 1, "Unary skill event needs no partner")
	check(facts.read(a, "memories.active").value.size() == 1, "Memory/moodlet descriptions are inert")
	result = engine.run(Setup.context("action.started", "kitchen"))
	check(result.selected.id == "social.kitchen_encounter" and result.main == b, "Event main participant can differ from trigger actor")
	check(result.bindings.worker == b and result.bindings.diner == a, "Kitchen binds both actual activities")
	result = engine.run(Setup.context("construction.completed", "building"))
	check(result.selected.id == "building.completion" and result.main.kind == "building", "Building completion works without an invented resident")
	var invalid := Setup.context("construction.completed", "invalid")
	invalid.location = {"kind": "building", "id": "removed"}
	check(engine.run(invalid, {}, true).status == "no_match", "Invalid role rejected")
	var simple := Setup.definition()
	var second := simple.duplicate(true)
	second.id = "second"
	second.weight = 3
	var weighted := Setup.engine({"definitions": [simple, second]}, facts)
	random = FixedRng.new()
	random.values = [0.0, 0.1]
	weighted.rng = random
	check(weighted.run(Setup.context("test", "low")).selected.id == "second", "Stable ID ordering used by weighted choice")
	random.values = [0.0, 0.9]
	check(weighted.run(Setup.context("test", "high")).selected.id == "test", "Different weights affect selection interval")
	second.weight = 0
	weighted = Setup.engine({"definitions": [simple, second]}, facts)
	check(weighted.run(Setup.context("test")).selected.id == "test", "Zero weight never selected")
	simple.weight = 0
	weighted = Setup.engine({"definitions": [simple, second]}, facts)
	check(weighted.run(Setup.context("test")).status == "no_match", "All-zero weights are safe")
	var left := Setup.engine({"definitions": [Setup.definition("a"), Setup.definition("b")]}, facts)
	var right := Setup.engine({"definitions": [Setup.definition("b"), Setup.definition("a")]}, facts)
	left.rng.seed = 12345
	right.rng.seed = 12345
	var trace: Array = []
	for i in 30:
		var event_context := Setup.context("test", str(i))
		var first: Dictionary = left.run(event_context)
		var next: Dictionary = right.run(event_context)
		check(first.selected.id == next.selected.id, "Seed/catalog-order independent deterministic trace")
		trace.append(first.selected.id)
	check("a" in trace and "b" in trace, "Both positive-weight definitions are reachable")
	random = FixedRng.new()
	random.values = [0.8]
	left.rng = random
	left.set_chance("test", 0.5)
	check(left.run(Setup.context("test", "failed")).status == "chance_failed" and random.draws == 1, "Failed opportunity chance uses one draw")
	check(left.run(Setup.context("test", "failed")).duplicate and random.draws == 1, "Failed chance is also deduplicated")
	var extended := Setup.definition()
	extended.effects = [{"op": "opinion.add", "owner": {"role": "actor"}, "target": {"role": "actor"}, "amount": 1, "chance": 0}]
	extended.exclusive_groups = [{"id": "reaction", "options": [{"op": "skill.add_xp", "owner": {"role": "actor"}, "skill": "construction", "amount": 1, "chance": 0.5, "weight": 1}]}]
	var future := Setup.engine({"definitions": [extended]}, facts)
	random = FixedRng.new()
	future.rng = random
	result = future.run(Setup.context("test"))
	check(result.status == "selected" and result.selected.effects[0].chance == 0 and result.selected.exclusive_groups.size() == 1, "Future independent/group effects preserved as descriptions")
	check(random.draws == 2, "No effect, group or diary RNG is consumed by dry-run")
	var original_context := Setup.context("test", "untouched")
	var before_context := original_context.duplicate(true)
	future.run(original_context, history)
	check(original_context == before_context and history == history_before, "Input context and cooldown history remain unchanged")
	var snapshot: Variant = facts.read(a, "skill.level", "construction").value
	check(snapshot == 1, "No mechanical consequence after repeated selected examples")
	var unknown := Setup.definition()
	unknown.when = {"not": {"eq": [{"ctx": "payload.unknown"}, 0]}}
	var unknown_runner := Setup.engine({"definitions": [unknown]}, facts)
	result = unknown_runner.run(Setup.context("test"), {}, true)
	check(result.status == "no_match" and "unknown" in result.rejected[0].reason, "Unknown does not become eligible under NOT; diagnostic reason retained")
	print("Event engine: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
