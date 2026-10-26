extends SceneTree
const Facts = preload("res://scripts/event_facts.gd")
const Evaluator = preload("res://scripts/event_expression.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var facts := Facts.new()
	var a := {"kind": "resident", "id": "a"}
	check(facts.register_entity(a), "Register stable entity")
	check(facts.register_fact("score", "resident", "number", "none", true), "Register typed nullable fact")
	check(not facts.register_fact("score", "resident", "string"), "Duplicate registration rejected")
	check(not facts.read(a, "score").known, "Missing is Unknown")
	check(facts.set_value(a, "score", null), "Known absence accepted by nullable schema")
	check(facts.read(a, "score").known and facts.read(a, "score").value == null, "Known null differs from Unknown")
	check(not facts.set_value(a, "score", false), "Bool is not numeric zero")
	check(facts.set_value(a, "score", 0), "Numeric zero preserved")
	check(facts.register_fact("tags", "resident", "array"), "Tags registered")
	check(facts.set_value(a, "tags", ["calm"]), "Tags snapshot")
	check(not facts.set_value(a, "tags", [RefCounted.new()]), "Objects excluded from snapshots")
	check(not facts.set_value(a, "tags", range(257)), "Oversized collection rejected, not truncated")
	var snapshot := ["calm"]
	facts.set_value(a, "tags", snapshot)
	snapshot.append("angry")
	var read := facts.read(a, "tags")
	read.value.append("changed")
	check(facts.read(a, "tags").value == ["calm"], "Snapshot input and returned arrays cannot mutate registry")
	var env := {"ctx": {"actor": a, "payload": {"absent": null}}, "role": {"actor": a}, "binding": {}, "param": {}, "catalog": {}, "local": {}}
	var names := {"role": {"actor": "entity"}, "binding": {}, "param": {}, "catalog": {}, "local": {}}
	var expr := Evaluator.new()
	var missing := {"fact": [{"role": "actor"}, "missing"]}
	check(not expr.evaluate({"not": missing}, env, facts).known, "NOT Unknown remains Unknown")
	check(expr.evaluate({"eq": [{"ctx": "payload.absent"}, null]}, env, facts).value, "Known absence can be compared to null")
	check(not expr.evaluate({"eq": [{"ctx": "payload.missing"}, null]}, env, facts).known, "Missing context is not null")
	check(not expr.evaluate({"all": [missing, false]}, env, facts).value, "Unknown AND false is false")
	check(expr.evaluate({"any": [missing, true]}, env, facts).value, "Unknown OR true is true")
	check(not expr.evaluate({"all": [missing, true]}, env, facts).known, "Unknown AND true stays Unknown")
	check(not expr.evaluate({"any": [missing, false]}, env, facts).known, "Unknown OR false stays Unknown")
	check(not expr.evaluate({"not": 0}, env, facts).known, "No numeric truthiness")
	check(expr.evaluate({"all": []}, env, facts).value and not expr.evaluate({"any": []}, env, facts).value, "Empty conjunction/disjunction")
	check(expr.evaluate({"has_tag": [{"role": "actor"}, "calm"]}, env, facts).value, "Tags use registered reader")
	check(expr.evaluate({"sub": [30, 10]}, env, facts).value == 20, "Bounded arithmetic")
	check(not expr.evaluate({"lt": [false, 2]}, env, facts).known, "Dynamic numeric type mismatch fails closed")
	for bad in [{"exec": "evil()"}, {"role": "missing"}, {"binding": "later"}, {"lt": [1, "x"]}, {"all": [1]}, {"fact": [{"role": "actor"}, "missing"]}, {"field": [2, "name"]}]:
		var errors: Array = []
		expr.visits = 0
		expr.validate(bad, names, facts, errors)
		check(not errors.is_empty(), "Invalid expression rejected: " + JSON.stringify(bad))
	var query := {"from": {"list": [1, 2, 3]}, "as": "candidate", "where": {"gte": [{"local": "candidate"}, 2]}}
	check(expr.evaluate({"exists": query}, env, facts).value, "Bounded existential query")
	check(not expr.evaluate({"exists": {"from": {"list": []}, "as": "candidate", "where": true}}, env, facts).value, "Empty query")
	query.where = {"any": [{"eq": [{"local": "candidate"}, 2]}, missing]}
	check(expr.evaluate({"exists": query}, env, facts).value, "Known witness makes exists true despite unknown alternatives")
	env.ctx.large = range(257)
	var oversized := {"exists": {"from": {"ctx": "large"}, "as": "candidate", "where": true}}
	var limited: Dictionary = expr.evaluate({"all": [oversized, false]}, env, facts)
	check(not limited.known and "budget" in limited.reason, "Budget exhaustion cannot masquerade as a normal false condition")
	var node := Node.new()
	check(not Facts.plain(node), "No Godot object property access")
	node.free()
	print("Event expressions: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
