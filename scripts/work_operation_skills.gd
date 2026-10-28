extends RefCounted
## Approved operation data. S2 awards XP only; weights are reserved for S3.
const Skill = preload("res://scripts/skill_type.gd")
const Rules = preload("res://scripts/work_skill_rules.gd")
const Balance = preload("res://scripts/balance_config.gd")
const OPERATIONS := {
	&"construction": [Skill.Type.CONSTRUCTION, 8],
	&"chop_tree": [Skill.Type.FORESTRY, 8],
	&"plant_tree": [Skill.Type.FORESTRY, 4],
	&"mine_stone": [Skill.Type.MINING, 8],
	&"mine_clay": [Skill.Type.MINING, 8],
	&"gather_mushroom": [Skill.Type.GATHERING, 3],
	&"plow": [Skill.Type.FARMING, 1],
	&"sow": [Skill.Type.FARMING, 1],
	&"mow": [Skill.Type.FARMING, 1],
	&"capture_sheep": [Skill.Type.ANIMAL_HUSBANDRY, 8],
	&"shearing": [Skill.Type.ANIMAL_HUSBANDRY, 16],
	&"delivery": [Skill.Type.LOGISTICS, 3],
}
# Primary skill, primary XP, secondary Crafting XP. Fixed per batch, not output.
const RECIPES := {
	&"sawmill_plank": [Skill.Type.WOODWORKING, 3, 1],
	&"cut_stone_brick": [Skill.Type.STONEWORKING, 3, 1],
	&"fire_brick": [Skill.Type.POTTERY, 3, 1],
	&"wool_cloth": [Skill.Type.WEAVING, 6, 2],
	&"wool_clothing": [Skill.Type.TAILORING, 12, 4],
	&"mill_flour": [Skill.Type.MILLING, 6, 2],
	&"fried_mushroom": [Skill.Type.COOKING, 4, 0],
	&"bake_bread": [Skill.Type.COOKING, 4, 0],
	&"thresh_wheat": [Skill.Type.FARMING, 4, 0],
}

static func reward(skill: Skill.Type, amount: int, cap: int = Balance.MAX_SKILL_XP) -> Dictionary:
	return {"skill": skill, "amount": amount, "training_cap": cap}

static func for_operation(operation: StringName) -> Rules:
	if RECIPES.has(operation):
		var row: Array = RECIPES[operation]
		var weights: Array = [{"skill": row[0], "weight_percent": 80 if row[2] > 0 else 100}]
		var rewards: Array = [reward(row[0], row[1])]
		if row[2] > 0:
			weights.append({"skill": Skill.Type.CRAFTING, "weight_percent": 20})
			rewards.append(reward(Skill.Type.CRAFTING, row[2]))
		return Rules.new([], weights, rewards)
	if OPERATIONS.has(operation):
		var row: Array = OPERATIONS[operation]
		var rewards: Array = [reward(row[0], row[1])]
		if operation == &"chop_tree": rewards.append(reward(Skill.Type.WOODWORKING, 2, 1000))
		if operation == &"mine_stone": rewards.append(reward(Skill.Type.STONEWORKING, 2, 1000))
		return Rules.new([], [{"skill": row[0], "weight_percent": 100}], rewards)
	if operation in [&"loading", &"unloading", &"gather_loading"]:
		return Rules.new([], [{"skill": Skill.Type.GATHERING if operation == &"gather_loading" else Skill.Type.LOGISTICS, "weight_percent": 100}])
	# Synthetic/default recipes have no gameplay award. Real recipes are covered
	# explicitly above; this is not a second XP or completion ledger.
	return Rules.new()
