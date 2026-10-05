extends RefCounted
## Need values describe state; action utility describes attractiveness of a response.
const Balance = preload("res://scripts/balance_config.gd")
static func eat(hunger: int) -> float:
	if hunger < Balance.EAT_MIN_HUNGER: return 0.0
	var normalized := clampf(float(hunger - Balance.EAT_MIN_HUNGER) / (100 - Balance.EAT_MIN_HUNGER), 0.0, 1.0)
	return Balance.EAT_MAX_UTILITY * pow(normalized, Balance.EAT_UTILITY_EXPONENT)
