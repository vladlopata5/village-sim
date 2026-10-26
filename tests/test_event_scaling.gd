extends SceneTree
const Setup = preload("res://tests/event_test_setup.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const DryRunner = preload("res://scripts/event_dry_run.gd")
class CountingRng extends RefCounted:
	var draws := 0
	func randf() -> float:
		draws += 1
		return 0.75
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var facts := Setup.registry()
	var definitions: Array = []
	for i in 5000: definitions.append(Setup.definition("event_%05d" % i, "group_%d" % (i % 100)))
	var catalog := Catalog.new()
	var started := Time.get_ticks_usec()
	check(catalog.load_json(JSON.stringify({"definitions": definitions}), facts), "Load/validate 5000 JSON definitions")
	var load_usec := Time.get_ticks_usec() - started
	var engine := DryRunner.new(catalog, facts)
	engine.set_chance("group_0", 1)
	var samples: Array = []
	for i in 100:
		started = Time.get_ticks_usec()
		var result: Dictionary = engine.run(Setup.context("group_0", str(i)))
		samples.append(Time.get_ticks_usec() - started)
		check(result.status == "selected" and result.eligible.size() == 50, "All relevant definitions considered")
		check(result.definitions_checked == 50, "Only 1/100 of catalog visited")
	var random := CountingRng.new()
	engine.rng = random
	engine.set_chance("group_0", 0.5)
	var failed: Dictionary = engine.run(Setup.context("group_0", "chance"))
	check(failed.status == "chance_failed" and failed.definitions_checked == 0 and random.draws == 1, "No multiplication of chance by 50 candidates")
	var tiny := Setup.engine({"definitions": [Setup.definition()]}, facts)
	var small_random := CountingRng.new()
	tiny.rng = small_random
	tiny.set_chance("test", 0.5)
	check(tiny.run(Setup.context("test")).status == failed.status and small_random.draws == 1, "Same chance decision for one or thousands of definitions")
	samples.sort()
	print("EVENT_SCALING_JSON ", JSON.stringify({"definitions": 5000, "trigger_buckets": 100, "visited_per_successful_trigger": 50, "samples": samples.size(), "load_usec": load_usec, "dry_run_p50_usec": samples[50], "dry_run_p95_usec": samples[95], "dry_run_max_usec": samples.back()}))
	print("Event scaling: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
