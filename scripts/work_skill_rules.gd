extends RefCounted
## Independent requirements, efficiency inputs and training rewards for an operation.
## XP remains owned by ResidentData; operation owners decide successful completion.
const Skill = preload("res://scripts/skill_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
var requirements: Array
var efficiency_weights: Array
var xp_rewards: Array

func _init(required: Array = [], weights: Array = [], rewards: Array = []) -> void:
	requirements = required.duplicate(true)
	efficiency_weights = weights.duplicate(true)
	xp_rewards = rewards.duplicate(true)

func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	_validate_rows(requirements, ["skill", "min_xp"], "requirements", errors)
	_validate_rows(efficiency_weights, ["skill", "weight_percent"], "efficiency_weights", errors)
	_validate_rows(xp_rewards, ["skill", "amount", "training_cap"], "xp_rewards", errors)
	var weight_sum := 0
	for row in efficiency_weights:
		if row is Dictionary and row.get("weight_percent") is int:
			var weight: int = row.weight_percent
			# Only valid small weights participate, so malformed int64 input cannot overflow.
			if weight > 0 and weight <= 100: weight_sum += weight
	if not efficiency_weights.is_empty() and weight_sum != 100:
		errors.append("Efficiency weights must sum to 100%")
	return errors

func _validate_rows(rows: Array, fields: Array, label: String, errors: Array[String]) -> void:
	var seen: Dictionary = {}
	for row in rows:
		if not row is Dictionary or row.size() != fields.size():
			errors.append(label + ": invalid row")
			continue
		var valid := true
		for field in fields:
			if not row.get(field) is int:
				errors.append(label + ": expected integer " + field)
				valid = false
		if not valid: continue
		if row.skill not in Skill.Type.values() or seen.has(row.skill):
			errors.append(label + ": unknown or duplicate skill")
		seen[row.skill] = true
		if row.has("min_xp") and (row.min_xp < 0 or row.min_xp > Balance.MAX_SKILL_XP):
			errors.append(label + ": invalid minimum XP")
		if row.has("weight_percent") and (row.weight_percent <= 0 or row.weight_percent > 100):
			errors.append(label + ": invalid weight")
		if row.has("amount") and (row.amount <= 0 or row.training_cap < 0):
			errors.append(label + ": invalid XP reward")

func is_valid() -> bool:
	return validation_errors().is_empty()

func can_perform(resident: RefCounted) -> bool:
	if resident == null or not is_valid(): return false
	for row in requirements:
		if resident.get_skill_xp(row.skill) < row.min_xp: return false
	return true

func efficiency_percent(resident: RefCounted) -> float:
	# A malformed rule is an error, not an implicit neutral modifier.
	if resident == null or not is_valid(): return -1.0
	if efficiency_weights.is_empty(): return 100.0
	var percent := 0.0
	for row in efficiency_weights:
		percent += Skill.efficiency_percent(resident.get_skill_xp(row.skill)) * row.weight_percent / 100.0
	return percent

func reward_deltas(resident: RefCounted) -> Dictionary:
	var gains: Dictionary = {}
	if resident == null or not is_valid(): return gains
	for row in xp_rewards:
		var gain := Skill.xp_gain(resident.get_skill_xp(row.skill), row.amount, row.training_cap)
		if gain > 0: gains[row.skill] = gain
	return gains
