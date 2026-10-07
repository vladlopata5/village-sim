extends RefCounted
## Assigned profession is data; it does not select behavior yet.
enum Type { NONE, PORTER, GATHERER, BUILDER }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		Type.GATHERER: return "Собиратель"
		Type.BUILDER: return "Строитель"
		_: return "Без профессии"
