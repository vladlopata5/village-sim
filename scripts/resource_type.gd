extends RefCounted
## Settlement resource categories, independent of building categories.
enum Type { FOOD, WOOD, LOG }

static func display_name(resource: Type) -> String:
	match resource:
		Type.FOOD: return "FOOD"
		Type.WOOD: return "Древесина"
		Type.LOG: return "Бревно"
		_: return "Ресурс"
