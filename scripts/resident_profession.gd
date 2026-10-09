extends RefCounted
## Assigned profession is resident data, separate from permanent skill XP.
enum Type { NONE, PORTER, GATHERER, BUILDER, LUMBERJACK, SAWYER }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		Type.GATHERER: return "Собиратель"
		Type.BUILDER: return "Строитель"
		Type.LUMBERJACK: return "Лесоруб"
		Type.SAWYER: return "Пильщик"
		_: return "Без профессии"
