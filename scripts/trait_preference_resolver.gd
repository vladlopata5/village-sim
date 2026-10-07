extends RefCounted
## Directed derived contribution, independent of stored opinion or pair compatibility.
const Balance = preload("res://scripts/balance_config.gd")
static func score(resident: RefCounted, other: RefCounted) -> int:
	if resident == null or other == null or resident.id == other.id: return 0
	var result := 0
	for trait_type in other.traits:
		if resident.likes_trait(trait_type): result += Balance.LIKED_TRAIT_PREFERENCE_VALUE
		elif resident.dislikes_trait(trait_type): result += Balance.DISLIKED_TRAIT_PREFERENCE_VALUE
	return result
