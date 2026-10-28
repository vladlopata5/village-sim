extends RefCounted
## Skills describe accumulated experience, independently of assigned profession.
enum Type {
	GATHERING, CONSTRUCTION, LOGISTICS, FORESTRY, MINING, FARMING,
	ANIMAL_HUSBANDRY, WOODWORKING, STONEWORKING, POTTERY, WEAVING,
	TAILORING, MILLING, COOKING, CRAFTING
}
enum Rank { PROFANE, NOVICE, AMATEUR, EXPERIENCED, MASTER }
const Balance = preload("res://scripts/balance_config.gd")

static func display_name(skill: Type) -> String:
	match skill:
		Type.GATHERING: return "Собирательство"
		Type.CONSTRUCTION: return "Строительство"
		Type.LOGISTICS: return "Логистика"
		Type.FORESTRY: return "Лесное дело"
		Type.MINING: return "Горное дело"
		Type.FARMING: return "Земледелие"
		Type.ANIMAL_HUSBANDRY: return "Животноводство"
		Type.WOODWORKING: return "Деревообработка"
		Type.STONEWORKING: return "Камнеобработка"
		Type.POTTERY: return "Гончарное дело"
		Type.WEAVING: return "Ткачество"
		Type.TAILORING: return "Портняжное дело"
		Type.MILLING: return "Мельничное дело"
		Type.COOKING: return "Кулинария"
		Type.CRAFTING: return "Ремесло"
		_: return ""

static func rank_for_xp(xp: int) -> Rank:
	for index in range(Balance.SKILL_RANK_XP.size() - 1, -1, -1):
		if xp >= Balance.SKILL_RANK_XP[index]: return index as Rank
	return Rank.PROFANE

static func rank_name(rank: Rank) -> String:
	match rank:
		Rank.PROFANE: return "Профан"
		Rank.NOVICE: return "Новичок"
		Rank.AMATEUR: return "Любитель"
		Rank.EXPERIENCED: return "Опытный"
		Rank.MASTER: return "Мастер"
		_: return ""

static func efficiency_percent(xp: int) -> float:
	return 100.0 + 50.0 * sqrt(float(clampi(xp, 0, Balance.MAX_SKILL_XP)) / Balance.MAX_SKILL_XP)

static func xp_gain(current: int, requested: int, training_cap: int = Balance.MAX_SKILL_XP) -> int:
	if current < 0 or requested <= 0 or training_cap < 0: return 0
	# Limit the addition before summing, including int64-sized requests.
	return mini(requested, maxi(0, mini(Balance.MAX_SKILL_XP, training_cap) - current))
