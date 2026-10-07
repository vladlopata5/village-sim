extends RefCounted
## Need values describe state; action utility describes attractiveness of a response.
const Balance = preload("res://scripts/balance_config.gd")
static func eat(hunger: int, minimum_hunger: int = Balance.EAT_MIN_HUNGER) -> float:
	if hunger < minimum_hunger: return 0.0
	var normalized := clampf(float(hunger - minimum_hunger) / (100 - minimum_hunger), 0.0, 1.0)
	return Balance.EAT_MAX_UTILITY * pow(normalized, Balance.EAT_UTILITY_EXPONENT)
