extends RefCounted
const Selector = preload("res://scripts/utility_selector.gd")
static func for_action(actions: Array, id: String) -> int:
	var report := Selector.evaluate(actions)
	var rng := RandomNumberGenerator.new()
	for candidate in range(10000):
		rng.seed = candidate
		var selected = Selector.pick(report, rng)
		if selected != null and selected.id == id: return candidate
	assert(false, "Requested test action is not a candidate")
	return -1
