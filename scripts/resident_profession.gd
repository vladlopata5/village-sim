extends RefCounted
## Assigned profession is resident data, separate from permanent skill XP.
enum Type { NONE, PORTER, GATHERER, BUILDER, LUMBERJACK, SAWYER, MINER }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		Type.GATHERER: return "Собиратель"
		Type.BUILDER: return "Строитель"
		Type.LUMBERJACK: return "Лесоруб"
		Type.SAWYER: return "Пильщик"
		Type.MINER: return "Камнедобытчик"
		_: return "Без профессии"
