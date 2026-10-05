extends RefCounted
## Assigned profession is data; it does not select behavior yet.
enum Type { NONE, PORTER, GATHERER }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		Type.GATHERER: return "Собиратель"
		_: return "Без профессии"
