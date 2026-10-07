extends RefCounted
## Narrow behavior resolver. Consumers supply base values, not trait_type identities.
## Future sources can compose their contributions here without changing callers.
const Trait = preload("res://scripts/trait_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Utility = preload("res://scripts/action_utility.gd")
enum Action { WORK, EAT, SOCIAL }
static func action_utility(resident: RefCounted, action: Action, base: float) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		match trait_type:
			Trait.Type.SOCIABLE:
				if action == Action.SOCIAL: multiplier *= Balance.SOCIABLE_SOCIAL_UTILITY_MULTIPLIER
			Trait.Type.INTROVERTED:
				if action == Action.SOCIAL: multiplier *= Balance.INTROVERTED_SOCIAL_UTILITY_MULTIPLIER
			Trait.Type.INDUSTRIOUS:
				if action == Action.WORK: multiplier *= Balance.INDUSTRIOUS_WORK_UTILITY_MULTIPLIER
			Trait.Type.LAZY:
				if action == Action.WORK: multiplier *= Balance.LAZY_WORK_UTILITY_MULTIPLIER
			Trait.Type.GLUTTON:
				if action == Action.EAT: multiplier *= Balance.GLUTTON_EAT_UTILITY_MULTIPLIER
	return maxf(base * multiplier, 0.0)
static func eat_threshold(resident: RefCounted, base: int = Balance.EAT_MIN_HUNGER) -> int:
	var addition := 0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.GLUTTON: addition += Balance.GLUTTON_EAT_THRESHOLD_MODIFIER
	return clampi(base + addition, 0, 99)
static func eat_utility(resident: RefCounted) -> float:
	return action_utility(resident, Action.EAT, Utility.eat(resident.hunger, eat_threshold(resident)))
static func movement_speed(resident: RefCounted, base: float) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.RESTLESS: multiplier *= Balance.RESTLESS_MOVEMENT_SPEED_MULTIPLIER
	return maxf(base * multiplier, 0.0)
static func selector_candidate_ratio(resident: RefCounted, base: float = Balance.UTILITY_CANDIDATE_RATIO) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.FOOLISH: multiplier *= Balance.FOOLISH_UTILITY_CANDIDATE_RATIO / Balance.UTILITY_CANDIDATE_RATIO
	return clampf(base * multiplier, 0.0, 1.0)
static func selector_random_exponent(resident: RefCounted, base: float = Balance.UTILITY_RANDOM_EXPONENT) -> float:
	var multiplier := 1.0
	for trait_type in resident.traits:
		if trait_type == Trait.Type.FOOLISH: multiplier *= Balance.FOOLISH_UTILITY_RANDOM_EXPONENT / Balance.UTILITY_RANDOM_EXPONENT
	return maxf(base * multiplier, 0.0)
