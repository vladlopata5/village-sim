extends RefCounted
## Assigned profession is resident data, separate from permanent skill XP.
enum Type { NONE, PORTER, GATHERER, BUILDER, LUMBERJACK, SAWYER, MINER, COOK, SHEPHERD, WEAVER, TAILOR, FARMER, MILLER, CLAY_DIGGER, POTTER, STONEMASON }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		Type.GATHERER: return "Собиратель"
		Type.BUILDER: return "Строитель"
		Type.LUMBERJACK: return "Лесоруб"
		Type.SAWYER: return "Пильщик"
		Type.MINER: return "Камнедобытчик"
		Type.COOK: return "Повар"
		Type.SHEPHERD: return "Пастух"
		Type.WEAVER: return "Ткач"
		Type.TAILOR: return "Портной"
		Type.FARMER: return "Фермер"
		Type.MILLER: return "Мельник"
		Type.CLAY_DIGGER: return "Глинокоп"
		Type.POTTER: return "Гончар"
		Type.STONEMASON: return "Каменотёс"
		_: return "Без профессии"
