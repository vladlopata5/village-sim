extends RefCounted
## Utility is supplied by the caller; this layer only selects among available actions.
const Balance = preload("res://scripts/balance_config.gd")
const Choice = preload("res://scripts/weighted_choice.gd")
static func evaluate(actions: Array, candidate_ratio: float = Balance.UTILITY_CANDIDATE_RATIO, random_exponent: float = Balance.UTILITY_RANDOM_EXPONENT) -> Dictionary:
	var maximum := 0.0
	for action in actions: maximum = maxf(maximum, action.priority)
	var threshold := maximum * clampf(candidate_ratio, 0.0, 1.0)
	var candidates: Array = []
	var discarded: Array = []
	for action in actions:
		var row: Dictionary = action.duplicate()
		if row.priority < threshold:
			discarded.append(row)
			continue
		row.shifted = maxf(float(row.priority) - threshold, 1.0)
		row.random_weight = pow(row.shifted, maxf(random_exponent, 0.0))
		row.option_weight = row.random_weight
		candidates.append(row)
	return {"candidate_ratio": clampf(candidate_ratio, 0.0, 1.0), "random_exponent": maxf(random_exponent, 0.0), "max_priority": maximum, "threshold": threshold, "candidates": candidates, "discarded": discarded}
static func pick(report: Dictionary, rng: RandomNumberGenerator):
	return Choice.pick(report.candidates, rng)
static func debug_text(resident_name: String, report: Dictionary, selected: String, unavailable: Array) -> String:
	var lines: Array[String] = ["%s decision: max_priority=%.2f threshold=%.2f" % [resident_name, report.max_priority, report.threshold], "selector ratio=%.2f exponent=%.2f" % [report.candidate_ratio, report.random_exponent]]
	for row in report.candidates:
		lines.append("%s priority=%.2f shifted=%.2f random_weight=%.2f" % [row.id, row.priority, row.shifted, row.random_weight])
	for row in report.discarded: lines.append("%s priority=%.2f discarded=below_cutoff" % [row.id, row.priority])
	for id in unavailable: lines.append("%s discarded=unavailable_or_below_need_threshold" % id)
	lines.append("selected=%s" % selected)
	return "\n".join(lines)
