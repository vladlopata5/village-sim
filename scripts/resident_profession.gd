extends RefCounted
## Assigned profession is data; it does not select behavior yet.
enum Type { NONE, PORTER }

static func display_name(profession: Type) -> String:
	match profession:
		Type.PORTER: return "Носильщик"
		_: return "Без профессии"
